#!/usr/bin/env bash
set -euo pipefail

remote="origin"
dev_branch="dev"
main_branch="main"
run_ios_tests="false"
export_options_plist=""

usage() {
  cat <<USAGE
Usage: scripts/release-main.sh [options]

Promotes a published dev branch tip to main with a fast-forward-only flow:
1. fetch remote dev/main
2. verify local dev/main match their remote refs
3. verify remote main is an ancestor of remote dev
4. optional iOS preflight run
5. ff-only merge remote dev -> main
6. push main

Options:
  --remote <name>       Git remote (default: origin)
  --dev <branch>        Dev branch name (default: dev)
  --main <branch>       Main branch name (default: main)
  --run-ios-tests       Run iOS logic tests before promotion
  --export-options-plist <path>
                        ExportOptions.plist for macOS archive/export widget verification
  -h, --help            Show this help
USAGE
}

warn_deprecated_option() {
  local option="$1"
  local replacement="$2"
  echo "Warning: ${option} is deprecated. ${replacement}" >&2
}

require_branch_matches_remote() {
  local branch="$1"
  local remote_ref="$2"
  local local_sha remote_sha

  local_sha="$(git rev-parse "$branch")"
  remote_sha="$(git rev-parse "$remote_ref")"

  if [[ "$local_sha" != "$remote_sha" ]]; then
    echo "Release blocked: local '$branch' does not match '$remote_ref'." >&2
    echo "Local:  $local_sha" >&2
    echo "Remote: $remote_sha" >&2
    echo "Push or reconcile '$branch' before promoting to '$main_branch'." >&2
    exit 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --remote)
      remote="$2"
      shift 2
      ;;
    --dev)
      dev_branch="$2"
      shift 2
      ;;
    --main)
      main_branch="$2"
      shift 2
      ;;
    --run-ios-tests)
      run_ios_tests="true"
      shift
      ;;
    --export-options-plist)
      export_options_plist="$2"
      shift 2
      ;;
    --push-dev)
      warn_deprecated_option \
        "--push-dev" \
        "The release flow no longer rewrites '$dev_branch'; there is nothing extra to push."
      shift
      ;;
    --skip-ios-tests)
      warn_deprecated_option \
        "--skip-ios-tests" \
        "Local iOS preflight is now opt-in. Omit this flag or use --run-ios-tests when needed."
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "Working tree must be clean before release." >&2
  exit 1
fi

repo_root="$(git rev-parse --show-toplevel)"
start_branch=$(git rev-parse --abbrev-ref HEAD)
restore_branch() {
  git checkout "$start_branch" >/dev/null 2>&1 || true
}
trap restore_branch EXIT

echo "Fetching $remote/$main_branch and $remote/$dev_branch..."
git fetch "$remote" "$main_branch" "$dev_branch"

echo "Updating $dev_branch..."
git checkout "$dev_branch"
git pull --ff-only "$remote" "$dev_branch"
require_branch_matches_remote "$dev_branch" "$remote/$dev_branch"

if ! git merge-base --is-ancestor "$remote/$main_branch" "$remote/$dev_branch"; then
  echo "Release blocked: '$remote/$main_branch' is not an ancestor of '$remote/$dev_branch'." >&2
  echo "Update '$dev_branch' onto '$main_branch' before promoting it." >&2
  exit 1
fi

if [[ "$run_ios_tests" == "true" ]]; then
  echo "Running iOS preflight..."
  xcodebuild test \
    -project ios/sideBar/sideBar.xcodeproj \
    -scheme sideBarLogicHost \
    -testPlan AppleFast \
    -destination 'platform=macOS' \
    -parallel-testing-enabled NO \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=
else
  echo "Skipping local iOS preflight. Use --run-ios-tests for an explicit release preflight."
fi

if [[ -z "$export_options_plist" ]]; then
  default_export_options_plist="$repo_root/ios/sideBar/ExportOptions.plist"
  if [[ -f "$default_export_options_plist" ]]; then
    export_options_plist="$default_export_options_plist"
  else
    echo "Release blocked: missing --export-options-plist for macOS archive/export widget verification." >&2
    echo "Provide --export-options-plist <path> or add $default_export_options_plist." >&2
    exit 1
  fi
fi

if [[ ! -f "$export_options_plist" ]]; then
  echo "Release blocked: export options plist not found at '$export_options_plist'." >&2
  exit 1
fi

echo "Running macOS widget archive/export verification..."
python3 "$repo_root/scripts/verify_macos_widget_artifacts.py" \
  --mode archive-export \
  --workspace-root "$repo_root" \
  --export-options-plist "$export_options_plist" \
  --clean-stale-registrations

echo "Updating $main_branch..."
git checkout "$main_branch"
git pull --ff-only "$remote" "$main_branch"
require_branch_matches_remote "$main_branch" "$remote/$main_branch"

echo "Fast-forward merging $remote/$dev_branch -> $main_branch..."
git merge --ff-only "$remote/$dev_branch"

echo "Pushing $main_branch to $remote..."
git push "$remote" "$main_branch"

echo "Release complete."
echo "'$main_branch' now matches '$remote/$dev_branch' without rewriting '$dev_branch'."
