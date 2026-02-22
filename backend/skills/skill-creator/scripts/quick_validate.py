#!/usr/bin/env python3
"""Quick validation script for skills - minimal version."""

import re
import sys
from datetime import date, datetime
from pathlib import Path

import yaml

SEMVER_PATTERN = re.compile(r"^\d+\.\d+\.\d+(?:[-+][A-Za-z0-9.-]+)?$")
REQUIREMENT_API_KEY_MARKERS = (
    "api key",
    "api-key",
    "_api_key",
    "openai_api_key",
    "anthropic_api_key",
    "google_api_key",
    "credential",
)
REQUIREMENT_DEVELOPER_MARKERS = (
    "ffmpeg",
    "pyproject",
    "pip install",
    "brew install",
    "apt-get install",
    "system package",
    "installed via",
    "dependency",
)


def _invalid_requirement_reason(requirement_text: str) -> str | None:
    """Return a reason string when metadata.requirements entry is invalid."""
    normalized_requirement = requirement_text.strip().lower()

    if any(marker in normalized_requirement for marker in REQUIREMENT_API_KEY_MARKERS):
        return (
            "metadata.requirements should list user-facing needs only; "
            "API keys and credentials belong in credential requirement metadata"
        )

    if any(
        marker in normalized_requirement for marker in REQUIREMENT_DEVELOPER_MARKERS
    ):
        return (
            "metadata.requirements should list user-facing needs only; "
            "developer/runtime dependency details should stay in docs"
        )

    return None


def validate_skill(skill_path):
    """Basic validation of a skill."""
    skill_path = Path(skill_path)

    # Check SKILL.md exists
    skill_md = skill_path / "SKILL.md"
    if not skill_md.exists():
        return False, "SKILL.md not found"

    # Read and validate frontmatter
    content = skill_md.read_text()
    if not content.startswith("---"):
        return False, "No YAML frontmatter found"

    # Extract frontmatter
    match = re.match(r"^---\n(.*?)\n---", content, re.DOTALL)
    if not match:
        return False, "Invalid frontmatter format"

    frontmatter_text = match.group(1)

    # Parse YAML frontmatter
    try:
        frontmatter = yaml.safe_load(frontmatter_text)
        if not isinstance(frontmatter, dict):
            return False, "Frontmatter must be a YAML dictionary"
    except yaml.YAMLError as e:
        return False, f"Invalid YAML in frontmatter: {e}"

    # Define allowed properties
    allowed_properties = {
        "name",
        "description",
        "license",
        "allowed-tools",
        "metadata",
    }

    # Check for unexpected properties (excluding nested keys under metadata)
    unexpected_keys = set(frontmatter.keys()) - allowed_properties
    if unexpected_keys:
        unexpected_list = ", ".join(sorted(unexpected_keys))
        allowed_list = ", ".join(sorted(allowed_properties))
        return False, (
            "Unexpected key(s) in SKILL.md frontmatter: "
            f"{unexpected_list}. Allowed properties are: {allowed_list}"
        )

    # Check required fields
    if "name" not in frontmatter:
        return False, "Missing 'name' in frontmatter"
    if "description" not in frontmatter:
        return False, "Missing 'description' in frontmatter"

    # Extract name for validation
    name = frontmatter.get("name", "")
    if not isinstance(name, str):
        return False, f"Name must be a string, got {type(name).__name__}"
    name = name.strip()
    if name:
        # Check naming convention (hyphen-case: lowercase with hyphens)
        if not re.match(r"^[a-z0-9-]+$", name):
            return (
                False,
                f"Name '{name}' should be hyphen-case "
                "(lowercase letters, digits, and hyphens only)",
            )
        if name.startswith("-") or name.endswith("-") or "--" in name:
            return (
                False,
                f"Name '{name}' cannot start/end with hyphen "
                "or contain consecutive hyphens",
            )
        # Check name length (max 64 characters per spec)
        if len(name) > 64:
            return (
                False,
                f"Name is too long ({len(name)} characters). Maximum is 64 characters.",
            )

    # Extract and validate description
    description = frontmatter.get("description", "")
    if not isinstance(description, str):
        return False, f"Description must be a string, got {type(description).__name__}"
    description = description.strip()
    if description:
        # Check for angle brackets
        if "<" in description or ">" in description:
            return False, "Description cannot contain angle brackets (< or >)"
        # Check description length (max 1024 characters per spec)
        if len(description) > 1024:
            return (
                False,
                "Description is too long "
                f"({len(description)} characters). Maximum is 1024 characters.",
            )

    metadata = frontmatter.get("metadata")
    if metadata is not None:
        if not isinstance(metadata, dict):
            return False, "metadata must be a mapping/object when provided"

        long_description = metadata.get("long_description")
        if long_description is not None:
            if not isinstance(long_description, str):
                return False, "metadata.long_description must be a string"
            if not long_description.strip():
                return False, "metadata.long_description cannot be empty"

        how_it_works = metadata.get("how_it_works")
        if how_it_works is not None:
            if not isinstance(how_it_works, str):
                return False, "metadata.how_it_works must be a string"
            if not how_it_works.strip():
                return False, "metadata.how_it_works cannot be empty"

        requirements = metadata.get("requirements")
        if requirements is not None:
            if not isinstance(requirements, list):
                return False, "metadata.requirements must be a list of strings"
            for requirement in requirements:
                if not isinstance(requirement, str) or not requirement.strip():
                    return (
                        False,
                        "metadata.requirements entries must be non-empty strings",
                    )
                if invalid_reason := _invalid_requirement_reason(requirement):
                    return False, invalid_reason

        version = metadata.get("version")
        if version is not None:
            if not isinstance(version, str):
                return False, "metadata.version must be a string"
            normalized_version = version.strip()
            if not normalized_version:
                return False, "metadata.version cannot be empty"
            if not SEMVER_PATTERN.match(normalized_version):
                return (
                    False,
                    "metadata.version should use semantic version format (e.g. 1.2.3)",
                )

        updated_at = metadata.get("updated_at")
        if updated_at is not None:
            if isinstance(updated_at, (date, datetime)):
                pass
            elif isinstance(updated_at, str):
                raw_updated_at = updated_at.strip()
                if not raw_updated_at:
                    return False, "metadata.updated_at cannot be empty"
                try:
                    datetime.fromisoformat(raw_updated_at.replace("Z", "+00:00"))
                except ValueError:
                    try:
                        date.fromisoformat(raw_updated_at)
                    except ValueError:
                        return (
                            False,
                            "metadata.updated_at must be an ISO date or datetime",
                        )
            else:
                return False, "metadata.updated_at must be a date or ISO string"

    return True, "Skill is valid!"


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.stderr.write("Usage: python quick_validate.py <skill_directory>\n")
        sys.exit(1)

    valid, message = validate_skill(sys.argv[1])
    sys.stdout.write(f"{message}\n")
    sys.exit(0 if valid else 1)
