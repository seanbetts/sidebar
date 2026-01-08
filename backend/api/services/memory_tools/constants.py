"""Constants for memory tool handling."""

from __future__ import annotations

import re

MAX_PATH_LENGTH = 500
LINE_LIMIT = 999_999
HIDDEN_PATTERN = re.compile(r"^\.")
