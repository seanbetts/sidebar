#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/sync-assets.sh [--check]

Syncs canonical assets from /assets into all runtime targets.
Currently synced groups:
  - loading GIFs from assets/loading/

Options:
  --check   Verify target files match canonical assets without modifying files.
EOF
}

MODE="sync"
if [[ "${1:-}" == "--check" ]]; then
  MODE="check"
elif [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
elif [[ $# -gt 0 ]]; then
  usage
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out_of_sync=0

sync_file() {
  local src="$1"
  local rel_dst="$2"
  local dst="${ROOT_DIR}/${rel_dst}"

  if [[ ! -f "${src}" ]]; then
    echo "Missing canonical asset: ${src}" >&2
    exit 1
  fi

  if [[ "${MODE}" == "check" ]]; then
    if [[ ! -f "${dst}" ]] || ! cmp -s "${src}" "${dst}"; then
      echo "Out of sync: ${rel_dst}" >&2
      out_of_sync=1
    fi
    return
  fi

  mkdir -p "$(dirname "${dst}")"
  if [[ ! -f "${dst}" ]] || ! cmp -s "${src}" "${dst}"; then
    cp -f "${src}" "${dst}"
    echo "Updated ${rel_dst}"
  fi
}

# Group: loading GIFs
LIGHT_SRC="${ROOT_DIR}/assets/loading/loading-light.gif"
DARK_SRC="${ROOT_DIR}/assets/loading/loading-dark.gif"

sync_file "${LIGHT_SRC}" "frontend/static/images/loading-light.gif"
sync_file "${DARK_SRC}" "frontend/static/images/loading-dark.gif"
sync_file "${LIGHT_SRC}" "ios/sideBar/sideBar/Resources/images/loading-light.gif"
sync_file "${DARK_SRC}" "ios/sideBar/sideBar/Resources/images/loading-dark.gif"
sync_file "${LIGHT_SRC}" "ios/sideBar/ShareExtension/Resources/images/loading-light.gif"
sync_file "${DARK_SRC}" "ios/sideBar/ShareExtension/Resources/images/loading-dark.gif"
sync_file "${LIGHT_SRC}" "ios/sideBar/sideBar Safari Extension/Resources/images/loading-light.gif"
sync_file "${DARK_SRC}" "ios/sideBar/sideBar Safari Extension/Resources/images/loading-dark.gif"

if [[ "${MODE}" == "check" && "${out_of_sync}" -ne 0 ]]; then
  echo "Run scripts/sync-assets.sh to re-sync assets." >&2
  exit 1
fi
