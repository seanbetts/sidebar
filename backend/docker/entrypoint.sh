#!/bin/sh
set -e

if [ "$(id -u)" -eq 0 ]; then
  if [ -d "/data" ]; then
    chown -R appuser:appuser /data || true
  fi
  exec su -s /bin/sh appuser -c "$*"
fi

exec "$@"
