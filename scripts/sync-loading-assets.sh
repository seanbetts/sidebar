#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/sync-loading-assets.sh [--check]

Syncs canonical loading GIF assets from assets/loading/ into all app targets.

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
CANONICAL_DIR="${ROOT_DIR}/assets/loading"

LIGHT_SRC="${CANONICAL_DIR}/loading-light.gif"
DARK_SRC="${CANONICAL_DIR}/loading-dark.gif"

TARGET_FILES=(
  "frontend/static/images/loading-light.gif"
  "frontend/static/images/loading-dark.gif"
  "ios/sideBar/sideBar/Resources/images/loading-light.gif"
  "ios/sideBar/sideBar/Resources/images/loading-dark.gif"
  "ios/sideBar/ShareExtension/Resources/images/loading-light.gif"
  "ios/sideBar/ShareExtension/Resources/images/loading-dark.gif"
  "ios/sideBar/sideBar Safari Extension/Resources/images/loading-light.gif"
  "ios/sideBar/sideBar Safari Extension/Resources/images/loading-dark.gif"
)

for src in "${LIGHT_SRC}" "${DARK_SRC}"; do
  if [[ ! -f "${src}" ]]; then
    echo "Missing canonical asset: ${src}" >&2
    exit 1
  fi
done

out_of_sync=0

for rel in "${TARGET_FILES[@]}"; do
  dst="${ROOT_DIR}/${rel}"
  src="${LIGHT_SRC}"
  if [[ "${rel}" == *"loading-dark.gif" ]]; then
    src="${DARK_SRC}"
  fi

  if [[ "${MODE}" == "check" ]]; then
    if [[ ! -f "${dst}" ]] || ! cmp -s "${src}" "${dst}"; then
      echo "Out of sync: ${rel}" >&2
      out_of_sync=1
    fi
    continue
  fi

  mkdir -p "$(dirname "${dst}")"
  if [[ ! -f "${dst}" ]] || ! cmp -s "${src}" "${dst}"; then
    cp -f "${src}" "${dst}"
    echo "Updated ${rel}"
  fi
done

if [[ "${MODE}" == "check" && "${out_of_sync}" -ne 0 ]]; then
  echo "Run scripts/sync-loading-assets.sh to re-sync loading assets." >&2
  exit 1
fi
