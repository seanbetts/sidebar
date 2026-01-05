#!/usr/bin/env python3
"""Unpack and format XML contents of Office files (.docx, .pptx, .xlsx)"""

import random
import sys
import defusedxml.minidom
import zipfile
from pathlib import Path

BACKEND_ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(BACKEND_ROOT))

from api.services.skill_file_transfer import (  # noqa: E402
    prepare_input_path,
    prepare_output_path,
    upload_output_dir,
    storage_is_r2,
    temp_root,
)

args = sys.argv[1:]
user_id = None
if "--user-id" in args:
    idx = args.index("--user-id")
    user_id = args[idx + 1]
    del args[idx:idx + 2]

if len(args) != 2:
    raise SystemExit("Usage: python unpack.py <office_file> <output_dir> [--user-id USER]")
input_file, output_dir = args[0], args[1]

local_root = temp_root("ooxml-unpack-") if storage_is_r2() else Path(".")
input_path = prepare_input_path(user_id, input_file, local_root) if storage_is_r2() else Path(input_file)
output_path, r2_output = prepare_output_path(user_id, output_dir, local_root)

# Extract and format
output_path.mkdir(parents=True, exist_ok=True)
zipfile.ZipFile(str(input_path)).extractall(output_path)

# Pretty print all XML files
xml_files = list(output_path.rglob("*.xml")) + list(output_path.rglob("*.rels"))
for xml_file in xml_files:
    content = xml_file.read_text(encoding="utf-8")
    dom = defusedxml.minidom.parseString(content)
    xml_file.write_bytes(dom.toprettyxml(indent="  ", encoding="ascii"))

# For .docx files, suggest an RSID for tracked changes
if input_file.endswith(".docx"):
    suggested_rsid = "".join(random.choices("0123456789ABCDEF", k=8))
    print(f"Suggested RSID for edit session: {suggested_rsid}")

if storage_is_r2():
    upload_output_dir(user_id, r2_output, output_path)
