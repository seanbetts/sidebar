#!/bin/bash
# sideBar local dev orchestrator.
#
# Run from repository root:
#   ./dev.sh start
#
# Common commands:
#   ./dev.sh start
#     Start backend, frontend, ingestion worker, website processing worker, product docs, internal design docs, website, and Caddy proxy,
#     restart the local GitHub Actions runner, and ensure local test Postgres availability.
#     Proxy URLs (requires: brew install caddy):
#       - Website: http://trysidebar.localhost:8080
#       - App:     http://app.trysidebar.localhost:8080
#       - Docs:    http://docs.trysidebar.localhost:8080
#       - API:     http://api.trysidebar.localhost:8080
#     Direct ports (no proxy):
#       - Backend:  http://localhost:8001
#       - Frontend: http://localhost:3000
#       - Docs:     http://localhost:3001
#       - Design docs: http://localhost:3002
#       - Website:  http://localhost:5173
#   ./dev.sh stop
#     Stop all services managed by this script, including the local GitHub Actions runner.
#   ./dev.sh restart
#     Restart all services, including the local GitHub Actions runner.
#   ./dev.sh status
#     Show running status, including the local GitHub Actions runner, URLs, and log file locations.
#   ./dev.sh logs [backend|frontend|ingestion|website-worker|docs|design-docs|website|caddy]
#     Tail logs for one service or all services.
#
# Notes:
# - If .env and/or .env.local exist, they are loaded automatically.
# - If Doppler is installed and configured, services run through doppler.
# - Set SIDEBAR_DEV_TEST_DB=0 to skip local test DB setup/checks.
# - Set SIDEBAR_FORCE_RUNNER_RESTART=1 to restart the GitHub runner even if it is busy.
set -euo pipefail

BACKEND_LOG="/tmp/sidebar-backend.log"
FRONTEND_LOG="/tmp/sidebar-frontend.log"
INGESTION_LOG="/tmp/sidebar-ingestion-worker.log"
WEBSITE_WORKER_LOG="/tmp/sidebar-website-processing-worker.log"
DOCS_LOG="/tmp/sidebar-docs.log"
DESIGN_DOCS_LOG="/tmp/sidebar-design-docs.log"
WEBSITE_LOG="/tmp/sidebar-website.log"
BACKEND_PID="/tmp/sidebar-backend.pid"
FRONTEND_PID="/tmp/sidebar-frontend.pid"
INGESTION_PID="/tmp/sidebar-ingestion-worker.pid"
WEBSITE_WORKER_PID="/tmp/sidebar-website-processing-worker.pid"
DOCS_PID="/tmp/sidebar-docs.pid"
DESIGN_DOCS_PID="/tmp/sidebar-design-docs.pid"
WEBSITE_PID="/tmp/sidebar-website.pid"
CADDY_LOG="/tmp/sidebar-caddy.log"
CADDY_PID="/tmp/sidebar-caddy.pid"
REPO_ROOT="$(pwd)"
PRODUCT_DOCS_MINTLIFY_HOME="${HOME}/.sidebar/mintlify-product"
DESIGN_DOCS_MINTLIFY_HOME="${HOME}/.sidebar/mintlify-design"
TEST_DB_HOST="localhost"
TEST_DB_PORT="5433"
TEST_DB_NAME="sidebar_test"
TEST_DB_USER="sidebar"
TEST_DB_PASSWORD="sidebar_dev"
TEST_DB_URL="postgresql://sidebar:sidebar_dev@localhost:5433/sidebar_test"
TEST_DB_DATA_DIR="${HOME}/.sidebar/test-postgres"
TEST_DB_LOG="/tmp/sidebar-test-postgres.log"
use_doppler=0
RESTART_LOCK="/tmp/sidebar-dev-restart.lock"
STARTUP_DETECT_ATTEMPTS=40
STARTUP_DETECT_INTERVAL_SECONDS="0.5"
RUNNER_DIRS=(
  "/Users/sean/Coding/actions-runner-ios"
)

load_env() {
  if [[ -f ".env" ]]; then
    set -a
    source .env
    set +a
  fi
  if [[ -f ".env.local" ]]; then
    set -a
    source .env.local
    set +a
  fi
}

normalize_runtime_paths() {
  local default_skills_dir="${REPO_ROOT}/backend/skills"

  if [[ ! -d "${default_skills_dir}" ]]; then
    return
  fi

  if [[ -n "${SKILLS_DIR:-}" && ! -d "${SKILLS_DIR}" ]]; then
    echo "SKILLS_DIR does not exist (${SKILLS_DIR}); using ${default_skills_dir}."
    export SKILLS_DIR="${default_skills_dir}"
    return
  fi

  if [[ -z "${SKILLS_DIR:-}" ]]; then
    export SKILLS_DIR="${default_skills_dir}"
  fi
}

detect_doppler() {
  if command -v doppler >/dev/null 2>&1; then
    if [[ -n "${DOPPLER_TOKEN:-}" || -n "${DOPPLER_PROJECT:-}" || -n "${DOPPLER_CONFIG:-}" ]]; then
      use_doppler=1
    fi
  fi
}

runner_name() {
  local runner_dir="$1"
  basename "${runner_dir}"
}

runner_svc_path() {
  local runner_dir="$1"
  echo "${runner_dir}/svc.sh"
}

runner_is_force_restart_enabled() {
  case "${SIDEBAR_FORCE_RUNNER_RESTART:-0}" in
    1|true|TRUE|yes|YES|on|ON)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

runner_is_configured() {
  local runner_dir="$1"
  [[ -d "${runner_dir}" && -x "$(runner_svc_path "${runner_dir}")" ]]
}

for_each_runner() {
  local callback="$1"
  local runner_dir

  for runner_dir in "${RUNNER_DIRS[@]}"; do
    "${callback}" "${runner_dir}"
  done
}

runner_worker_pid() {
  local runner_dir="$1"
  local pid
  local proc_command

  if ! command -v pgrep >/dev/null 2>&1; then
    return 1
  fi

  while read -r pid; do
    [[ -z "${pid}" ]] && continue
    proc_command="$(pid_command "${pid}")"
    if [[ "${proc_command}" == *"${runner_dir}/bin/Runner.Worker"* ]]; then
      echo "${pid}"
      return 0
    fi
  done < <(pgrep -f "Runner.Worker" || true)

  return 1
}

