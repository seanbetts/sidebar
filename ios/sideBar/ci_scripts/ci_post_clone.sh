#!/bin/bash
#
# Xcode Cloud post-clone script
# Generates SideBar.local.xcconfig from environment variables
#
# Required environment variables (set in Xcode Cloud):
#   - API_BASE_URL
#   - SUPABASE_URL
#   - SUPABASE_ANON_KEY
#   - KEYCHAIN_ACCESS_GROUP
#   - KEYCHAIN_SERVICE
# Optional (defaults to group.ai.sidebar.sidebar):
#   - APP_GROUP_ID
# Optional (defaults to sideBar production webcredentials domain):
#   - ASSOCIATED_DOMAINS
# Optional (enables Apple app Sentry SDK in release builds):
#   - SENTRY_DSN
# Optional (enables dSYM upload when all are present):
#   - SENTRY_AUTH_TOKEN
#   - SENTRY_ORG
#   - SENTRY_PROJECT
# Optional (pins the verified sentry-cli install, defaults to 2.58.2):
#   - SENTRY_CLI_VERSION

set -euo pipefail

echo "=== ci_post_clone.sh: Ensuring SwiftLint is available (best effort) ==="
if command -v swiftlint >/dev/null 2>&1; then
    echo "SwiftLint already available at: $(command -v swiftlint)"
elif command -v brew >/dev/null 2>&1; then
    # Avoid flaky Homebrew auto-update/network dependency from blocking Xcode Cloud builds.
    export HOMEBREW_NO_AUTO_UPDATE=1
    if brew list swiftlint >/dev/null 2>&1; then
        echo "SwiftLint already installed via Homebrew"
    elif brew install swiftlint; then
        echo "Installed SwiftLint via Homebrew"
    else
        echo "warning: Unable to install SwiftLint via Homebrew; continuing without it"
        echo "warning: SwiftLint remains optional in the Xcode build phase"
    fi
else
    echo "warning: Homebrew not found and SwiftLint not installed; continuing without SwiftLint"
fi

ensure_sentry_cli() {
    echo "=== ci_post_clone.sh: Ensuring sentry-cli is available ==="

    if [[ -z "${SENTRY_AUTH_TOKEN:-}" || -z "${SENTRY_ORG:-}" || -z "${SENTRY_PROJECT:-}" ]]; then
        echo "Sentry dSYM upload disabled; set SENTRY_AUTH_TOKEN, SENTRY_ORG, and SENTRY_PROJECT to enable it"
        return 0
    fi

    local install_root="$SIDEBAR_DIR/.tools/sentry-cli"
    local install_dir="$install_root/bin"
    local cli_version="${SENTRY_CLI_VERSION:-2.58.2}"

    if command -v sentry-cli >/dev/null 2>&1; then
        echo "sentry-cli already available at: $(command -v sentry-cli)"
        return 0
    fi

    if [[ -x "$install_dir/sentry-cli" ]]; then
        echo "sentry-cli already installed at: $install_dir/sentry-cli"
        return 0
    fi

    if ! command -v curl >/dev/null 2>&1; then
        echo "error: curl not found; unable to install sentry-cli while dSYM upload is enabled"
        return 1
    fi

    if ! command -v python3 >/dev/null 2>&1; then
        echo "error: python3 not found; unable to verify sentry-cli release metadata"
        return 1
    fi

    if ! command -v shasum >/dev/null 2>&1; then
        echo "error: shasum not found; unable to verify sentry-cli checksum"
        return 1
    fi

    mkdir -p "$install_dir"

    local asset_name
    case "$(uname -s)" in
        Darwin)
            asset_name="sentry-cli-Darwin-universal"
            ;;
        *)
            echo "error: unsupported sentry-cli install platform: $(uname -s)"
            return 1
            ;;
    esac

    local tmp_dir
    tmp_dir="$(mktemp -d)"
    local registry_path="$tmp_dir/release-registry.json"
    local download_path="$tmp_dir/$asset_name"
    local registry_url="https://release-registry.services.sentry.io/apps/sentry-cli/$cli_version"

    echo "Downloading sentry-cli release metadata for ${cli_version}"
    curl -fsSL "$registry_url" > "$registry_path"

    local asset_metadata
    if ! asset_metadata="$(python3 - "$registry_path" "$asset_name" <<'PY'
import json
import sys

registry_path = sys.argv[1]
asset_name = sys.argv[2]

with open(registry_path, "r", encoding="utf-8") as handle:
    registry = json.load(handle)

try:
    asset = registry["files"][asset_name]
    checksum = asset["checksums"]["sha256-hex"]
    url = asset["url"]
except KeyError as exc:
    raise SystemExit(f"missing sentry-cli registry field: {exc}") from exc

if not checksum or not url:
    raise SystemExit("missing sentry-cli URL or checksum")

print(url)
print(checksum)
PY
)"; then
        rm -rf "$tmp_dir"
        echo "error: unable to read sentry-cli release metadata"
        return 1
    fi

    local asset_url
    local expected_sha
    asset_url="$(printf '%s\n' "$asset_metadata" | sed -n '1p')"
    expected_sha="$(printf '%s\n' "$asset_metadata" | sed -n '2p')"

    echo "Downloading ${asset_name}"
    curl -fsSL -o "$download_path" "$asset_url"

    local actual_sha
    actual_sha="$(shasum -a 256 "$download_path" | awk '{print $1}')"
    if [[ "$actual_sha" != "$expected_sha" ]]; then
        rm -rf "$tmp_dir"
        echo "error: sentry-cli checksum mismatch for ${asset_name}"
        echo "error: expected ${expected_sha}, got ${actual_sha}"
        return 1
    fi

    mv "$download_path" "$install_dir/sentry-cli"
    chmod +x "$install_dir/sentry-cli"
    rm -rf "$tmp_dir"
    echo "Installed verified sentry-cli ${cli_version} to $install_dir/sentry-cli"
}

