#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Load function definitions from dev.sh without executing its main dispatcher.
eval "$(
  awk '
    /^command="\$\{1:-start\}"$/ { exit }
    { print }
  ' "${REPO_ROOT}/dev.sh"
)"

docs_command="node --no-deprecation /Users/sean/.nvm/versions/node/v22.21.1/lib/node_modules/mint/node_modules/@mintlify/cli/bin/start.js dev --port 3001"
design_docs_command="node --no-deprecation /Users/sean/.nvm/versions/node/v22.21.1/lib/node_modules/mint/node_modules/@mintlify/cli/bin/start.js dev --port 3002"
caddy_command="caddy run --config Caddyfile"

if ! is_docs_process "${docs_command}"; then
  echo "Expected docs matcher to accept Mintlify child process command."
  exit 1
fi

if ! is_design_docs_process "${design_docs_command}"; then
  echo "Expected design docs matcher to accept Mintlify child process command."
  exit 1
fi

if ! is_caddy_process "${caddy_command}"; then
  echo "Expected Caddy matcher to accept relative-config command."
  exit 1
fi