runner_listener_pid() {
  local runner_dir="$1"
  local pid
  local proc_command

  if ! command -v pgrep >/dev/null 2>&1; then
    return 1
  fi

  while read -r pid; do
    [[ -z "${pid}" ]] && continue
    proc_command="$(pid_command "${pid}")"
    if [[ "${proc_command}" == *"${runner_dir}/bin/Runner.Listener"* ]]; then
      echo "${pid}"
      return 0
    fi
  done < <(pgrep -f "Runner.Listener" || true)

  return 1
}

runner_state() {
  local runner_dir="$1"

  if runner_worker_pid "${runner_dir}" >/dev/null; then
    echo "busy"
    return
  fi

  if runner_listener_pid "${runner_dir}" >/dev/null; then
    echo "idle"
    return
  fi

  echo "stopped"
}

restart_runner() {
  local runner_dir="$1"
  local runner_label
  local state
  runner_label="$(runner_name "${runner_dir}")"

  if ! runner_is_configured "${runner_dir}"; then
    echo "Skipping GitHub runner ${runner_label}, svc.sh not found."
    return
  fi

  state="$(runner_state "${runner_dir}")"
  if [[ "${state}" == "busy" ]] && ! runner_is_force_restart_enabled; then
    echo "Skipping GitHub runner ${runner_label}, runner is busy. Set SIDEBAR_FORCE_RUNNER_RESTART=1 to force."
    return
  fi

  echo "Restarting GitHub runner ${runner_label}..."
  (
    cd "${runner_dir}"
    ./svc.sh stop >/dev/null 2>&1 || true
    ./svc.sh start >/dev/null
  )
}

stop_runner() {
  local runner_dir="$1"
  local runner_label
  runner_label="$(runner_name "${runner_dir}")"

  if ! runner_is_configured "${runner_dir}"; then
    echo "Skipping GitHub runner ${runner_label}, svc.sh not found."
    return
  fi

  echo "Stopping GitHub runner ${runner_label}..."
  (
    cd "${runner_dir}"
    ./svc.sh stop >/dev/null 2>&1 || true
  )
}

status_runner() {
  local runner_dir="$1"
  local runner_label
  local state
  runner_label="$(runner_name "${runner_dir}")"

  if ! runner_is_configured "${runner_dir}"; then
    echo "✗ GitHub runner ${runner_label} not configured"
    return
  fi

  state="$(runner_state "${runner_dir}")"
  if [[ "${state}" == "busy" ]]; then
    echo "✓ GitHub runner ${runner_label} running"
    echo "  State: busy"
    echo "  Path: ${runner_dir}"
    return
  fi

  if [[ "${state}" == "idle" ]]; then
    echo "✓ GitHub runner ${runner_label} running"
    echo "  State: idle"
    echo "  Path: ${runner_dir}"
    return
  fi

  echo "✗ GitHub runner ${runner_label} not running"
  echo "  State: stopped"
  echo "  Path: ${runner_dir}"
}

is_test_db_enabled() {
  case "${SIDEBAR_DEV_TEST_DB:-1}" in
    0|false|FALSE|no|NO|off|OFF)
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

is_test_db_running() {
  if command -v pg_isready >/dev/null 2>&1; then
    pg_isready -h "${TEST_DB_HOST}" -p "${TEST_DB_PORT}" -U "${TEST_DB_USER}" -d "${TEST_DB_NAME}" >/dev/null 2>&1
    return $?
  fi

  if command -v nc >/dev/null 2>&1; then
    nc -z "${TEST_DB_HOST}" "${TEST_DB_PORT}" >/dev/null 2>&1
    return $?
  fi

  if command -v lsof >/dev/null 2>&1; then
    lsof -iTCP:"${TEST_DB_PORT}" -sTCP:LISTEN >/dev/null 2>&1
    return $?
  fi

  return 1
}

wait_for_test_db() {
  for _ in {1..30}; do
    if is_test_db_running; then
      return 0
    fi
    sleep 1
  done
  return 1
}

has_postgres_tools() {
  command -v initdb >/dev/null 2>&1 &&
    command -v pg_ctl >/dev/null 2>&1 &&
    command -v psql >/dev/null 2>&1 &&
    command -v pg_isready >/dev/null 2>&1
}

ensure_postgres_tools() {
  if has_postgres_tools; then
    return 0
  fi

  if command -v brew >/dev/null 2>&1; then
    local formula
    local bin_dir
    for formula in postgresql@17 postgresql@16 postgresql@15 postgresql@14 postgresql; do
      if brew list --formula "${formula}" >/dev/null 2>&1; then
        bin_dir="$(brew --prefix "${formula}")/bin"
        if [[ -d "${bin_dir}" ]]; then
          export PATH="${bin_dir}:${PATH}"
          break
        fi
      fi
    done
  fi

  has_postgres_tools
}

detect_test_db_admin_user() {
  local candidate
  for candidate in "${TEST_DB_USER}" "$(id -un)" postgres; do
    if psql -h "${TEST_DB_HOST}" -p "${TEST_DB_PORT}" -U "${candidate}" -d postgres \
      -tAc "SELECT 1" >/dev/null 2>&1; then
      echo "${candidate}"
      return 0
    fi
  done
  return 1
}

bootstrap_test_db_objects() {
  local admin_user="$1"
  local role_exists
  local db_exists

  role_exists=$(
    psql -h "${TEST_DB_HOST}" -p "${TEST_DB_PORT}" -U "${admin_user}" -d postgres \
      -tAc "SELECT 1 FROM pg_roles WHERE rolname='${TEST_DB_USER}'" | tr -d '[:space:]'
  )
  if [[ "${role_exists}" != "1" ]]; then
    psql -h "${TEST_DB_HOST}" -p "${TEST_DB_PORT}" -U "${admin_user}" -d postgres \
      -c "CREATE ROLE ${TEST_DB_USER} WITH LOGIN PASSWORD '${TEST_DB_PASSWORD}';" >/dev/null
  else
    psql -h "${TEST_DB_HOST}" -p "${TEST_DB_PORT}" -U "${admin_user}" -d postgres \
      -c "ALTER ROLE ${TEST_DB_USER} WITH LOGIN PASSWORD '${TEST_DB_PASSWORD}';" >/dev/null
  fi

  db_exists=$(
    psql -h "${TEST_DB_HOST}" -p "${TEST_DB_PORT}" -U "${admin_user}" -d postgres \
      -tAc "SELECT 1 FROM pg_database WHERE datname='${TEST_DB_NAME}'" | tr -d '[:space:]'
  )
  if [[ "${db_exists}" != "1" ]]; then
    psql -h "${TEST_DB_HOST}" -p "${TEST_DB_PORT}" -U "${admin_user}" -d postgres \
      -c "CREATE DATABASE ${TEST_DB_NAME} OWNER ${TEST_DB_USER};" >/dev/null
  fi
}

