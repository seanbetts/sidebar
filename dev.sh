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

load_env() {
  if [[ -f ".env.local" ]]; then
    set -a
    source .env.local
    set +a
  elif [[ -f ".env" ]]; then
    set -a
    source .env
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
    lsof -iTCP:"${port}" -sTCP:LISTEN >/dev/null 2>&1
  else
    nc -z 127.0.0.1 "${port}" >/dev/null 2>&1
  fi
}

port_pid() {
  local port="$1"
  if ! command -v lsof >/dev/null 2>&1; then
    return 1
  fi
  lsof -t -iTCP:"${port}" -sTCP:LISTEN 2>/dev/null | head -n 1
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

ensure_port_available() {
  local port="$1"
  local role="$2"
  local pid
  local command

  if ! port_in_use "${port}"; then
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
  ensure_port_available 8001 backend
  echo "Starting backend..."
  if [[ ${use_doppler} -eq 1 ]]; then
    (cd backend && doppler run -- uv run uvicorn api.main:app --reload --port 8001 --host 0.0.0.0) >"${BACKEND_LOG}" 2>&1 &
  else
    (cd backend && uv run uvicorn api.main:app --reload --port 8001 --host 0.0.0.0) >"${BACKEND_LOG}" 2>&1 &
  fi
  echo $! >"${BACKEND_PID}"
}

start_frontend() {
  ensure_port_available 3000 frontend
  echo "Starting frontend..."
  if [[ ${use_doppler} -eq 1 ]]; then
    (cd frontend && doppler run -- npm run dev) >"${FRONTEND_LOG}" 2>&1 &
  else
    (cd frontend && npm run dev) >"${FRONTEND_LOG}" 2>&1 &
  fi
  echo $! >"${FRONTEND_PID}"
}

start_ingestion_worker() {
  echo "Starting ingestion worker..."
  if [[ ${use_doppler} -eq 1 ]]; then
    (cd backend && doppler run -- uv run python workers/ingestion_worker.py) >"${INGESTION_LOG}" 2>&1 &
  else
    (cd backend && uv run python workers/ingestion_worker.py) >"${INGESTION_LOG}" 2>&1 &
  fi
  echo $! >"${INGESTION_PID}"
}

stop_service() {
  local pid_file="$1"
  local name="$2"
  if [[ -f "${pid_file}" ]]; then
    local pid
    pid=$(cat "${pid_file}")
    if kill -0 "${pid}" >/dev/null 2>&1; then
      echo "Stopping ${name} (PID ${pid})..."
      stop_pid "${pid}"
    fi
    rm -f "${pid_file}"
  else
    echo "${name} is not running."
  fi
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
  if [[ -f "${pid_file}" ]]; then
    local pid
    pid=$(cat "${pid_file}")
    if kill -0 "${pid}" >/dev/null 2>&1; then
      echo "✓ ${name} running (PID: ${pid})"
      echo "  URL: ${url}"
      echo "  Logs: ${log_file}"
      return
    fi
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

case "${command}" in
  start)
    start_backend
    start_frontend
    start_ingestion_worker
    ;;
  stop)
    stop_service "${BACKEND_PID}" "backend"
    stop_service "${FRONTEND_PID}" "frontend"
    stop_service "${INGESTION_PID}" "ingestion worker"
    ;;
  restart)
    stop_service "${BACKEND_PID}" "backend"
    stop_service "${FRONTEND_PID}" "frontend"
    stop_service "${INGESTION_PID}" "ingestion worker"
    start_backend
    start_frontend
    start_ingestion_worker
    ;;
  cleanup)
    cleanup_services
    ;;
  status)
    status_service "${BACKEND_PID}" "Backend" "http://localhost:8001" "${BACKEND_LOG}"
    status_service "${FRONTEND_PID}" "Frontend" "http://localhost:3000" "${FRONTEND_LOG}"
    status_service "${INGESTION_PID}" "Ingestion worker" "n/a" "${INGESTION_LOG}"
    ;;
  logs)
    show_logs "${2:-}"
    ;;
  *)
    echo "Usage: ./dev.sh [start|stop|restart|cleanup|status|logs [backend|frontend|ingestion]]"
    exit 1
    ;;
esac
