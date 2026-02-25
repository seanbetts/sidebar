#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/sync-assets.sh [--check]

Syncs canonical assets from /assets into all runtime targets.
Currently synced groups:
  - loading GIFs (44px source) from assets/loading/
  - extension logos from assets/branding/
  - Safari extension icons from assets/safari-extension/

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
# Use 44px assets for regular loading indicators (16, 20, 24, 32, 44) and sync
# 128px assets for hero-sized loading surfaces.
LIGHT_SRC="${ROOT_DIR}/assets/loading/loading-light-44.gif"
DARK_SRC="${ROOT_DIR}/assets/loading/loading-dark-44.gif"

sync_file "${LIGHT_SRC}" "frontend/static/images/loading-light.gif"
sync_file "${DARK_SRC}" "frontend/static/images/loading-dark.gif"

LIGHT_128_SRC="${ROOT_DIR}/assets/loading/loading-light-128.gif"
DARK_128_SRC="${ROOT_DIR}/assets/loading/loading-dark-128.gif"
sync_file "${LIGHT_128_SRC}" "frontend/static/images/loading-light-128.gif"
sync_file "${DARK_128_SRC}" "frontend/static/images/loading-dark-128.gif"

sync_file "${LIGHT_SRC}" "ios/sideBar/sideBar/Resources/images/loading-light.gif"
sync_file "${DARK_SRC}" "ios/sideBar/sideBar/Resources/images/loading-dark.gif"
sync_file "${LIGHT_128_SRC}" "ios/sideBar/sideBar/Resources/images/loading-light-128.gif"
sync_file "${DARK_128_SRC}" "ios/sideBar/sideBar/Resources/images/loading-dark-128.gif"
sync_file "${LIGHT_SRC}" "ios/sideBar/ShareExtension/Resources/images/loading-light.gif"
sync_file "${DARK_SRC}" "ios/sideBar/ShareExtension/Resources/images/loading-dark.gif"
sync_file "${LIGHT_128_SRC}" "ios/sideBar/ShareExtension/Resources/images/loading-light-128.gif"
sync_file "${DARK_128_SRC}" "ios/sideBar/ShareExtension/Resources/images/loading-dark-128.gif"
sync_file "${LIGHT_SRC}" "ios/sideBar/sideBar Safari Extension/Resources/images/loading-light.gif"
sync_file "${DARK_SRC}" "ios/sideBar/sideBar Safari Extension/Resources/images/loading-dark.gif"
sync_file "${LIGHT_SRC}" "ios/sideBar/sideBar Safari Extension (macOS) Extension/Resources/images/loading-light.gif"
sync_file "${DARK_SRC}" "ios/sideBar/sideBar Safari Extension (macOS) Extension/Resources/images/loading-dark.gif"

# Group: extension logos
LOGO_LIGHT_SRC="${ROOT_DIR}/assets/branding/logo-light.png"
LOGO_DARK_SRC="${ROOT_DIR}/assets/branding/logo-dark.png"

sync_file "${LOGO_LIGHT_SRC}" "ios/sideBar/ShareExtension/Resources/images/logo-light.png"
sync_file "${LOGO_DARK_SRC}" "ios/sideBar/ShareExtension/Resources/images/logo-dark.png"
sync_file "${LOGO_LIGHT_SRC}" "ios/sideBar/sideBar Safari Extension/Resources/images/logo-light.png"
sync_file "${LOGO_DARK_SRC}" "ios/sideBar/sideBar Safari Extension/Resources/images/logo-dark.png"

# Group: Safari extension icon set and toolbar icon
for size in 16 32 48 64 96 128 256 512; do
  icon_src="${ROOT_DIR}/assets/safari-extension/icon-${size}.png"
  sync_file "${icon_src}" "ios/sideBar/sideBar Safari Extension/Resources/images/icon-${size}.png"
  sync_file "${icon_src}" "ios/sideBar/sideBar Safari Extension (macOS) Extension/Resources/images/icon-${size}.png"
done

TOOLBAR_ICON_SRC="${ROOT_DIR}/assets/safari-extension/toolbar-icon.svg"
sync_file "${TOOLBAR_ICON_SRC}" "ios/sideBar/sideBar Safari Extension/Resources/images/toolbar-icon.svg"
sync_file "${TOOLBAR_ICON_SRC}" "ios/sideBar/sideBar Safari Extension (macOS) Extension/Resources/images/toolbar-icon.svg"

if [[ "${MODE}" == "check" && "${out_of_sync}" -ne 0 ]]; then
  echo "Run scripts/sync-assets.sh to re-sync assets." >&2
  exit 1
fi
