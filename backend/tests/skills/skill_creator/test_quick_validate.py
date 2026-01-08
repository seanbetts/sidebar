"""Tests for skills/skill-creator/scripts/quick_validate.py

Tests YAML frontmatter validation, name/description rules,
and error message generation.
"""

import sys
from pathlib import Path

# Add project root and skill script to path
project_root = Path(__file__).parent.parent.parent.parent
skill_script_path = project_root / "skills" / "skill-creator" / "scripts"
sys.path.insert(0, str(project_root))
sys.path.insert(0, str(skill_script_path))

from quick_validate import validate_skill  # noqa: E402


class TestValidSkills:
    """Test validation of valid skills."""

    def test_minimal_valid_skill(self, temp_dir):
        """Test validation of minimal valid skill."""
        skill_dir = temp_dir / "test-skill"
        skill_dir.mkdir()

        skill_md = skill_dir / "SKILL.md"
        skill_md.write_text("""---
name: test-skill
description: A valid test skill
---

# Test Skill
""")

        valid, message = validate_skill(skill_dir)

        assert valid is True
        assert "valid" in message.lower()

    def test_skill_with_all_fields(self, temp_dir):
        """Test validation of skill with all optional fields."""
        skill_dir = temp_dir / "test-skill"
        skill_dir.mkdir()

        skill_md = skill_dir / "SKILL.md"
        skill_md.write_text("""---
name: test-skill
description: A test skill with all fields
license: MIT
allowed-tools: [Read, Write, Bash]
metadata:
  author: Test Author
  version: 1.0.0
---

# Test Skill
""")

        valid, message = validate_skill(skill_dir)

        assert valid is True

    def test_skill_with_long_description(self, temp_dir):
        """Test validation of skill with maximum description length."""
        skill_dir = temp_dir / "test-skill"
        skill_dir.mkdir()

        # Create description with exactly 1024 characters
        description = "A" * 1024

        skill_md = skill_dir / "SKILL.md"
        skill_md.write_text(f"""---
name: test-skill
description: {description}
---

# Test Skill
""")

        valid, message = validate_skill(skill_dir)

        assert valid is True


class TestMissingFrontmatter:
    """Test detection of missing or invalid frontmatter."""

    def test_no_frontmatter(self, temp_dir):
        """Test skill without YAML frontmatter fails."""
        skill_dir = temp_dir / "test-skill"
        skill_dir.mkdir()

        skill_md = skill_dir / "SKILL.md"
        skill_md.write_text("# Just a regular markdown file")

        valid, message = validate_skill(skill_dir)

        assert valid is False
        assert "frontmatter" in message.lower()

    def test_invalid_frontmatter_format(self, temp_dir):
        """Test skill with invalid frontmatter format fails."""
        skill_dir = temp_dir / "test-skill"
        skill_dir.mkdir()

        skill_md = skill_dir / "SKILL.md"
        skill_md.write_text("""---
name: test-skill
# Missing closing ---
""")

        valid, message = validate_skill(skill_dir)

        assert valid is False
        assert "frontmatter" in message.lower()

    def test_invalid_yaml_syntax(self, temp_dir):
        """Test skill with invalid YAML syntax fails."""
        skill_dir = temp_dir / "test-skill"
        skill_dir.mkdir()

        skill_md = skill_dir / "SKILL.md"
        skill_md.write_text("""---
name: test-skill
description: "unclosed string
---
""")

        valid, message = validate_skill(skill_dir)

        assert valid is False
        assert "YAML" in message or "yaml" in message.lower()


class TestRequiredFields:
    """Test validation of required fields."""

    def test_missing_name(self, temp_dir):
        """Test skill without 'name' field fails."""
        skill_dir = temp_dir / "test-skill"
        skill_dir.mkdir()

        skill_md = skill_dir / "SKILL.md"
        skill_md.write_text("""---
description: Missing name field
---
""")

        valid, message = validate_skill(skill_dir)

        assert valid is False
        assert "name" in message.lower()

    def test_missing_description(self, temp_dir):
        """Test skill without 'description' field fails."""
        skill_dir = temp_dir / "test-skill"
        skill_dir.mkdir()

        skill_md = skill_dir / "SKILL.md"
        skill_md.write_text("""---
name: test-skill
---
""")

        valid, message = validate_skill(skill_dir)

        assert valid is False
        assert "description" in message.lower()


