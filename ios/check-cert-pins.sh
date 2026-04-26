#!/usr/bin/env bash
# check-cert-pins.sh — compare bundled .cer SPKI hashes against live server chain
#
# Usage:
#   ./ios/check-cert-pins.sh [hostname] [port]
#
# Exits non-zero if:
#   - The server cert cannot be fetched
#   - No bundled .cer SPKI hash matches the live server chain
#   - The server cert has expired or expires within WARN_DAYS
#
# Requires: openssl, sha256sum (or shasum on macOS)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOURCES_DIR="$SCRIPT_DIR/sideBar/sideBar/Resources"
HOST="${1:-api.trysidebar.ai}"
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

CHAIN_DIR=$(mktemp -d "${TMPDIR:-/tmp}/cert-pin-check.XXXXXX")
cleanup() {
    rm -rf "$CHAIN_DIR"
}
trap cleanup EXIT

# Fetch the PEMs for the server-presented certificate chain.
openssl s_client \
    -connect "$HOST:$PORT" \
    -servername "$HOST" \
    -verify_quiet \
    -showcerts \
    2>/dev/null </dev/null \
    | awk -v dir="$CHAIN_DIR" '
        /-----BEGIN CERTIFICATE-----/ {
            in_cert = 1
            cert_index += 1
            cert_file = sprintf("%s/cert-%02d.pem", dir, cert_index)
        }
        in_cert {
            print > cert_file
        }
        /-----END CERTIFICATE-----/ {
            in_cert = 0
            close(cert_file)
        }
    ' || true

SERVER_CHAIN_FILES=("$CHAIN_DIR"/cert-*.pem)
if [ ${#SERVER_CHAIN_FILES[@]} -eq 0 ] || [ ! -f "${SERVER_CHAIN_FILES[0]}" ]; then
    fail "Could not retrieve server certificate chain from $HOST:$PORT"
fi

SERVER_PEM=$(cat "${SERVER_CHAIN_FILES[0]}")
if [ -z "$SERVER_PEM" ]; then
    fail "Could not retrieve server certificate from $HOST:$PORT"
fi

LIVE_CHAIN_SPKIS=()
log "Live cert chain:"
CHAIN_INDEX=0
for PEM in "${SERVER_CHAIN_FILES[@]}"; do
    [ -f "$PEM" ] || continue
    CHAIN_INDEX=$((CHAIN_INDEX + 1))
    CHAIN_SPKI=$(openssl x509 -in "$PEM" -noout -pubkey 2>/dev/null \
        | openssl pkey -pubin -outform DER 2>/dev/null \
        | sha256_hex)
    LIVE_CHAIN_SPKIS+=("$CHAIN_SPKI")
    SUBJECT=$(openssl x509 -in "$PEM" -noout -subject 2>/dev/null \
        | sed 's/subject=//' | tr -d '\n')
    ENDDATE=$(openssl x509 -in "$PEM" -noout -enddate 2>/dev/null \
        | cut -d= -f2)
    LABEL="chain[$CHAIN_INDEX]"
    if [ "$CHAIN_INDEX" -eq 1 ]; then
        LABEL="leaf"
    fi
    log "  $LABEL: SPKI=$CHAIN_SPKI  ($SUBJECT, expires $ENDDATE)"
done

SERVER_SPKI="${LIVE_CHAIN_SPKIS[0]}"

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
    CHAIN_INDEX=0
    for LIVE_SPKI in "${LIVE_CHAIN_SPKIS[@]}"; do
        CHAIN_INDEX=$((CHAIN_INDEX + 1))
        if [ "$BUNDLED_SPKI" = "$LIVE_SPKI" ]; then
            MATCH=1
            LABEL="chain[$CHAIN_INDEX]"
            if [ "$CHAIN_INDEX" -eq 1 ]; then
                LABEL="leaf"
            fi
            SUFFIX=" MATCHES live $LABEL"
        fi
    done
    log "  $(basename "$CER"): SPKI=$BUNDLED_SPKI  ($SUBJECT, expires $ENDDATE)$SUFFIX"
done

if [ "$MATCH" -eq 0 ]; then
    fail "No bundled .cer SPKI matches live server chain ($HOST); leaf SPKI=$SERVER_SPKI. Update sideBar/sideBar/Resources/ before the next release."
fi

log "Cert pin check PASSED for $HOST"