echo "=== ci_post_clone.sh: Generating SideBar.local.xcconfig ==="

# Validate required environment variables
required_vars=("API_BASE_URL" "SUPABASE_URL" "SUPABASE_ANON_KEY" "KEYCHAIN_ACCESS_GROUP" "KEYCHAIN_SERVICE")
for var in "${required_vars[@]}"; do
    if [[ -z "${!var:-}" ]]; then
        echo "Error: Required environment variable $var is not set"
        exit 1
    fi
done

APP_GROUP_ID="${APP_GROUP_ID:-group.ai.sidebar.sidebar}"
if ! [[ "$APP_GROUP_ID" =~ ^(group\.[A-Za-z0-9.-]+|[A-Z0-9]{10}\.[A-Za-z0-9.-]+)$ ]]; then
    echo "Error: APP_GROUP_ID must be a valid app group identifier (got: '$APP_GROUP_ID')"
    exit 1
fi
ASSOCIATED_DOMAINS="${ASSOCIATED_DOMAINS:-webcredentials:app.trysidebar.ai}"

# Escape forward slashes for xcconfig format (// is treated as comment)
escape_url() {
    echo "$1" | sed 's/\//\\\//g'
}

API_BASE_URL_ESCAPED=$(escape_url "$API_BASE_URL")
SUPABASE_URL_ESCAPED=$(escape_url "$SUPABASE_URL")
R2_ENDPOINT_ESCAPED=$(escape_url "${R2_ENDPOINT:-}")
R2_BUCKET_ESCAPED=$(escape_url "${R2_BUCKET:-}")
R2_FAVICON_BUCKET_ESCAPED=$(escape_url "${R2_FAVICON_BUCKET:-}")
R2_FAVICON_PUBLIC_BASE_URL_ESCAPED=$(escape_url "${R2_FAVICON_PUBLIC_BASE_URL:-}")
SENTRY_DSN_ESCAPED=$(escape_url "${SENTRY_DSN:-}")

# Generate the xcconfig content
XCCONFIG_CONTENT="// Auto-generated by ci_post_clone.sh for Xcode Cloud builds
// DO NOT COMMIT THIS FILE

API_BASE_URL = ${API_BASE_URL_ESCAPED}

SUPABASE_URL = ${SUPABASE_URL_ESCAPED}
SUPABASE_ANON_KEY = ${SUPABASE_ANON_KEY}
SENTRY_DSN = ${SENTRY_DSN_ESCAPED}
R2_ENDPOINT = ${R2_ENDPOINT_ESCAPED}
R2_BUCKET = ${R2_BUCKET_ESCAPED}
R2_FAVICON_BUCKET = ${R2_FAVICON_BUCKET_ESCAPED}
R2_FAVICON_PUBLIC_BASE_URL = ${R2_FAVICON_PUBLIC_BASE_URL_ESCAPED}

APP_GROUP_ID = ${APP_GROUP_ID}
KEYCHAIN_ACCESS_GROUP = ${KEYCHAIN_ACCESS_GROUP}
KEYCHAIN_SERVICE = ${KEYCHAIN_SERVICE}
ASSOCIATED_DOMAINS = ${ASSOCIATED_DOMAINS}

INFOPLIST_KEY_API_BASE_URL = \$(API_BASE_URL)
INFOPLIST_KEY_SUPABASE_URL = \$(SUPABASE_URL)
INFOPLIST_KEY_SUPABASE_ANON_KEY = \$(SUPABASE_ANON_KEY)
INFOPLIST_KEY_SENTRY_DSN = \$(SENTRY_DSN)
INFOPLIST_KEY_R2_ENDPOINT = \$(R2_ENDPOINT)
INFOPLIST_KEY_R2_BUCKET = \$(R2_BUCKET)
INFOPLIST_KEY_R2_FAVICON_BUCKET = \$(R2_FAVICON_BUCKET)
INFOPLIST_KEY_R2_FAVICON_PUBLIC_BASE_URL = \$(R2_FAVICON_PUBLIC_BASE_URL)
INFOPLIST_KEY_APP_GROUP_ID = \$(APP_GROUP_ID)
INFOPLIST_KEY_KEYCHAIN_ACCESS_GROUP = \$(KEYCHAIN_ACCESS_GROUP)
INFOPLIST_KEY_KEYCHAIN_SERVICE = \$(KEYCHAIN_SERVICE)"

# Write to both locations the project might reference
REPO_ROOT="${CI_PRIMARY_REPOSITORY_PATH:-$(cd "$(dirname "$0")/../.." && pwd)}"
SIDEBAR_DIR="$REPO_ROOT/ios/sideBar"

ensure_sentry_cli

echo "$XCCONFIG_CONTENT" > "$SIDEBAR_DIR/SideBar.local.xcconfig"
echo "Created: $SIDEBAR_DIR/SideBar.local.xcconfig"

echo "$XCCONFIG_CONTENT" > "$SIDEBAR_DIR/Config/SideBar.local.xcconfig"
echo "Created: $SIDEBAR_DIR/Config/SideBar.local.xcconfig"

echo "=== ci_post_clone.sh: Done ==="
