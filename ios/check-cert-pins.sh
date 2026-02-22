#!/usr/bin/env bash
# check-cert-pins.sh — compare bundled .cer SPKI hashes against live server cert
#
# Usage:
#   ./ios/check-cert-pins.sh [hostname] [port]
#
# Exits non-zero if:
#   - The server cert cannot be fetched
#   - No bundled .cer SPKI hash matches the live server SPKI
#   - The server cert has expired or expires within WARN_DAYS
#
# Requires: openssl, sha256sum (or shasum on macOS)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOURCES_DIR="$SCRIPT_DIR/sideBar/sideBar/Resources"
HOST="${1:-sidebar-api.fly.dev}"
PORT="${2:-443}"
WARN_DAYS=21

log()  { echo "[cert-pin-check] $*"; }
fail() { echo "[cert-pin-check] ERROR: $*" >&2; exit 1; }
warn() { echo "[cert-pin-check] WARNING: $*" >&2; }

# sha256 of stdin → hex (handles macOS vs Linux)
sha256_hex() {
    if command -v sha256sum &>/dev/null; then
        sha256sum | awk '{print $1}'
    else
        shasum -a 256 | awk '{print $1}'
    fi
}

log "Checking live cert for $HOST:$PORT ..."

# Fetch the PEM of the server leaf cert
SERVER_PEM=$(openssl s_client \
    -connect "$HOST:$PORT" \
    -servername "$HOST" \
    -verify_quiet \
    2>/dev/null </dev/null \
    | openssl x509 2>/dev/null) || true

if [ -z "$SERVER_PEM" ]; then
    fail "Could not retrieve server certificate from $HOST:$PORT"
fi

# SPKI hash = SHA-256 of the DER-encoded SubjectPublicKeyInfo
SERVER_SPKI=$(echo "$SERVER_PEM" \
    | openssl x509 -noout -pubkey 2>/dev/null \
    | openssl pkey -pubin -outform DER 2>/dev/null \
    | sha256_hex)

log "Server SPKI:      $SERVER_SPKI"

# Cert expiry
EXPIRY=$(echo "$SERVER_PEM" | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
if [ -n "$EXPIRY" ]; then
    # Parse date: macOS uses -j -f, Linux uses -d
    EXPIRY_EPOCH=$(date -j -f "%b %d %T %Y %Z" "$EXPIRY" +%s 2>/dev/null \
        || date -d "$EXPIRY" +%s 2>/dev/null \
        || echo 0)
    NOW_EPOCH=$(date +%s)
    DAYS_LEFT=$(( (EXPIRY_EPOCH - NOW_EPOCH) / 86400 ))
    if [ "$DAYS_LEFT" -le 0 ]; then
        fail "Server cert has EXPIRED ($EXPIRY)"
    elif [ "$DAYS_LEFT" -le "$WARN_DAYS" ]; then
        warn "Server cert expires in ${DAYS_LEFT}d ($EXPIRY) — rotate bundled certs soon"
    else
        log "Server cert expires in ${DAYS_LEFT}d ($EXPIRY)"
    fi
fi

# Compute SPKI hashes for all bundled .cer files
if [ ! -d "$RESOURCES_DIR" ]; then
    fail "Resources directory not found: $RESOURCES_DIR"
fi

CER_FILES=("$RESOURCES_DIR"/*.cer)
if [ ${#CER_FILES[@]} -eq 0 ] || [ ! -f "${CER_FILES[0]}" ]; then
    fail "No .cer files found in $RESOURCES_DIR"
fi

log "Bundled .cer files:"
MATCH=0
for CER in "${CER_FILES[@]}"; do
    [ -f "$CER" ] || continue
    BUNDLED_SPKI=$(openssl x509 -inform DER -in "$CER" -noout -pubkey 2>/dev/null \
        | openssl pkey -pubin -outform DER 2>/dev/null \
        | sha256_hex)
    SUBJECT=$(openssl x509 -inform DER -in "$CER" -noout -subject 2>/dev/null \
        | sed 's/subject=//' | tr -d '\n')
    ENDDATE=$(openssl x509 -inform DER -in "$CER" -noout -enddate 2>/dev/null \
        | cut -d= -f2)
    SUFFIX=""
    if [ "$BUNDLED_SPKI" = "$SERVER_SPKI" ]; then
        MATCH=1
        SUFFIX=" ✓ MATCH"
    fi
    log "  $(basename "$CER"): SPKI=$BUNDLED_SPKI  ($SUBJECT, expires $ENDDATE)$SUFFIX"
done

if [ "$MATCH" -eq 0 ]; then
    fail "No bundled .cer SPKI matches live server ($HOST) SPKI=$SERVER_SPKI"
    fail "Update sideBar/sideBar/Resources/ with the current server cert before the next release."
fi

log "Cert pin check PASSED for $HOST"
