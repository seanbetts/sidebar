#!/usr/bin/env bash
set -euo pipefail

remote_sha="${1:-}"
local_sha="${2:-}"
dev_branch="${3:-dev}"

if [[ -z "$remote_sha" || -z "$local_sha" ]]; then
  echo "Usage: $0 <remote-sha> <local-sha> [dev-branch]" >&2
  exit 2
fi

zero_sha_regex='^0+$'

if [[ "$local_sha" =~ $zero_sha_regex ]]; then
  # Deleting refs is handled by server policy.
  exit 0
fi

if ! git show-ref --verify --quiet "refs/heads/$dev_branch"; then
  echo "Cannot verify linear main push: missing local '$dev_branch' branch." >&2
  exit 1
fi

dev_sha=$(git rev-parse "$dev_branch")
if [[ "$local_sha" != "$dev_sha" ]]; then
  echo "Push to main blocked: main tip must match '$dev_branch' tip." >&2
  echo "Expected: $dev_sha ($dev_branch)" >&2
  echo "Actual:   $local_sha (main push tip)" >&2
  echo "Use scripts/release-main.sh to promote '$dev_branch' safely." >&2
  exit 1
fi

if [[ ! "$remote_sha" =~ $zero_sha_regex ]]; then
  if ! git merge-base --is-ancestor "$remote_sha" "$local_sha"; then
    echo "Push to main blocked: force-push / non-fast-forward updates are not allowed." >&2
    exit 1
  fi
  range="$remote_sha..$local_sha"
else
  range="$local_sha"
fi

merge_commits=$(git rev-list --merges "$range")
if [[ -n "$merge_commits" ]]; then
  echo "Push to main blocked: merge commits detected in push range ($range)." >&2
  echo "Linear history requires rebased commits. Offending commits:" >&2
  git log --oneline --decorate $merge_commits >&2
  echo "Use scripts/release-main.sh to promote '$dev_branch' with ff-only main updates." >&2
  exit 1
fi
