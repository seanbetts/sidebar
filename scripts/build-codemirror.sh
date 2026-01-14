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
if [[ -f "${output_dir}/editor.html" ]]; then
  /usr/bin/perl -0pi -e 's/\s+crossorigin//g' "${output_dir}/editor.html"
  /usr/bin/perl -0pi -e 's/type="module"//g' "${output_dir}/editor.html"
  if [[ -f "${output_dir}/editor.js" ]]; then
    CODEMIRROR_DIST="${output_dir}" /usr/bin/python3 - <<'PY'
from pathlib import Path
import os
import re

output_dir = Path(os.environ["CODEMIRROR_DIST"])
html_path = output_dir / "editor.html"
js_path = output_dir / "editor.js"

html = html_path.read_text(encoding="utf-8")
js = js_path.read_text(encoding="utf-8").replace("</script>", "<\\/script>")

needle = 'src="./editor.js"'
idx = html.find(needle)
if idx == -1:
    raise SystemExit("Could not inline CodeMirror bundle: script src not found")

start = html.rfind("<script", 0, idx)
end = html.find("</script>", idx)
if start == -1 or end == -1:
    raise SystemExit("Could not inline CodeMirror bundle: script tag not found")

replacement = f"<script>{js}</script>"
html = html[:start] + replacement + html[end + len("</script>"):]
html_path.write_text(html, encoding="utf-8")
PY
  fi
fi

cp -R "${output_dir}/"* "${resources_dir}/"

echo "CodeMirror bundle copied to ${resources_dir}"
