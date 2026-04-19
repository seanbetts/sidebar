#!/bin/sh
set -e

should_run_playwright_startup_check() {
  [ "${PLAYWRIGHT_STARTUP_CHECK:-0}" = "1" ] &&
    [ "${SKIP_PLAYWRIGHT_STARTUP_CHECK:-0}" != "1" ]
}

if [ "$(id -u)" -eq 0 ]; then
  if [ -d "/data" ]; then
    chown appuser:appuser /data || true
  fi
  if should_run_playwright_startup_check; then
    su -s /bin/sh appuser -c "python /app/playwright_smoke_check.py"
  fi
  exec su -s /bin/sh appuser -c "$*"
fi

if should_run_playwright_startup_check; then
  python /app/playwright_smoke_check.py
fi

exec "$@"
