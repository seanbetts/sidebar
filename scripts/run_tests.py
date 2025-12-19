#!/usr/bin/env python3
"""
Test runner for agent-smith project.

Usage:
    # Run all tests
    python scripts/run_tests.py

    # Run specific test file
    python scripts/run_tests.py tests/scripts/test_add_skill_dependencies.py

    # Run with coverage
    python scripts/run_tests.py --cov

    # Run in parallel
    python scripts/run_tests.py -n auto

    # Run only fast tests
    python scripts/run_tests.py -m "not slow"
"""

import sys
import subprocess
from pathlib import Path


def main():
    # Ensure we're in project root
    project_root = Path(__file__).parent.parent

    # Build pytest command
    cmd = [str(project_root / ".venv" / "bin" / "pytest")]

    # Add any arguments passed to this script
    cmd.extend(sys.argv[1:])

    # Run pytest
    result = subprocess.run(cmd, cwd=project_root)
    sys.exit(result.returncode)


if __name__ == "__main__":
    main()