class TestNameValidation:
    """Test skill name validation rules."""

    def test_name_with_uppercase_fails(self, temp_dir):
        """Test skill name with uppercase letters fails."""
        skill_dir = temp_dir / "test-skill"
        skill_dir.mkdir()

        skill_md = skill_dir / "SKILL.md"
        skill_md.write_text("""---
name: Test-Skill
description: Invalid name
---
""")

        valid, message = validate_skill(skill_dir)

        assert valid is False
        assert "hyphen-case" in message or "lowercase" in message

    def test_name_with_underscores_fails(self, temp_dir):
        """Test skill name with underscores fails."""
        skill_dir = temp_dir / "test-skill"
        skill_dir.mkdir()

        skill_md = skill_dir / "SKILL.md"
        skill_md.write_text("""---
name: test_skill
description: Invalid name with underscores
---
""")

        valid, message = validate_skill(skill_dir)

        assert valid is False
        assert "hyphen-case" in message or "lowercase" in message

    def test_name_with_spaces_fails(self, temp_dir):
        """Test skill name with spaces fails."""
        skill_dir = temp_dir / "test-skill"
        skill_dir.mkdir()

        skill_md = skill_dir / "SKILL.md"
        skill_md.write_text("""---
name: test skill
description: Invalid name with spaces
---
""")

        valid, message = validate_skill(skill_dir)

        assert valid is False
        assert "hyphen-case" in message

    def test_name_starting_with_hyphen_fails(self, temp_dir):
        """Test skill name starting with hyphen fails."""
        skill_dir = temp_dir / "test-skill"
        skill_dir.mkdir()

        skill_md = skill_dir / "SKILL.md"
        skill_md.write_text("""---
name: -test-skill
description: Invalid name starting with hyphen
---
""")

        valid, message = validate_skill(skill_dir)

        assert valid is False
        assert "hyphen" in message.lower()

    def test_name_ending_with_hyphen_fails(self, temp_dir):
        """Test skill name ending with hyphen fails."""
        skill_dir = temp_dir / "test-skill"
        skill_dir.mkdir()

        skill_md = skill_dir / "SKILL.md"
        skill_md.write_text("""---
name: test-skill-
description: Invalid name ending with hyphen
---
""")

        valid, message = validate_skill(skill_dir)

        assert valid is False
        assert "hyphen" in message.lower()

    def test_name_with_consecutive_hyphens_fails(self, temp_dir):
        """Test skill name with consecutive hyphens fails."""
        skill_dir = temp_dir / "test-skill"
        skill_dir.mkdir()

        skill_md = skill_dir / "SKILL.md"
        skill_md.write_text("""---
name: test--skill
description: Invalid name with consecutive hyphens
---
""")

        valid, message = validate_skill(skill_dir)

        assert valid is False
        assert "hyphen" in message.lower()

    def test_name_too_long_fails(self, temp_dir):
        """Test skill name exceeding 64 characters fails."""
        skill_dir = temp_dir / "test-skill"
        skill_dir.mkdir()

        # Create name with 65 characters
        long_name = "a" * 65

        skill_md = skill_dir / "SKILL.md"
        skill_md.write_text(f"""---
name: {long_name}
description: Name too long
---
""")

        valid, message = validate_skill(skill_dir)

        assert valid is False
        assert "64" in message  # Error message should mention the limit


class TestDescriptionValidation:
    """Test description validation rules."""

    def test_description_with_angle_brackets_fails(self, temp_dir):
        """Test description with angle brackets fails."""
        skill_dir = temp_dir / "test-skill"
        skill_dir.mkdir()

        skill_md = skill_dir / "SKILL.md"
        skill_md.write_text("""---
name: test-skill
description: Description with <angle> brackets
---
""")

        valid, message = validate_skill(skill_dir)

        assert valid is False
        assert "angle bracket" in message.lower() or "<" in message or ">" in message

    def test_description_too_long_fails(self, temp_dir):
        """Test description exceeding 1024 characters fails."""
        skill_dir = temp_dir / "test-skill"
        skill_dir.mkdir()

        # Create description with 1025 characters
        long_description = "A" * 1025

        skill_md = skill_dir / "SKILL.md"
        skill_md.write_text(f"""---
name: test-skill
description: {long_description}
---
""")

        valid, message = validate_skill(skill_dir)

        assert valid is False
        assert "1024" in message  # Error message should mention the limit


class TestUnexpectedProperties:
    """Test detection of unexpected properties."""

    def test_unexpected_top_level_property_fails(self, temp_dir):
        """Test skill with unexpected top-level property fails."""
        skill_dir = temp_dir / "test-skill"
        skill_dir.mkdir()

        skill_md = skill_dir / "SKILL.md"
        skill_md.write_text("""---
name: test-skill
description: Valid description
unexpected_field: This should not be here
---
""")

        valid, message = validate_skill(skill_dir)

        assert valid is False
        assert "unexpected" in message.lower() or "unexpected_field" in message

    def test_metadata_nested_properties_allowed(self, temp_dir):
        """Test that nested properties under metadata are allowed."""
        skill_dir = temp_dir / "test-skill"
        skill_dir.mkdir()

        skill_md = skill_dir / "SKILL.md"
        skill_md.write_text("""---
name: test-skill
description: Valid description
metadata:
  author: Test Author
  custom_field: This is fine
---
""")

        valid, message = validate_skill(skill_dir)

        # Should pass - metadata can have arbitrary nested properties
        assert valid is True


class TestMissingSkillFile:
    """Test handling of missing SKILL.md file."""

    def test_missing_skill_md(self, temp_dir):
        """Test skill directory without SKILL.md fails."""
        skill_dir = temp_dir / "test-skill"
        skill_dir.mkdir()

        valid, message = validate_skill(skill_dir)

        assert valid is False
        assert "SKILL.md" in message or "not found" in message.lower()
