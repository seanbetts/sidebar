#!/usr/bin/env bash
set -euo pipefail

remote="origin"
dev_branch="dev"
main_branch="main"
push_dev="false"
skip_ios_tests="false"

usage() {
  cat <<USAGE
Usage: scripts/release-main.sh [options]

Promotes dev to main with a linear-history flow:
1. fetch + ff pull dev/main
2. rebase dev onto origin/main
3. optional iOS test run
4. ff-only merge dev -> main
5. push main
6. optional force-with-lease push of rebased dev

Options:
  --remote <name>       Git remote (default: origin)
  --dev <branch>        Dev branch name (default: dev)
  --main <branch>       Main branch name (default: main)
  --push-dev            Force-with-lease push rebased dev branch
  --skip-ios-tests      Skip scripts/test-ios.sh
  -h, --help            Show this help
USAGE
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
    --push-dev)
      push_dev="true"
      shift
      ;;
    --skip-ios-tests)
      skip_ios_tests="true"
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

echo "Rebasing $dev_branch onto $remote/$main_branch..."
git rebase "$remote/$main_branch"

if [[ "$skip_ios_tests" != "true" ]]; then
  echo "Running iOS tests..."
  scripts/test-ios.sh
fi

echo "Updating $main_branch..."
git checkout "$main_branch"
git pull --ff-only "$remote" "$main_branch"

echo "Fast-forward merging $dev_branch -> $main_branch..."
git merge --ff-only "$dev_branch"

echo "Pushing $main_branch to $remote..."
git push "$remote" "$main_branch"

git checkout "$dev_branch"
if [[ "$push_dev" == "true" ]]; then
  echo "Pushing rebased $dev_branch to $remote with --force-with-lease..."
  git push --force-with-lease "$remote" "$dev_branch"
else
  echo "Release complete."
  echo "Note: local '$dev_branch' is rebased; publish it with:"
  echo "  git push --force-with-lease $remote $dev_branch"
fi

trap - EXIT
git checkout "$dev_branch"
