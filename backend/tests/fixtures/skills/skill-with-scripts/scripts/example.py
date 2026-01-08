#!/usr/bin/env python3
"""Example script with various imports for testing dependency detection.
"""

# Standard library imports (should be filtered out)
import json  # noqa: F401
import os  # noqa: F401
import re  # noqa: F401
import sys  # noqa: F401
from datetime import datetime  # noqa: F401

import numpy as np  # noqa: F401
import pandas as pd  # noqa: F401

# External package imports (should be detected)
import requests  # noqa: F401
import skills  # noqa: F401

# Local imports (should be filtered out)
from ooxml import pack  # noqa: F401
from PIL import Image  # noqa: F401


def main():
    """Example function."""
    pass


if __name__ == "__main__":
    main()