start_test_db_native() {
  local admin_user

  if ! ensure_postgres_tools; then
    echo "PostgreSQL tools not found (initdb/pg_ctl/psql/pg_isready)."
    echo "Install with: brew install postgresql@16"
    return 1
  fi

  mkdir -p "$(dirname "${TEST_DB_DATA_DIR}")"
  if [[ ! -f "${TEST_DB_DATA_DIR}/PG_VERSION" ]]; then
    echo "Initializing local test DB cluster at ${TEST_DB_DATA_DIR}..."
    initdb -D "${TEST_DB_DATA_DIR}" --username="${TEST_DB_USER}" --auth=trust >/dev/null
  fi

  if pg_ctl -D "${TEST_DB_DATA_DIR}" status >/dev/null 2>&1; then
    pg_ctl -D "${TEST_DB_DATA_DIR}" -m fast stop >/dev/null 2>&1 || true
  fi

  echo "Starting local test DB cluster on port ${TEST_DB_PORT}..."
  if ! pg_ctl -D "${TEST_DB_DATA_DIR}" -l "${TEST_DB_LOG}" -o "-p ${TEST_DB_PORT}" start >/dev/null 2>&1; then
    return 1
  fi

  if ! wait_for_test_db; then
    return 1
  fi

  if ! admin_user="$(detect_test_db_admin_user)"; then
    return 1
  fi

  bootstrap_test_db_objects "${admin_user}"
  wait_for_test_db
}

print_native_test_db_help() {
  echo "Run native local PostgreSQL on localhost:${TEST_DB_PORT} (${TEST_DB_NAME})."
  echo "If PostgreSQL is missing, install with: brew install postgresql@16"
}

ensure_test_db() {
  if ! is_test_db_enabled; then
    echo "Skipping local test DB setup/checks (SIDEBAR_DEV_TEST_DB=${SIDEBAR_DEV_TEST_DB:-1})."
    return
  fi

  if is_test_db_running; then
    echo "Local test DB detected (${TEST_DB_URL})."
    return
  fi

  if start_test_db_native; then
    return
  fi

  echo "Local test DB not detected at ${TEST_DB_URL}."
  echo "Could not auto-start it. DB-backed tests may skip."
  print_native_test_db_help
}

port_in_use() {
  local port="$1"
  if command -v lsof >/dev/null 2>&1; then
    if lsof -iTCP:"${port}" -sTCP:LISTEN >/dev/null 2>&1; then
      return 0
    fi
    return 1
  else
    if nc -z 127.0.0.1 "${port}" >/dev/null 2>&1; then
      return 0
    fi
    return 1
  fi
}

install_backend_deps_fallback() {
  local venv="${REPO_ROOT}/backend/.venv"
  local deps_file="/tmp/sidebar-backend-deps.txt"

  if [[ ! -d "${venv}" ]]; then
    python3 -m venv "${venv}"
  fi

  if ! "${venv}/bin/python" -m pip --version >/dev/null 2>&1; then
    "${venv}/bin/python" -m ensurepip --upgrade
  fi

  "${venv}/bin/python" -c 'import tomllib, pathlib; data = tomllib.loads(pathlib.Path("pyproject.toml").read_text()); print("\n".join(data["project"]["dependencies"]))' >"${deps_file}"
  PIP_CONFIG_FILE=/dev/null PIP_USER=0 "${venv}/bin/python" -m pip install \
    --trusted-host pypi.org \
    --trusted-host pypi.python.org \
    --trusted-host files.pythonhosted.org \
    -r "${deps_file}"
}

port_pid() {
  local port="$1"
  if ! command -v lsof >/dev/null 2>&1; then
    return 1
  fi
  lsof -t -iTCP:"${port}" -sTCP:LISTEN 2>/dev/null | head -n 1 || true
}

port_pid_any() {
  local port="$1"
  if ! command -v lsof >/dev/null 2>&1; then
    return 1
  fi
  lsof -t -iTCP:"${port}" 2>/dev/null | head -n 1 || true
}

pid_command() {
  local pid="$1"
  ps -p "${pid}" -o command= 2>/dev/null || true
}

is_backend_process() {
  local command="$1"
  [[ "${command}" == *"uvicorn api.main:app"* ]] && [[ "${command}" == *"${REPO_ROOT}"* ]]
}

is_frontend_process() {
  local command="$1"
  if [[ "${command}" == *"npm run dev"* || "${command}" == *"vite dev"* ]]; then
    [[ "${command}" == *"${REPO_ROOT}/frontend"* || "${command}" == *"${REPO_ROOT}"* ]]
  else
    return 1
  fi
}

is_ingestion_process() {
  local command="$1"
  [[ "${command}" == *"workers/ingestion_worker.py"* ]] && [[ "${command}" == *"${REPO_ROOT}"* ]]
}

is_website_worker_process() {
  local command="$1"
  [[ "${command}" == *"workers/website_processing_worker.py"* ]] && [[ "${command}" == *"${REPO_ROOT}"* ]]
}

is_docs_process() {
  local command="$1"
  if [[ "${command}" == *"${REPO_ROOT}/docs/product"* ]]; then
    [[ "${command}" == *"mintlify"* || "${command}" == *"@mintlify/cli"* ]]
    return $?
  fi

  [[ "${command}" == *"mintlify"* || "${command}" == *"@mintlify/cli"* ]] &&
    [[ "${command}" == *"--port 3001"* ]]
}

