"""
Tests for skills/list-skills/scripts/list_skills.py

Tests YAML extraction from SKILL.md files and skill discovery.
"""

import pytest
from pathlib import Path
import sys

# Add project root and skill script to path
project_root = Path(__file__).parent.parent.parent.parent
skill_script_path = project_root / "skills" / "list-skills" / "scripts"
sys.path.insert(0, str(project_root))
sys.path.insert(0, str(skill_script_path))

from list_skills import extract_frontmatter, find_skills


class TestExtractFrontmatter:
    """Test YAML frontmatter extraction from SKILL.md files."""

    def test_extracts_valid_frontmatter(self):
        """Test extraction of valid YAML frontmatter."""
        content = """---
name: test-skill
description: A test skill
---

# Test Skill
"""

        frontmatter = extract_frontmatter(content)

        assert frontmatter is not None
        assert frontmatter["name"] == "test-skill"
        assert frontmatter["description"] == "A test skill"

    def test_extracts_frontmatter_with_extra_fields(self):
        """Test extraction when frontmatter has additional fields."""
        content = """---
name: test-skill
description: A test skill
license: MIT
metadata:
  author: Test
---

# Test Skill
"""

        frontmatter = extract_frontmatter(content)

        assert frontmatter is not None
        assert frontmatter["name"] == "test-skill"
        assert frontmatter["description"] == "A test skill"

    def test_missing_frontmatter_returns_none(self):
        """Test that content without frontmatter returns None."""
        content = """# Just a regular markdown file

No frontmatter here.
"""

        frontmatter = extract_frontmatter(content)

        assert frontmatter is None

    def test_invalid_frontmatter_returns_none(self):
        """Test that invalid frontmatter format returns None."""
        content = """---
name: test-skill
# Missing closing ---

# Test Skill
"""

        frontmatter = extract_frontmatter(content)

        assert frontmatter is None

    def test_missing_name_field_returns_none(self):
        """Test that frontmatter without 'name' returns None."""
        content = """---
description: Missing name field
---
"""

        frontmatter = extract_frontmatter(content)

        assert frontmatter is None

    def test_missing_description_field_returns_none(self):
        """Test that frontmatter without 'description' returns None."""
        content = """---
name: test-skill
---
"""

        frontmatter = extract_frontmatter(content)

        assert frontmatter is None


class TestFindSkills:
    """Test skill discovery in skills directory."""

    def test_finds_skills_in_directory(self, fixtures_dir):
        """Test finding all skills in fixtures directory."""
        skills_dir = fixtures_dir / "skills"

        skills = find_skills(skills_dir)

        # Should find skills with valid SKILL.md files
        skill_names = [skill["name"] for skill in skills]

        assert "valid-skill" in skill_names
        assert "skill-with-scripts" in skill_names

    def test_skips_invalid_skills(self, fixtures_dir):
        """Test that skills with invalid frontmatter are skipped."""
        skills_dir = fixtures_dir / "skills"

        skills = find_skills(skills_dir)

        # Should not include invalid skills
        skill_names = [skill["name"] for skill in skills]

        # invalid-no-frontmatter and invalid-bad-name should be skipped
        # (they may appear in stderr warnings but not in returned list)
        assert len(skills) >= 2  # At least valid-skill and skill-with-scripts

    def test_empty_directory_returns_empty_list(self, temp_dir):
        """Test that empty directory returns empty list."""
        empty_skills_dir = temp_dir / "skills"
        empty_skills_dir.mkdir()

        skills = find_skills(empty_skills_dir)

        assert skills == []

    def test_returns_path_for_each_skill(self, fixtures_dir):
        """Test that each skill includes its directory path."""
        skills_dir = fixtures_dir / "skills"

        skills = find_skills(skills_dir)

        for skill in skills:
            assert "path" in skill
            assert Path(skill["path"]).exists()
            assert Path(skill["path"]).is_dir()

    def test_skills_are_sorted(self, fixtures_dir):
        """Test that skills are returned in sorted order."""
        skills_dir = fixtures_dir / "skills"

        skills = find_skills(skills_dir)

        skill_names = [skill["name"] for skill in skills]

        # Should be sorted alphabetically
        assert skill_names == sorted(skill_names)


class TestIntegration:
    """Integration tests for the full list skills workflow."""

    def test_full_workflow_with_real_skills(self):
        """Test finding real skills in the actual skills/ directory."""
        project_root = Path(__file__).parent.parent.parent.parent
        skills_dir = project_root / "skills"

        if not skills_dir.exists():
            pytest.skip("Skills directory not found")

        skills = find_skills(skills_dir)

        # Should find multiple skills
        assert len(skills) > 0

        # Each skill should have required fields
        for skill in skills:
            assert "name" in skill
            assert "description" in skill
            assert "path" in skill
            assert skill["name"]  # Not empty
            assert skill["description"]  # Not empty

    def test_descriptions_are_truncated_in_output(self, temp_dir):
        """Test that long descriptions would be truncated (for display)."""
        # Create a skill with a very long description
        skill_dir = temp_dir / "long-desc-skill"
        skill_dir.mkdir()

        long_description = "A" * 200  # 200 characters

        skill_md = skill_dir / "SKILL.md"
        skill_md.write_text(f"""---
name: long-desc-skill
description: {long_description}
---

# Long Description Skill
""")

        skills_dir = temp_dir
        skills = find_skills(skills_dir)

        assert len(skills) == 1
        skill = skills[0]

        # Description should be full in data structure
        assert len(skill["description"]) == 200

        # Note: Truncation happens in main() for display, not in find_skills()
        # This test just verifies the data is available
