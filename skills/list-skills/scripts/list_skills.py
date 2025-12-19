#!/usr/bin/env python3
"""
List all available Agent Skills with their names and descriptions.

Scans the /skills directory and extracts skill information from SKILL.md files.
Uses only Python standard library - no external dependencies required.
"""

import re
import sys
from pathlib import Path
from typing import List, Dict, Optional


def extract_frontmatter(content: str) -> Optional[Dict[str, str]]:
    """
    Extract YAML frontmatter from a SKILL.md file.

    Returns a dict with 'name' and 'description' fields, or None if invalid.
    """
    # Match YAML frontmatter between --- delimiters
    frontmatter_pattern = r'^---\s*\n(.*?)\n---\s*\n'
    match = re.match(frontmatter_pattern, content, re.DOTALL)

    if not match:
        return None

    frontmatter_content = match.group(1)

    # Extract name and description fields
    name_match = re.search(r'^name:\s*(.+)$', frontmatter_content, re.MULTILINE)
    desc_match = re.search(r'^description:\s*(.+)$', frontmatter_content, re.MULTILINE)

    if not name_match or not desc_match:
        return None

    return {
        'name': name_match.group(1).strip(),
        'description': desc_match.group(1).strip()
    }


def find_skills(skills_dir: Path) -> List[Dict[str, str]]:
    """
    Find all skills in the skills directory.

    Returns a list of dicts with 'name', 'description', and 'path' fields.
    """
    skills = []

    # Find all SKILL.md files
    for skill_md in sorted(skills_dir.glob('*/SKILL.md')):
        skill_name = skill_md.parent.name

        try:
            content = skill_md.read_text(encoding='utf-8')
            frontmatter = extract_frontmatter(content)

            if frontmatter:
                skills.append({
                    'name': frontmatter['name'],
                    'description': frontmatter['description'],
                    'path': str(skill_md.parent)
                })
            else:
                print(f"⚠️  Warning: Could not parse frontmatter in {skill_name}/SKILL.md", file=sys.stderr)
        except Exception as e:
            print(f"⚠️  Warning: Error reading {skill_name}/SKILL.md: {e}", file=sys.stderr)

    return skills


def main():
    # Determine skills directory
    # If running in Docker, use /skills
    # If running from host, use ./skills relative to project root
    skills_dir = Path('/skills')
    if not skills_dir.exists():
        # Try relative path from project root
        skills_dir = Path(__file__).parent.parent.parent.parent / 'skills'
        if not skills_dir.exists():
            print("❌ Error: Could not find skills directory", file=sys.stderr)
            sys.exit(1)

    # Find all skills
    skills = find_skills(skills_dir)

    if not skills:
        print("No skills found")
        return

    # Print formatted list
    print("Available Skills:")
    print()
    for i, skill in enumerate(skills, 1):
        # Truncate long descriptions for readability
        desc = skill['description']
        if len(desc) > 100:
            desc = desc[:97] + '...'

        print(f"{i}. {skill['name']}")
        print(f"   {desc}")
        print()


if __name__ == '__main__':
    main()
