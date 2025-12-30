#!/bin/bash
set -euo pipefail

BACKEND_LOG="/tmp/sidebar-backend.log"
FRONTEND_LOG="/tmp/sidebar-frontend.log"
BACKEND_PID="/tmp/sidebar-backend.pid"
FRONTEND_PID="/tmp/sidebar-frontend.pid"

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

port_in_use() {
  local port="$1"
  if command -v lsof >/dev/null 2>&1; then
    lsof -iTCP:"${port}" -sTCP:LISTEN >/dev/null 2>&1
  else
    nc -z 127.0.0.1 "${port}" >/dev/null 2>&1
  fi
}

start_backend() {
  if port_in_use 8001; then
    echo "Port 8001 is already in use. Stop the running process first."
    exit 1
  fi
  echo "Starting backend..."
  (cd backend && uv run uvicorn api.main:app --reload --port 8001 --host 0.0.0.0) >"${BACKEND_LOG}" 2>&1 &
  echo $! >"${BACKEND_PID}"
}

start_frontend() {
  if port_in_use 3000; then
    echo "Port 3000 is already in use. Stop the running process first."
    exit 1
  fi
  echo "Starting frontend..."
  (cd frontend && npm run dev) >"${FRONTEND_LOG}" 2>&1 &
  echo $! >"${FRONTEND_PID}"
}

stop_service() {
  local pid_file="$1"
  local name="$2"
  if [[ -f "${pid_file}" ]]; then
    local pid
    pid=$(cat "${pid_file}")
    if kill -0 "${pid}" >/dev/null 2>&1; then
      echo "Stopping ${name} (PID ${pid})..."
      kill "${pid}"
      wait "${pid}" 2>/dev/null || true
    fi
    rm -f "${pid_file}"
  else
    echo "${name} is not running."
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
    *)
      echo "--- Backend logs (${BACKEND_LOG}) ---"
      tail -n 200 "${BACKEND_LOG}" || true
      echo "--- Frontend logs (${FRONTEND_LOG}) ---"
      tail -n 200 "${FRONTEND_LOG}" || true
      ;;
  esac
}

command="${1:-start}"

load_env

case "${command}" in
  start)
    start_backend
    start_frontend
    ;;
  stop)
    stop_service "${BACKEND_PID}" "backend"
    stop_service "${FRONTEND_PID}" "frontend"
    ;;
  restart)
    stop_service "${BACKEND_PID}" "backend"
    stop_service "${FRONTEND_PID}" "frontend"
    start_backend
    start_frontend
    ;;
  status)
    status_service "${BACKEND_PID}" "Backend" "http://localhost:8001" "${BACKEND_LOG}"
    status_service "${FRONTEND_PID}" "Frontend" "http://localhost:3000" "${FRONTEND_LOG}"
    ;;
  logs)
    show_logs "${2:-}"
    ;;
  *)
    echo "Usage: ./dev.sh [start|stop|restart|status|logs [backend|frontend]]"
    exit 1
    ;;
esac
