import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw

BACKEND_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(BACKEND_ROOT))

from api.services.skill_file_transfer import (  # noqa: E402
    prepare_input_path,
    prepare_output_path,
    upload_output_path,
    storage_is_r2,
    temp_root,
)

# Creates "validation" images with rectangles for the bounding box information that
# Claude creates when determining where to add text annotations in PDFs. See forms.md.


def create_validation_image(page_number, fields_json_path: Path, input_path: Path, output_path: Path):
    # Input file should be in the `fields.json` format described in forms.md.
    with open(fields_json_path, 'r') as f:
        data = json.load(f)

        img = Image.open(input_path)
        draw = ImageDraw.Draw(img)
        num_boxes = 0
        
        for field in data["form_fields"]:
            if field["page_number"] == page_number:
                entry_box = field['entry_bounding_box']
                label_box = field['label_bounding_box']
                # Draw red rectangle over entry bounding box and blue rectangle over the label.
                draw.rectangle(entry_box, outline='red', width=2)
                draw.rectangle(label_box, outline='blue', width=2)
                num_boxes += 2
        
        img.save(output_path)
        print(f"Created validation image at {output_path} with {num_boxes} bounding boxes")


if __name__ == "__main__":
    args = sys.argv[1:]
    user_id = None
    if "--user-id" in args:
        idx = args.index("--user-id")
        user_id = args[idx + 1]
        del args[idx:idx + 2]

    if len(args) != 4:
        print("Usage: create_validation_image.py [page number] [fields.json file] [input image path] [output image path] [--user-id USER]")
        sys.exit(1)
    page_number = int(args[0])
    fields_json_path = args[1]
    input_image_path = args[2]
    output_image_path = args[3]

    local_root = temp_root("pdf-validate-") if storage_is_r2() else Path(".")
    local_fields = prepare_input_path(user_id, fields_json_path, local_root) if storage_is_r2() else Path(fields_json_path)
    local_input = prepare_input_path(user_id, input_image_path, local_root) if storage_is_r2() else Path(input_image_path)
    local_output, r2_output = prepare_output_path(user_id, output_image_path, local_root)
    create_validation_image(page_number, local_fields, local_input, local_output)
    if storage_is_r2():
        upload_output_path(user_id, r2_output, local_output)
