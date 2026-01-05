import json
import sys
from pathlib import Path

from pypdf import PdfReader, PdfWriter
from pypdf.annotations import FreeText

BACKEND_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(BACKEND_ROOT))

from api.services.skill_file_transfer import (  # noqa: E402
    prepare_input_path,
    prepare_output_path,
    upload_output_path,
    storage_is_r2,
    temp_root,
)


# Fills a PDF by adding text annotations defined in `fields.json`. See forms.md.


def transform_coordinates(bbox, image_width, image_height, pdf_width, pdf_height):
    """Transform bounding box from image coordinates to PDF coordinates"""
    # Image coordinates: origin at top-left, y increases downward
    # PDF coordinates: origin at bottom-left, y increases upward
    x_scale = pdf_width / image_width
    y_scale = pdf_height / image_height
    
    left = bbox[0] * x_scale
    right = bbox[2] * x_scale
    
    # Flip Y coordinates for PDF
    top = pdf_height - (bbox[1] * y_scale)
    bottom = pdf_height - (bbox[3] * y_scale)
    
    return left, bottom, right, top


def fill_pdf_form(input_pdf_path: Path, fields_json_path: Path, output_pdf_path: Path):
    """Fill the PDF form with data from fields.json"""
    
    # `fields.json` format described in forms.md.
    with open(fields_json_path, "r") as f:
        fields_data = json.load(f)
    
    # Open the PDF
    reader = PdfReader(str(input_pdf_path))
    writer = PdfWriter()
    
    # Copy all pages to writer
    writer.append(reader)
    
    # Get PDF dimensions for each page
    pdf_dimensions = {}
    for i, page in enumerate(reader.pages):
        mediabox = page.mediabox
        pdf_dimensions[i + 1] = [mediabox.width, mediabox.height]
    
    # Process each form field
    annotations = []
    for field in fields_data["form_fields"]:
        page_num = field["page_number"]
        
        # Get page dimensions and transform coordinates.
        page_info = next(p for p in fields_data["pages"] if p["page_number"] == page_num)
        image_width = page_info["image_width"]
        image_height = page_info["image_height"]
        pdf_width, pdf_height = pdf_dimensions[page_num]
        
        transformed_entry_box = transform_coordinates(
            field["entry_bounding_box"],
            image_width, image_height,
            pdf_width, pdf_height
        )
        
        # Skip empty fields
        if "entry_text" not in field or "text" not in field["entry_text"]:
            continue
        entry_text = field["entry_text"]
        text = entry_text["text"]
        if not text:
            continue
        
        font_name = entry_text.get("font", "Arial")
        font_size = str(entry_text.get("font_size", 14)) + "pt"
        font_color = entry_text.get("font_color", "000000")

        # Font size/color seems to not work reliably across viewers:
        # https://github.com/py-pdf/pypdf/issues/2084
        annotation = FreeText(
            text=text,
            rect=transformed_entry_box,
            font=font_name,
            font_size=font_size,
            font_color=font_color,
            border_color=None,
            background_color=None,
        )
        annotations.append(annotation)
        # page_number is 0-based for pypdf
        writer.add_annotation(page_number=page_num - 1, annotation=annotation)
        
    # Save the filled PDF
    with open(output_pdf_path, "wb") as output:
        writer.write(output)
    
    print(f"Successfully filled PDF form and saved to {output_pdf_path}")
    print(f"Added {len(annotations)} text annotations")


if __name__ == "__main__":
    args = sys.argv[1:]
    user_id = None
    if "--user-id" in args:
        idx = args.index("--user-id")
        user_id = args[idx + 1]
        del args[idx:idx + 2]

    if len(args) != 3:
        print("Usage: fill_pdf_form_with_annotations.py [input pdf] [fields.json] [output pdf] [--user-id USER]")
        sys.exit(1)
    input_pdf, fields_json, output_pdf = args

    local_root = temp_root("pdf-annotate-") if storage_is_r2() else Path(".")
    local_input = prepare_input_path(user_id, input_pdf, local_root) if storage_is_r2() else Path(input_pdf)
    local_fields = prepare_input_path(user_id, fields_json, local_root) if storage_is_r2() else Path(fields_json)
    local_output, r2_output = prepare_output_path(user_id, output_pdf, local_root)
    fill_pdf_form(local_input, local_fields, local_output)
    if storage_is_r2():
        upload_output_path(user_id, r2_output, local_output)
