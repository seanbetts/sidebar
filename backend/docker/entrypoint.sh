#!/bin/sh
set -e

if [ -n "${YT_DLP_COOKIES_CONTENT:-}" ]; then
  COOKIE_PATH="${YT_DLP_COOKIES:-/data/yt-cookies.txt}"
  COOKIE_DIR=$(dirname "$COOKIE_PATH")
  mkdir -p "$COOKIE_DIR"
  printf "%s" "$YT_DLP_COOKIES_CONTENT" > "$COOKIE_PATH"
  chmod 600 "$COOKIE_PATH"
  export YT_DLP_COOKIES="$COOKIE_PATH"
fi

if [ "$(id -u)" -eq 0 ]; then
  if [ -d "/data" ]; then
    chown -R appuser:appuser /data || true
  fi
  exec su -s /bin/sh appuser -c "$*"
fi

exec "$@"