is_design_docs_process() {
  local command="$1"
  if [[ "${command}" == *"${REPO_ROOT}/docs/design"* ]]; then
    [[ "${command}" == *"mintlify"* || "${command}" == *"@mintlify/cli"* ]]
    return $?
  fi

  [[ "${command}" == *"mintlify"* || "${command}" == *"@mintlify/cli"* ]] &&
    [[ "${command}" == *"--port 3002"* ]]
}

is_website_process() {
  local command="$1"
  if [[ "${command}" == *"npm run dev"* || "${command}" == *"vite dev"* ]]; then
    [[ "${command}" == *"${REPO_ROOT}/website"* ]]
  else
    return 1
  fi
}

is_caddy_process() {
  local command="$1"
  [[ "${command}" == *"caddy run"* ]] &&
    ([[ "${command}" == *"${REPO_ROOT}"* ]] ||
      [[ "${command}" == *"--config Caddyfile"* ]] ||
      [[ "${command}" == *"--config ${REPO_ROOT}/Caddyfile"* ]])
}

role_matches_command() {
  local role="$1"
  local command="$2"
  case "${role}" in
    backend)
      is_backend_process "${command}"
      ;;
    frontend)
      is_frontend_process "${command}"
      ;;
    ingestion)
      is_ingestion_process "${command}"
      ;;
    website-worker)
      is_website_worker_process "${command}"
      ;;
    docs)
      is_docs_process "${command}"
      ;;
    design-docs)
      is_design_docs_process "${command}"
      ;;
    website)
      is_website_process "${command}"
      ;;
    caddy)
      is_caddy_process "${command}"
      ;;
    *)
      return 1
      ;;
  esac
}

resolve_pid_for_port() {
  local port="$1"
  local role="$2"
  local pid
  local command
  pid=$(port_pid "${port}")
  if [[ -z "${pid}" ]]; then
    return 1
  fi
  command=$(pid_command "${pid}")
  if role_matches_command "${role}" "${command}"; then
    echo "${pid}"
    return 0
  fi
  return 1
}

wait_for_role_port() {
  local port="$1"
  local role="$2"
  local pid_file="$3"
  local pid
  local any_pid
  local attempt

  for ((attempt = 1; attempt <= STARTUP_DETECT_ATTEMPTS; attempt++)); do
    pid=$(resolve_pid_for_port "${port}" "${role}" || true)
    if [[ -n "${pid}" ]]; then
      echo "${pid}" >"${pid_file}"
      return 0
    fi

    # During startup/reload, strict command matching can lag behind the actual
    # listener becoming available.
    if port_in_use "${port}"; then
      any_pid=$(port_pid "${port}")
      if [[ -n "${any_pid}" ]]; then
        echo "${any_pid}" >"${pid_file}"
        return 0
      fi
    fi

    sleep "${STARTUP_DETECT_INTERVAL_SECONDS}"
  done

  return 1
}

wait_for_ingestion_process() {
  local pid_file="$1"
  local pid
  local attempt

  for ((attempt = 1; attempt <= STARTUP_DETECT_ATTEMPTS; attempt++)); do
    pid=$(resolve_ingestion_pid || true)
    if [[ -n "${pid}" ]]; then
      echo "${pid}" >"${pid_file}"
      return 0
    fi
    sleep "${STARTUP_DETECT_INTERVAL_SECONDS}"
  done

  return 1
}

resolve_ingestion_pid() {
  if ! command -v pgrep >/dev/null 2>&1; then
    return 1
  fi
  local pid
  local command
  while read -r pid; do
    [[ -z "${pid}" ]] && continue
    command=$(pid_command "${pid}")
    if is_ingestion_process "${command}"; then
      echo "${pid}"
      return 0
    fi
  done < <(pgrep -f "workers/ingestion_worker.py" || true)
  return 1
}

wait_for_website_worker_process() {
  local pid_file="$1"
  local pid
  local attempt

  for ((attempt = 1; attempt <= STARTUP_DETECT_ATTEMPTS; attempt++)); do
    pid=$(resolve_website_worker_pid || true)
    if [[ -n "${pid}" ]]; then
      echo "${pid}" >"${pid_file}"
      return 0
    fi
    sleep "${STARTUP_DETECT_INTERVAL_SECONDS}"
  done

  return 1
}

resolve_website_worker_pid() {
  if ! command -v pgrep >/dev/null 2>&1; then
    return 1
  fi
  local pid
  local command
  while read -r pid; do
    [[ -z "${pid}" ]] && continue
    command=$(pid_command "${pid}")
    if is_website_worker_process "${command}"; then
      echo "${pid}"
      return 0
    fi
  done < <(pgrep -f "workers/website_processing_worker.py" || true)
  return 1
}

stop_pid() {
  local pid="$1"
  if kill -0 "${pid}" >/dev/null 2>&1; then
    kill "${pid}"
    sleep 1
  fi
  if kill -0 "${pid}" >/dev/null 2>&1; then
    kill -9 "${pid}" || true
  fi
}

cleanup_restart_processes() {
  local pid
  local proc_command
  if ! command -v pgrep >/dev/null 2>&1; then
    return
  fi
  while read -r pid; do
    [[ -z "${pid}" ]] && continue
    [[ "${pid}" == "$$" ]] && continue
    proc_command=$(pid_command "${pid}")
    if [[ "${proc_command}" == *"./dev.sh restart"* ]]; then
      echo "Cleaning stale restart process (PID ${pid})..."
      stop_pid "${pid}"
    fi
  done < <(pgrep -f "./dev.sh restart" || true)
}

ensure_restart_lock() {
  if [[ "${command}" != "restart" ]]; then
    return
  fi
  cleanup_restart_processes
  if [[ -f "${RESTART_LOCK}" ]]; then
    local pid
    pid=$(cat "${RESTART_LOCK}")
    if [[ -n "${pid}" ]] && kill -0 "${pid}" >/dev/null 2>&1; then
      echo "Restart already running (PID ${pid})."
      exit 1
    fi
  fi
  echo "$$" >"${RESTART_LOCK}"
  trap 'rm -f "${RESTART_LOCK}"' EXIT
}

