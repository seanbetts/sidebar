import os
import sys
from pathlib import Path

from pdf2image import convert_from_path

BACKEND_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(BACKEND_ROOT))

from api.services.skill_file_transfer import (  # noqa: E402
    prepare_input_path,
    prepare_output_path,
    upload_output_dir,
    storage_is_r2,
    temp_root,
)

# Converts each page of a PDF to a PNG image.


def convert(pdf_path: Path, output_dir: Path, max_dim=1000):
    images = convert_from_path(str(pdf_path), dpi=200)

    for i, image in enumerate(images):
        # Scale image if needed to keep width/height under `max_dim`
        width, height = image.size
        if width > max_dim or height > max_dim:
            scale_factor = min(max_dim / width, max_dim / height)
            new_width = int(width * scale_factor)
            new_height = int(height * scale_factor)
            image = image.resize((new_width, new_height))
        
        image_path = os.path.join(output_dir, f"page_{i+1}.png")
        image.save(image_path)
        print(f"Saved page {i+1} as {image_path} (size: {image.size})")

    print(f"Converted {len(images)} pages to PNG images")


if __name__ == "__main__":
    args = sys.argv[1:]
    user_id = None
    if "--user-id" in args:
        idx = args.index("--user-id")
        user_id = args[idx + 1]
        del args[idx:idx + 2]

    if len(args) != 2:
        print("Usage: convert_pdf_to_images.py [input pdf] [output directory] [--user-id USER]")
        sys.exit(1)

    pdf_path, output_directory = args
    local_root = temp_root("pdf-images-") if storage_is_r2() else Path(".")
    local_input = prepare_input_path(user_id, pdf_path, local_root) if storage_is_r2() else Path(pdf_path)
    local_output, r2_output = prepare_output_path(user_id, output_directory, local_root)
    local_output.mkdir(parents=True, exist_ok=True)
    convert(local_input, local_output)
    if storage_is_r2():
        upload_output_dir(user_id, r2_output, local_output)
