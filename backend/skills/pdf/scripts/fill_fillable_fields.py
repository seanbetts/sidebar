import json
import sys
from pathlib import Path

from pypdf import PdfReader, PdfWriter

from extract_form_field_info import get_field_info

BACKEND_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(BACKEND_ROOT))

from api.services.skill_file_transfer import (  # noqa: E402
    prepare_input_path,
    prepare_output_path,
    upload_output_path,
    storage_is_r2,
    temp_root,
)


# Fills fillable form fields in a PDF. See forms.md.


def fill_pdf_fields(input_pdf_path: Path, fields_json_path: Path, output_pdf_path: Path):
    with open(fields_json_path) as f:
        fields = json.load(f)
    # Group by page number.
    fields_by_page = {}
    for field in fields:
        if "value" in field:
            field_id = field["field_id"]
            page = field["page"]
            if page not in fields_by_page:
                fields_by_page[page] = {}
            fields_by_page[page][field_id] = field["value"]
    
    reader = PdfReader(str(input_pdf_path))

    has_error = False
    field_info = get_field_info(reader)
    fields_by_ids = {f["field_id"]: f for f in field_info}
    for field in fields:
        existing_field = fields_by_ids.get(field["field_id"])
        if not existing_field:
            has_error = True
            print(f"ERROR: `{field['field_id']}` is not a valid field ID")
        elif field["page"] != existing_field["page"]:
            has_error = True
            print(f"ERROR: Incorrect page number for `{field['field_id']}` (got {field['page']}, expected {existing_field['page']})")
        else:
            if "value" in field:
                err = validation_error_for_field_value(existing_field, field["value"])
                if err:
                    print(err)
                    has_error = True
    if has_error:
        sys.exit(1)

    writer = PdfWriter(clone_from=reader)
    for page, field_values in fields_by_page.items():
        writer.update_page_form_field_values(writer.pages[page - 1], field_values, auto_regenerate=False)

    # This seems to be necessary for many PDF viewers to format the form values correctly.
    # It may cause the viewer to show a "save changes" dialog even if the user doesn't make any changes.
    writer.set_need_appearances_writer(True)
    
    with open(output_pdf_path, "wb") as f:
        writer.write(f)


def validation_error_for_field_value(field_info, field_value):
    field_type = field_info["type"]
    field_id = field_info["field_id"]
    if field_type == "checkbox":
        checked_val = field_info["checked_value"]
        unchecked_val = field_info["unchecked_value"]
        if field_value != checked_val and field_value != unchecked_val:
            return f'ERROR: Invalid value "{field_value}" for checkbox field "{field_id}". The checked value is "{checked_val}" and the unchecked value is "{unchecked_val}"'
    elif field_type == "radio_group":
        option_values = [opt["value"] for opt in field_info["radio_options"]]
        if field_value not in option_values:
            return f'ERROR: Invalid value "{field_value}" for radio group field "{field_id}". Valid values are: {option_values}' 
    elif field_type == "choice":
        choice_values = [opt["value"] for opt in field_info["choice_options"]]
        if field_value not in choice_values:
            return f'ERROR: Invalid value "{field_value}" for choice field "{field_id}". Valid values are: {choice_values}'
    return None


# pypdf (at least version 5.7.0) has a bug when setting the value for a selection list field.
# In _writer.py around line 966:
#
# if field.get(FA.FT, "/Tx") == "/Ch" and field_flags & FA.FfBits.Combo == 0:
#     txt = "\n".join(annotation.get_inherited(FA.Opt, []))
#
# The problem is that for selection lists, `get_inherited` returns a list of two-element lists like
# [["value1", "Text 1"], ["value2", "Text 2"], ...]
# This causes `join` to throw a TypeError because it expects an iterable of strings.
# The horrible workaround is to patch `get_inherited` to return a list of the value strings.
# We call the original method and adjust the return value only if the argument to `get_inherited`
# is `FA.Opt` and if the return value is a list of two-element lists.
def monkeypatch_pydpf_method():
    from pypdf.generic import DictionaryObject
    from pypdf.constants import FieldDictionaryAttributes

    original_get_inherited = DictionaryObject.get_inherited

    def patched_get_inherited(self, key: str, default = None):
        result = original_get_inherited(self, key, default)
        if key == FieldDictionaryAttributes.Opt:
            if isinstance(result, list) and all(isinstance(v, list) and len(v) == 2 for v in result):
                result = [r[0] for r in result]
        return result

    DictionaryObject.get_inherited = patched_get_inherited


if __name__ == "__main__":
    args = sys.argv[1:]
    user_id = None
    if "--user-id" in args:
        idx = args.index("--user-id")
        user_id = args[idx + 1]
        del args[idx:idx + 2]

    if len(args) != 3:
        print("Usage: fill_fillable_fields.py [input pdf] [field_values.json] [output pdf] [--user-id USER]")
        sys.exit(1)
    monkeypatch_pydpf_method()
    input_pdf, fields_json, output_pdf = args
    local_root = temp_root("pdf-fill-") if storage_is_r2() else Path(".")
    local_input = prepare_input_path(user_id, input_pdf, local_root) if storage_is_r2() else Path(input_pdf)
    local_fields = prepare_input_path(user_id, fields_json, local_root) if storage_is_r2() else Path(fields_json)
    local_output, r2_output = prepare_output_path(user_id, output_pdf, local_root)
    fill_pdf_fields(local_input, local_fields, local_output)
    if storage_is_r2():
        upload_output_path(user_id, r2_output, local_output)