ensure_port_available() {
  local port="$1"
  local role="$2"
  local pid
  local command

  if ! port_in_use "${port}"; then
    pid=$(port_pid_any "${port}")
    if [[ -n "${pid}" ]]; then
      command=$(pid_command "${pid}")
      if role_matches_command "${role}" "${command}"; then
        echo "Cleaning up stale ${role} process on port ${port} (PID ${pid})..."
        stop_pid "${pid}"
      fi
    fi
    return
  fi

  pid=$(port_pid "${port}")
  if [[ -z "${pid}" ]]; then
    echo "Port ${port} is already in use. Stop the running process first."
    exit 1
  fi

  command=$(pid_command "${pid}")
  if role_matches_command "${role}" "${command}"; then
    echo "Cleaning up stale ${role} process on port ${port} (PID ${pid})..."
    stop_pid "${pid}"
    return
  fi

  echo "Port ${port} is in use by another process:"
  echo "  PID: ${pid}"
  echo "  CMD: ${command}"
  echo "Stop it manually or choose a different port."
  exit 1
}

start_backend() {
  if [[ "${command}" == "start" ]]; then
    local existing_pid
    existing_pid=$(resolve_pid_for_port 8001 backend || true)
    if [[ -n "${existing_pid}" ]]; then
      echo "Backend already running (PID ${existing_pid})."
      echo "${existing_pid}" >"${BACKEND_PID}"
      return
    fi
  fi
  ensure_port_available 8001 backend
  echo "Starting backend..."
  (cd backend && {
    if [[ ${use_doppler} -eq 1 ]]; then
      doppler run --preserve-env="SUPABASE_URL,LOG_REQUESTS" -- uv run uvicorn api.main:app --reload --port 8001 --host 0.0.0.0
    else
      uv run uvicorn api.main:app --reload --port 8001 --host 0.0.0.0
    fi
  } || {
    echo "uv run failed; falling back to pip install with trusted hosts..."
    install_backend_deps_fallback
    if [[ ${use_doppler} -eq 1 ]]; then
      doppler run --preserve-env="SUPABASE_URL,LOG_REQUESTS" -- "${REPO_ROOT}/backend/.venv/bin/python" -m uvicorn api.main:app --reload --port 8001 --host 0.0.0.0
    else
      "${REPO_ROOT}/backend/.venv/bin/python" -m uvicorn api.main:app --reload --port 8001 --host 0.0.0.0
    fi
  }) >"${BACKEND_LOG}" 2>&1 </dev/null &
  echo $! >"${BACKEND_PID}"
  if ! wait_for_role_port 8001 backend "${BACKEND_PID}"; then
    echo "Backend failed to bind to port 8001. Check logs: ${BACKEND_LOG}"
  fi
}

start_frontend() {
  if [[ "${command}" == "start" ]]; then
    local existing_pid
    existing_pid=$(resolve_pid_for_port 3000 frontend || true)
    if [[ -n "${existing_pid}" ]]; then
      echo "Frontend already running (PID ${existing_pid})."
      echo "${existing_pid}" >"${FRONTEND_PID}"
      return
    fi
  fi
  ensure_port_available 3000 frontend
  echo "Starting frontend..."
  if [[ ${use_doppler} -eq 1 ]]; then
    (cd frontend && doppler run --preserve-env="SUPABASE_URL" -- npm run dev -- --host 0.0.0.0 --port 3000 --strictPort) >"${FRONTEND_LOG}" 2>&1 </dev/null &
  else
    (cd frontend && npm run dev -- --host 0.0.0.0 --port 3000 --strictPort) >"${FRONTEND_LOG}" 2>&1 </dev/null &
  fi
  echo $! >"${FRONTEND_PID}"
  if ! wait_for_role_port 3000 frontend "${FRONTEND_PID}"; then
    echo "Frontend failed to bind to port 3000. Check logs: ${FRONTEND_LOG}"
  fi
}

start_docs() {
  if [[ "${command}" == "start" ]]; then
    local existing_pid
    existing_pid=$(resolve_pid_for_port 3001 docs || true)
    if [[ -n "${existing_pid}" ]]; then
      echo "Docs already running (PID ${existing_pid})."
      echo "${existing_pid}" >"${DOCS_PID}"
      return
    fi
  fi
  ensure_port_available 3001 docs
  echo "Starting docs..."
  mkdir -p "${PRODUCT_DOCS_MINTLIFY_HOME}"
  (cd "${REPO_ROOT}/docs/product" && HOME="${PRODUCT_DOCS_MINTLIFY_HOME}" mintlify dev --port 3001 --no-open) >"${DOCS_LOG}" 2>&1 </dev/null &
  echo $! >"${DOCS_PID}"
  if ! wait_for_role_port 3001 docs "${DOCS_PID}"; then
    echo "Docs failed to bind to port 3001. Check logs: ${DOCS_LOG}"
  fi
}

start_design_docs() {
  if [[ "${command}" == "start" ]]; then
    local existing_pid
    existing_pid=$(resolve_pid_for_port 3002 design-docs || true)
    if [[ -n "${existing_pid}" ]]; then
      echo "Design docs already running (PID ${existing_pid})."
      echo "${existing_pid}" >"${DESIGN_DOCS_PID}"
      return
    fi
  fi
  ensure_port_available 3002 design-docs
  echo "Starting design docs..."
  mkdir -p "${DESIGN_DOCS_MINTLIFY_HOME}"
  (cd "${REPO_ROOT}/docs/design" && HOME="${DESIGN_DOCS_MINTLIFY_HOME}" mintlify dev --port 3002 --no-open) >"${DESIGN_DOCS_LOG}" 2>&1 </dev/null &
  echo $! >"${DESIGN_DOCS_PID}"
  if ! wait_for_role_port 3002 design-docs "${DESIGN_DOCS_PID}"; then
    echo "Design docs failed to bind to port 3002. Check logs: ${DESIGN_DOCS_LOG}"
  fi
}

start_website() {
  if [[ "${command}" == "start" ]]; then
    local existing_pid
    existing_pid=$(resolve_pid_for_port 5173 website || true)
    if [[ -n "${existing_pid}" ]]; then
      echo "Website already running (PID ${existing_pid})."
      echo "${existing_pid}" >"${WEBSITE_PID}"
      return
    fi
  fi
  ensure_port_available 5173 website
  echo "Starting website..."
  (cd website && npm run dev -- --host 0.0.0.0 --port 5173 --strictPort) >"${WEBSITE_LOG}" 2>&1 </dev/null &
  echo $! >"${WEBSITE_PID}"
  if ! wait_for_role_port 5173 website "${WEBSITE_PID}"; then
    echo "Website failed to bind to port 5173. Check logs: ${WEBSITE_LOG}"
  fi
}

