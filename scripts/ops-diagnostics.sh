#!/bin/bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PYTHON_BIN="${OPS_DIAGNOSTICS_PYTHON:-python}"

load_env() {
  if [[ -f "${REPO_ROOT}/.env.local" ]]; then
    set -a
    source "${REPO_ROOT}/.env.local"
    set +a
  elif [[ -f "${REPO_ROOT}/.env" ]]; then
    set -a
    source "${REPO_ROOT}/.env"
    set +a
  fi
}

usage() {
  cat <<'EOF'
Usage:
  ./scripts/ops-diagnostics.sh all [extra-args...]
  ./scripts/ops-diagnostics.sh <db|app|sentry|fly> [command] [extra-args...]
EOF
}

require_env() {
  local missing=0
  for name in "$@"; do
    if [[ -z "${!name:-}" ]]; then
      echo "Missing environment variable: ${name}"
      missing=1
    fi
  done
  return "${missing}"
}

run_target() {
  local target="$1"
  shift

  local command="summary"
  if [[ $# -gt 0 && "$1" != --* ]]; then
    command="$1"
    shift
  fi

  local script_path=""
  case "${target}" in
    db)
      require_env OPS_DB_URL || return 2
      script_path="${REPO_ROOT}/backend/scripts/db_diagnostics.py"
      ;;
    app)
      require_env OPS_DB_URL || return 2
      script_path="${REPO_ROOT}/backend/scripts/app_diagnostics.py"
      ;;
    sentry)
      require_env OPS_SENTRY_AUTH_TOKEN OPS_SENTRY_ORG OPS_SENTRY_PROJECT || return 2
      script_path="${REPO_ROOT}/backend/scripts/sentry_diagnostics.py"
      ;;
    fly)
      require_env OPS_FLY_API_TOKEN OPS_FLY_APP || return 2
      script_path="${REPO_ROOT}/backend/scripts/fly_diagnostics.py"
      ;;
    *)
      echo "Unknown target: ${target}"
      usage
      return 2
      ;;
  esac

  "${PYTHON_BIN}" "${script_path}" "${command}" "$@"
}

main() {
  load_env

  if [[ $# -lt 1 ]]; then
    usage
    return 2
  fi

  local target="$1"
  shift

  if [[ "${target}" == "all" ]]; then
    local overall_exit=0
    local name
    for name in db app sentry fly; do
      echo "== ${name} =="
      run_target "${name}" "$@"
      local exit_code=$?
      if [[ ${exit_code} -ne 0 ]]; then
        if [[ ${exit_code} -eq 2 && ${overall_exit} -eq 0 ]]; then
          overall_exit=2
        elif [[ ${exit_code} -eq 1 ]]; then
          overall_exit=1
        fi
      fi
    done
    return "${overall_exit}"
  fi

  run_target "${target}" "$@"
}

main "$@"
