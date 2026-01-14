#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
frontend_dir="${repo_root}/frontend"
output_dir="${frontend_dir}/dist/codemirror"
resources_dir="${repo_root}/ios/sideBar/sideBar/Resources/CodeMirror"

if [[ ! -d "${frontend_dir}" ]]; then
  echo "frontend directory not found: ${frontend_dir}" >&2
  exit 1
fi

(
  cd "${frontend_dir}"
  npm run build:codemirror
)

if [[ ! -d "${output_dir}" ]]; then
  echo "CodeMirror build output missing: ${output_dir}" >&2
  exit 1
fi

mkdir -p "${resources_dir}"
cp -R "${output_dir}/"* "${resources_dir}/"

echo "CodeMirror bundle copied to ${resources_dir}"
