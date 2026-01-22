#!/bin/bash
set -euo pipefail

BACKEND_LOG="/tmp/sidebar-backend.log"
FRONTEND_LOG="/tmp/sidebar-frontend.log"
INGESTION_LOG="/tmp/sidebar-ingestion-worker.log"
BACKEND_PID="/tmp/sidebar-backend.pid"
FRONTEND_PID="/tmp/sidebar-frontend.pid"
INGESTION_PID="/tmp/sidebar-ingestion-worker.pid"
REPO_ROOT="$(pwd)"
use_doppler=0
RESTART_LOCK="/tmp/sidebar-dev-restart.lock"

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

detect_doppler() {
  if command -v doppler >/dev/null 2>&1; then
    if [[ -n "${DOPPLER_TOKEN:-}" || -n "${DOPPLER_PROJECT:-}" || -n "${DOPPLER_CONFIG:-}" ]]; then
      use_doppler=1
    fi
  fi
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
  if ! command -v pgrep >/dev/null 2>&1; then
    return
  fi
  while read -r pid; do
    [[ -z "${pid}" ]] && continue
    [[ "${pid}" == "$$" ]] && continue
    command=$(pid_command "${pid}")
    if [[ "${command}" == *"./dev.sh restart"* ]]; then
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
      if [[ "${role}" == "backend" ]] && is_backend_process "${command}"; then
        echo "Cleaning up stale backend process on port ${port} (PID ${pid})..."
        stop_pid "${pid}"
      elif [[ "${role}" == "frontend" ]] && is_frontend_process "${command}"; then
        echo "Cleaning up stale frontend process on port ${port} (PID ${pid})..."
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
  if [[ "${role}" == "backend" ]] && is_backend_process "${command}"; then
    echo "Cleaning up stale backend process on port ${port} (PID ${pid})..."
    stop_pid "${pid}"
    return
  fi

  if [[ "${role}" == "frontend" ]] && is_frontend_process "${command}"; then
    echo "Cleaning up stale frontend process on port ${port} (PID ${pid})..."
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
      doppler run --preserve-env="SUPABASE_URL" -- uv run uvicorn api.main:app --reload --port 8001 --host 0.0.0.0
    else
      uv run uvicorn api.main:app --reload --port 8001 --host 0.0.0.0
    fi
  } || {
    echo "uv run failed; falling back to pip install with trusted hosts..."
    install_backend_deps_fallback
    if [[ ${use_doppler} -eq 1 ]]; then
      doppler run --preserve-env="SUPABASE_URL" -- "${REPO_ROOT}/backend/.venv/bin/python" -m uvicorn api.main:app --reload --port 8001 --host 0.0.0.0
    else
      "${REPO_ROOT}/backend/.venv/bin/python" -m uvicorn api.main:app --reload --port 8001 --host 0.0.0.0
    fi
  }) >"${BACKEND_LOG}" 2>&1 </dev/null &
  echo $! >"${BACKEND_PID}"
  for _ in {1..10}; do
    local pid
    pid=$(resolve_pid_for_port 8001 backend || true)
    if [[ -n "${pid}" ]]; then
      echo "${pid}" >"${BACKEND_PID}"
      break
    fi
    sleep 0.5
  done
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
    (cd frontend && doppler run --preserve-env="SUPABASE_URL" -- npm run dev) >"${FRONTEND_LOG}" 2>&1 </dev/null &
  else
    (cd frontend && npm run dev) >"${FRONTEND_LOG}" 2>&1 </dev/null &
  fi
  echo $! >"${FRONTEND_PID}"
  for _ in {1..10}; do
    local pid
    pid=$(resolve_pid_for_port 3000 frontend || true)
    if [[ -n "${pid}" ]]; then
      echo "${pid}" >"${FRONTEND_PID}"
      break
    fi
    sleep 0.5
  done
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
      doppler run --preserve-env="SUPABASE_URL" -- env PYTHONPATH=. PYTHONUNBUFFERED=1 uv run python workers/ingestion_worker.py
    else
      env PYTHONPATH=. PYTHONUNBUFFERED=1 uv run python workers/ingestion_worker.py
    fi
  } || {
    echo "uv run failed; falling back to venv for ingestion worker..."
    install_backend_deps_fallback
    if [[ ${use_doppler} -eq 1 ]]; then
      doppler run --preserve-env="SUPABASE_URL" -- env PYTHONPATH=. PYTHONUNBUFFERED=1 "${REPO_ROOT}/backend/.venv/bin/python" workers/ingestion_worker.py
    else
      env PYTHONPATH=. PYTHONUNBUFFERED=1 "${REPO_ROOT}/backend/.venv/bin/python" workers/ingestion_worker.py
    fi
  }) >"${INGESTION_LOG}" 2>&1 </dev/null &
  echo $! >"${INGESTION_PID}"
  for _ in {1..10}; do
    local pid
    pid=$(resolve_ingestion_pid || true)
    if [[ -n "${pid}" ]]; then
      echo "${pid}" >"${INGESTION_PID}"
      break
    fi
    sleep 0.5
  done
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

  if [[ -f "${INGESTION_PID}" ]]; then
    pid=$(cat "${INGESTION_PID}")
    if kill -0 "${pid}" >/dev/null 2>&1; then
      echo "Cleaning ingestion worker (PID ${pid})..."
      stop_pid "${pid}"
    fi
    rm -f "${INGESTION_PID}"
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
    *)
      echo "--- Backend logs (${BACKEND_LOG}) ---"
      tail -n 200 "${BACKEND_LOG}" || true
      echo "--- Frontend logs (${FRONTEND_LOG}) ---"
      tail -n 200 "${FRONTEND_LOG}" || true
      echo "--- Ingestion worker logs (${INGESTION_LOG}) ---"
      tail -n 200 "${INGESTION_LOG}" || true
      ;;
  esac
}

command="${1:-start}"

load_env
detect_doppler
ensure_restart_lock

case "${command}" in
  start)
    start_backend
    start_frontend
    start_ingestion_worker
    ;;
  stop)
    stop_service "${BACKEND_PID}" "backend" "backend" "8001"
    stop_service "${FRONTEND_PID}" "frontend" "frontend" "3000"
    stop_service "${INGESTION_PID}" "ingestion worker" "ingestion"
    ;;
  restart)
    cleanup_restart_processes
    stop_service "${BACKEND_PID}" "backend" "backend" "8001"
    stop_service "${FRONTEND_PID}" "frontend" "frontend" "3000"
    stop_service "${INGESTION_PID}" "ingestion worker" "ingestion"
    start_backend
    start_frontend
    start_ingestion_worker
    ;;
  cleanup)
    cleanup_services
    ;;
  status)
    status_service "${BACKEND_PID}" "Backend" "http://localhost:8001" "${BACKEND_LOG}" "backend"
    status_service "${FRONTEND_PID}" "Frontend" "http://localhost:3000" "${FRONTEND_LOG}" "frontend"
    status_service "${INGESTION_PID}" "Ingestion worker" "n/a" "${INGESTION_LOG}" "ingestion"
    ;;
  logs)
    show_logs "${2:-}"
    ;;
  *)
    echo "Usage: ./dev.sh [start|stop|restart|cleanup|status|logs [backend|frontend|ingestion]]"
    exit 1
    ;;
esac
