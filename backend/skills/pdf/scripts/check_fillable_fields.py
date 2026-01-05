import sys
from pathlib import Path

from pypdf import PdfReader

BACKEND_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(BACKEND_ROOT))

from api.services.skill_file_transfer import prepare_input_path, storage_is_r2, temp_root  # noqa: E402


# Script for Claude to run to determine whether a PDF has fillable form fields. See forms.md.


args = sys.argv[1:]
user_id = None
if "--user-id" in args:
    idx = args.index("--user-id")
    user_id = args[idx + 1]
    del args[idx:idx + 2]

if len(args) != 1:
    print("Usage: check_fillable_fields.py [input pdf] [--user-id USER]")
    sys.exit(1)

input_path = args[0]
local_root = temp_root("pdf-check-") if storage_is_r2() else Path(".")
pdf_path = prepare_input_path(user_id, input_path, local_root) if storage_is_r2() else Path(input_path)

reader = PdfReader(str(pdf_path))
if (reader.get_fields()):
    print("This PDF has fillable form fields")
else:
    print("This PDF does not have fillable form fields; you will need to visually determine where to enter data")