start_caddy() {
  if ! command -v caddy >/dev/null 2>&1; then
    echo "Caddy not installed — skipping proxy (install with: brew install caddy)"
    return
  fi
  if [[ "${command}" == "start" ]]; then
    local existing_pid
    existing_pid=$(resolve_pid_for_port 8080 caddy || true)
    if [[ -n "${existing_pid}" ]]; then
      echo "Caddy proxy already running (PID ${existing_pid})."
      echo "${existing_pid}" >"${CADDY_PID}"
      return
    fi
  fi
  ensure_port_available 8080 caddy
  echo "Starting Caddy proxy..."
  (cd "${REPO_ROOT}" && caddy run --config Caddyfile) >"${CADDY_LOG}" 2>&1 </dev/null &
  echo $! >"${CADDY_PID}"
  if ! wait_for_role_port 8080 caddy "${CADDY_PID}"; then
    echo "Caddy proxy failed to bind to port 8080. Check logs: ${CADDY_LOG}"
  fi
}

start_ingestion_worker() {
  if [[ "${command}" == "start" ]]; then
    local existing_pid
    existing_pid=$(resolve_ingestion_pid || true)
    if [[ -n "${existing_pid}" ]]; then
      echo "Ingestion worker already running (PID ${existing_pid})."
      echo "${existing_pid}" >"${INGESTION_PID}"
      return
    fi
  fi
  cleanup_ingestion_workers
  echo "Starting ingestion worker..."
  (cd backend && {
    if [[ ${use_doppler} -eq 1 ]]; then
      doppler run --preserve-env="SUPABASE_URL,LOG_REQUESTS" -- env PYTHONPATH=. PYTHONUNBUFFERED=1 uv run python workers/ingestion_worker.py
    else
      env PYTHONPATH=. PYTHONUNBUFFERED=1 uv run python workers/ingestion_worker.py
    fi
  } || {
    echo "uv run failed; falling back to venv for ingestion worker..."
    install_backend_deps_fallback
    if [[ ${use_doppler} -eq 1 ]]; then
      doppler run --preserve-env="SUPABASE_URL,LOG_REQUESTS" -- env PYTHONPATH=. PYTHONUNBUFFERED=1 "${REPO_ROOT}/backend/.venv/bin/python" workers/ingestion_worker.py
    else
      env PYTHONPATH=. PYTHONUNBUFFERED=1 "${REPO_ROOT}/backend/.venv/bin/python" workers/ingestion_worker.py
    fi
  }) >"${INGESTION_LOG}" 2>&1 </dev/null &
  echo $! >"${INGESTION_PID}"
  if ! wait_for_ingestion_process "${INGESTION_PID}"; then
    echo "Ingestion worker did not stay running. Check logs: ${INGESTION_LOG}"
  fi
}

cleanup_ingestion_workers() {
  local pid
  local command

  if command -v pgrep >/dev/null 2>&1; then
    while read -r pid; do
      [[ -z "${pid}" ]] && continue
      command=$(pid_command "${pid}")
      if [[ "${command}" == *"workers/ingestion_worker.py"* ]] && [[ "${command}" == *"${REPO_ROOT}"* ]]; then
        echo "Cleaning ingestion worker process (PID ${pid})..."
        stop_pid "${pid}"
      fi
    done < <(pgrep -f "workers/ingestion_worker.py" || true)
  fi
}

start_website_worker() {
  if [[ "${command}" == "start" ]]; then
    local existing_pid
    existing_pid=$(resolve_website_worker_pid || true)
    if [[ -n "${existing_pid}" ]]; then
      echo "Website processing worker already running (PID ${existing_pid})."
      echo "${existing_pid}" >"${WEBSITE_WORKER_PID}"
      return
    fi
  fi
  cleanup_website_workers
  echo "Starting website processing worker..."
  (cd backend && {
    if [[ ${use_doppler} -eq 1 ]]; then
      doppler run --preserve-env="SUPABASE_URL,LOG_REQUESTS" -- env PYTHONPATH=. PYTHONUNBUFFERED=1 uv run python workers/website_processing_worker.py
    else
      env PYTHONPATH=. PYTHONUNBUFFERED=1 uv run python workers/website_processing_worker.py
    fi
  } || {
    echo "uv run failed; falling back to venv for website processing worker..."
    install_backend_deps_fallback
    if [[ ${use_doppler} -eq 1 ]]; then
      doppler run --preserve-env="SUPABASE_URL,LOG_REQUESTS" -- env PYTHONPATH=. PYTHONUNBUFFERED=1 "${REPO_ROOT}/backend/.venv/bin/python" workers/website_processing_worker.py
    else
      env PYTHONPATH=. PYTHONUNBUFFERED=1 "${REPO_ROOT}/backend/.venv/bin/python" workers/website_processing_worker.py
    fi
  }) >"${WEBSITE_WORKER_LOG}" 2>&1 </dev/null &
  echo $! >"${WEBSITE_WORKER_PID}"
  if ! wait_for_website_worker_process "${WEBSITE_WORKER_PID}"; then
    echo "Website processing worker did not stay running. Check logs: ${WEBSITE_WORKER_LOG}"
  fi
}

cleanup_website_workers() {
  local pid
  local command

  if command -v pgrep >/dev/null 2>&1; then
    while read -r pid; do
      [[ -z "${pid}" ]] && continue
      command=$(pid_command "${pid}")
      if [[ "${command}" == *"workers/website_processing_worker.py"* ]] && [[ "${command}" == *"${REPO_ROOT}"* ]]; then
        echo "Cleaning website processing worker (PID ${pid})..."
        stop_pid "${pid}"
      fi
    done < <(pgrep -f "workers/website_processing_worker.py" || true)
  fi
}

