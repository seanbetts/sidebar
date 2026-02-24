#!/bin/sh
set -e

if [ "$(id -u)" -eq 0 ]; then
  if [ -d "/data" ]; then
    chown -R appuser:appuser /data || true
  fi
  if [ "${PLAYWRIGHT_STARTUP_CHECK:-0}" = "1" ]; then
    su -s /bin/sh appuser -c "python /app/playwright_smoke_check.py"
  fi
  exec su -s /bin/sh appuser -c "$*"
fi

if [ "${PLAYWRIGHT_STARTUP_CHECK:-0}" = "1" ]; then
  python /app/playwright_smoke_check.py
fi

exec "$@"
