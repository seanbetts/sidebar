#!/usr/bin/env python3
"""
Command line tool to validate Office document XML files against XSD schemas and tracked changes.

Usage:
    python validate.py <dir> --original <original_file>
"""

import argparse
import sys
from pathlib import Path

from validation import DOCXSchemaValidator, PPTXSchemaValidator, RedliningValidator

BACKEND_ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(BACKEND_ROOT))

from api.services.skill_file_transfer import (  # noqa: E402
    prepare_input_path,
    download_input_dir,
    storage_is_r2,
    temp_root,
)


def main():
    parser = argparse.ArgumentParser(description="Validate Office document XML files")
    parser.add_argument(
        "unpacked_dir",
        help="Path to unpacked Office document directory",
    )
    parser.add_argument(
        "--original",
        required=True,
        help="Path to original file (.docx/.pptx/.xlsx)",
    )
    parser.add_argument(
        "-v",
        "--verbose",
        action="store_true",
        help="Enable verbose output",
    )
    parser.add_argument("--user-id", help="User id for storage access")
    args = parser.parse_args()

    # Validate paths
    local_root = temp_root("ooxml-validate-") if storage_is_r2() else Path(".")
    unpacked_dir = (
        download_input_dir(args.user_id, args.unpacked_dir, local_root / "unpacked")
        if storage_is_r2()
        else Path(args.unpacked_dir)
    )
    original_file = (
        prepare_input_path(args.user_id, args.original, local_root)
        if storage_is_r2()
        else Path(args.original)
    )
    file_extension = original_file.suffix.lower()
    assert unpacked_dir.is_dir(), f"Error: {unpacked_dir} is not a directory"
    assert original_file.is_file(), f"Error: {original_file} is not a file"
    assert file_extension in [".docx", ".pptx", ".xlsx"], (
        f"Error: {original_file} must be a .docx, .pptx, or .xlsx file"
    )

    # Run validations
    match file_extension:
        case ".docx":
            validators = [DOCXSchemaValidator, RedliningValidator]
        case ".pptx":
            validators = [PPTXSchemaValidator]
        case _:
            print(f"Error: Validation not supported for file type {file_extension}")
            sys.exit(1)

    # Run validators
    success = True
    for V in validators:
        validator = V(unpacked_dir, original_file, verbose=args.verbose)
        if not validator.validate():
            success = False

    if success:
        print("All validations PASSED!")

    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