stop_service() {
  local pid_file="$1"
  local name="$2"
  local role="${3:-}"
  local port="${4:-}"
  local pid=""

  if [[ -f "${pid_file}" ]]; then
    pid=$(cat "${pid_file}")
    if kill -0 "${pid}" >/dev/null 2>&1; then
      echo "Stopping ${name} (PID ${pid})..."
      stop_pid "${pid}"
      rm -f "${pid_file}"
      return
    fi
  fi

  if [[ -n "${role}" ]]; then
    if [[ "${role}" == "ingestion" ]]; then
      pid=$(resolve_ingestion_pid || true)
    elif [[ -n "${port}" ]]; then
      pid=$(resolve_pid_for_port "${port}" "${role}" || true)
    fi
  fi

  if [[ -n "${pid}" ]]; then
    echo "Stopping ${name} (PID ${pid})..."
    stop_pid "${pid}"
    rm -f "${pid_file}"
    return
  fi

  echo "${name} is not running."
  rm -f "${pid_file}"
}

stop_service_quiet() {
  local pid_file="$1"
  local name="$2"
  local role="${3:-}"
  local port="${4:-}"
  local pid=""

  if [[ -f "${pid_file}" ]]; then
    pid=$(cat "${pid_file}")
    if kill -0 "${pid}" >/dev/null 2>&1; then
      echo "Stopping ${name} (PID ${pid})..."
      stop_pid "${pid}"
      rm -f "${pid_file}"
      return
    fi
  fi

  if [[ -n "${role}" ]]; then
    if [[ "${role}" == "ingestion" ]]; then
      pid=$(resolve_ingestion_pid || true)
    elif [[ -n "${port}" ]]; then
      pid=$(resolve_pid_for_port "${port}" "${role}" || true)
    fi
  fi

  if [[ -n "${pid}" ]]; then
    echo "Stopping ${name} (PID ${pid})..."
    stop_pid "${pid}"
  fi
  rm -f "${pid_file}"
}

cleanup_services() {
  local pid
  local command

  if ! command -v lsof >/dev/null 2>&1; then
    echo "cleanup requires lsof to be installed."
    exit 1
  fi

  for pid in $(lsof -t -iTCP:8001 -sTCP:LISTEN 2>/dev/null || true); do
    command=$(pid_command "${pid}")
    if is_backend_process "${command}"; then
      echo "Cleaning backend process (PID ${pid})..."
      stop_pid "${pid}"
    fi
  done

  for pid in $(lsof -t -iTCP:3000 -sTCP:LISTEN 2>/dev/null || true); do
    command=$(pid_command "${pid}")
    if is_frontend_process "${command}"; then
      echo "Cleaning frontend process (PID ${pid})..."
      stop_pid "${pid}"
    fi
  done

  for pid in $(lsof -t -iTCP:3001 -sTCP:LISTEN 2>/dev/null || true); do
    command=$(pid_command "${pid}")
    if is_docs_process "${command}"; then
      echo "Cleaning docs process (PID ${pid})..."
      stop_pid "${pid}"
    fi
  done

  for pid in $(lsof -t -iTCP:3002 -sTCP:LISTEN 2>/dev/null || true); do
    command=$(pid_command "${pid}")
    if is_design_docs_process "${command}"; then
      echo "Cleaning design docs process (PID ${pid})..."
      stop_pid "${pid}"
    fi
  done

  for pid in $(lsof -t -iTCP:5173 -sTCP:LISTEN 2>/dev/null || true); do
    command=$(pid_command "${pid}")
    if is_website_process "${command}"; then
      echo "Cleaning website process (PID ${pid})..."
      stop_pid "${pid}"
    fi
  done

  for pid in $(lsof -t -iTCP:8080 -sTCP:LISTEN 2>/dev/null || true); do
    command=$(pid_command "${pid}")
    if is_caddy_process "${command}"; then
      echo "Cleaning Caddy proxy process (PID ${pid})..."
      stop_pid "${pid}"
    fi
  done

  if [[ -f "${INGESTION_PID}" ]]; then
    pid=$(cat "${INGESTION_PID}")
    if kill -0 "${pid}" >/dev/null 2>&1; then
      echo "Cleaning ingestion worker (PID ${pid})..."
      stop_pid "${pid}"
    fi
    rm -f "${INGESTION_PID}"
  fi

  if [[ -f "${WEBSITE_WORKER_PID}" ]]; then
    pid=$(cat "${WEBSITE_WORKER_PID}")
    if kill -0 "${pid}" >/dev/null 2>&1; then
      echo "Cleaning website processing worker (PID ${pid})..."
      stop_pid "${pid}"
    fi
    rm -f "${WEBSITE_WORKER_PID}"
  fi

}

status_service() {
  local pid_file="$1"
  local name="$2"
  local url="$3"
  local log_file="$4"
  local role="${5:-}"
  local pid=""
  if [[ -f "${pid_file}" ]]; then
    pid=$(cat "${pid_file}")
    if kill -0 "${pid}" >/dev/null 2>&1; then
      local command
      command=$(pid_command "${pid}")
      if [[ -n "${role}" ]] && ! role_matches_command "${role}" "${command}"; then
        pid=""
      fi
    else
      pid=""
    fi
  fi

  if [[ -z "${pid}" && -n "${role}" ]]; then
    if [[ "${role}" == "backend" ]]; then
      pid=$(resolve_pid_for_port 8001 backend || true)
    elif [[ "${role}" == "frontend" ]]; then
      pid=$(resolve_pid_for_port 3000 frontend || true)
    elif [[ "${role}" == "ingestion" ]]; then
      pid=$(resolve_ingestion_pid || true)
    elif [[ "${role}" == "website-worker" ]]; then
      pid=$(resolve_website_worker_pid || true)
    elif [[ "${role}" == "docs" ]]; then
      pid=$(resolve_pid_for_port 3001 docs || true)
    elif [[ "${role}" == "design-docs" ]]; then
      pid=$(resolve_pid_for_port 3002 design-docs || true)
    elif [[ "${role}" == "website" ]]; then
      pid=$(resolve_pid_for_port 5173 website || true)
    elif [[ "${role}" == "caddy" ]]; then
      pid=$(resolve_pid_for_port 8080 caddy || true)
    fi
    if [[ -n "${pid}" ]]; then
      echo "${pid}" >"${pid_file}"
    fi
  fi

  if [[ -n "${pid}" ]]; then
    echo "✓ ${name} running (PID: ${pid})"
    echo "  URL: ${url}"
    echo "  Logs: ${log_file}"
    return
  fi

  echo "✗ ${name} not running"
}

