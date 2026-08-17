"""Import-boundary regressions for the ingestion worker claim path."""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path


BACKEND_ROOT = Path(__file__).resolve().parents[2]


def test_ingestion_worker_import_defers_processing_dependencies() -> None:
    """Cold worker import should not load dependencies needed only after claim."""
    processing_dependencies = (
        "pdfplumber",
        "docx",
        "pdfminer",
        "PIL",
        "pptx",
        "pypdf",
        "python_calamine",
        "tabulate",
        "botocore",
        "api.services.file_ingestion_service",
        "api.services.website_transcript_service",
        "api.services.storage.service",
    )
    probe = (
        "import json, sys\n"
        "import workers.ingestion_worker\n"
        f"names = {processing_dependencies!r}\n"
        "print(json.dumps([name for name in names if name in sys.modules]))\n"
    )

    result = subprocess.run(
        [sys.executable, "-c", probe],
        cwd=BACKEND_ROOT,
        check=True,
        capture_output=True,
        text=True,
    )

    assert json.loads(result.stdout) == []