status_test_db() {
  if ! is_test_db_enabled; then
    echo "- Local test DB setup/checks disabled (SIDEBAR_DEV_TEST_DB=${SIDEBAR_DEV_TEST_DB:-1})."
    return
  fi

  if is_test_db_running; then
    echo "✓ Local test DB running (${TEST_DB_URL})"
    return
  fi

  echo "✗ Local test DB not running"
  echo "  Expected: ${TEST_DB_URL}"
  echo "  Start the dedicated local test cluster with: ./dev.sh restart"
  echo "  (It will auto-bootstrap when PostgreSQL tools are installed.)"
  echo "  Install package if needed: brew install postgresql@16"
}

show_logs() {
  local target="$1"
  case "${target}" in
    backend)
      tail -n 200 "${BACKEND_LOG}" || true
      ;;
    frontend)
      tail -n 200 "${FRONTEND_LOG}" || true
      ;;
    ingestion)
      tail -n 200 "${INGESTION_LOG}" || true
      ;;
    website-worker)
      tail -n 200 "${WEBSITE_WORKER_LOG}" || true
      ;;
    docs)
      tail -n 200 "${DOCS_LOG}" || true
      ;;
    design-docs)
      tail -n 200 "${DESIGN_DOCS_LOG}" || true
      ;;
    website)
      tail -n 200 "${WEBSITE_LOG}" || true
      ;;
    caddy)
      tail -n 200 "${CADDY_LOG}" || true
      ;;
    *)
      echo "--- Backend logs (${BACKEND_LOG}) ---"
      tail -n 200 "${BACKEND_LOG}" || true
      echo "--- Frontend logs (${FRONTEND_LOG}) ---"
      tail -n 200 "${FRONTEND_LOG}" || true
      echo "--- Ingestion worker logs (${INGESTION_LOG}) ---"
      tail -n 200 "${INGESTION_LOG}" || true
      echo "--- Website processing worker logs (${WEBSITE_WORKER_LOG}) ---"
      tail -n 200 "${WEBSITE_WORKER_LOG}" || true
      echo "--- Docs logs (${DOCS_LOG}) ---"
      tail -n 200 "${DOCS_LOG}" || true
      echo "--- Design docs logs (${DESIGN_DOCS_LOG}) ---"
      tail -n 200 "${DESIGN_DOCS_LOG}" || true
      echo "--- Website logs (${WEBSITE_LOG}) ---"
      tail -n 200 "${WEBSITE_LOG}" || true
      echo "--- Caddy proxy logs (${CADDY_LOG}) ---"
      tail -n 200 "${CADDY_LOG}" || true
      ;;
  esac
}

command="${1:-start}"

load_env
normalize_runtime_paths
detect_doppler
ensure_restart_lock

case "${command}" in
  start)
    for_each_runner restart_runner
    ensure_test_db
    start_backend
    start_frontend
    start_ingestion_worker
    start_website_worker
    start_docs
    start_design_docs
    start_website
    start_caddy
    ;;
  stop)
    for_each_runner stop_runner
    stop_service "${BACKEND_PID}" "backend" "backend" "8001"
    stop_service "${FRONTEND_PID}" "frontend" "frontend" "3000"
    stop_service "${INGESTION_PID}" "ingestion worker" "ingestion"
    stop_service "${WEBSITE_WORKER_PID}" "website processing worker" "website-worker"
    stop_service "${DOCS_PID}" "docs" "docs" "3001"
    stop_service "${DESIGN_DOCS_PID}" "design docs" "design-docs" "3002"
    stop_service "${WEBSITE_PID}" "website" "website" "5173"
    stop_service "${CADDY_PID}" "Caddy proxy" "caddy" "8080"
    ;;
  restart)
    cleanup_restart_processes
    for_each_runner stop_runner
    stop_service "${BACKEND_PID}" "backend" "backend" "8001"
    stop_service "${FRONTEND_PID}" "frontend" "frontend" "3000"
    stop_service "${INGESTION_PID}" "ingestion worker" "ingestion"
    stop_service "${WEBSITE_WORKER_PID}" "website processing worker" "website-worker"
    stop_service "${DOCS_PID}" "docs" "docs" "3001"
    stop_service "${DESIGN_DOCS_PID}" "design docs" "design-docs" "3002"
    stop_service "${WEBSITE_PID}" "website" "website" "5173"
    stop_service "${CADDY_PID}" "Caddy proxy" "caddy" "8080"
    for_each_runner restart_runner
    ensure_test_db
    start_backend
    start_frontend
    start_ingestion_worker
    start_website_worker
    start_docs
    start_design_docs
    start_website
    start_caddy
    ;;
  cleanup)
    cleanup_services
    ;;
  status)
    for_each_runner status_runner
    status_service "${BACKEND_PID}" "Backend" "http://localhost:8001" "${BACKEND_LOG}" "backend"
    status_service "${FRONTEND_PID}" "Frontend" "http://app.trysidebar.localhost:3000" "${FRONTEND_LOG}" "frontend"
    status_service "${INGESTION_PID}" "Ingestion worker" "n/a" "${INGESTION_LOG}" "ingestion"
    status_service "${WEBSITE_WORKER_PID}" "Website processing worker" "n/a" "${WEBSITE_WORKER_LOG}" "website-worker"
    status_service "${DOCS_PID}" "Docs" "http://localhost:3001" "${DOCS_LOG}" "docs"
    status_service "${DESIGN_DOCS_PID}" "Design docs" "http://localhost:3002" "${DESIGN_DOCS_LOG}" "design-docs"
    status_service "${WEBSITE_PID}" "Website" "http://localhost:5173" "${WEBSITE_LOG}" "website"
    status_service "${CADDY_PID}" "Caddy proxy" "http://*.trysidebar.localhost:8080" "${CADDY_LOG}" "caddy"
    status_test_db
    ;;
  logs)
    show_logs "${2:-}"
    ;;
  *)
    echo "Usage: ./dev.sh [start|stop|restart|cleanup|status|logs [backend|frontend|ingestion|docs|design-docs|website|caddy]]"
    exit 1
    ;;
esac
