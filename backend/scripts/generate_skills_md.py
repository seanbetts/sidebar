#!/usr/bin/env python3
"""Generate SKILLS.md from skill frontmatter."""
import yaml
from pathlib import Path
from datetime import datetime
from typing import Dict, Optional


SKILLS_DIR = Path(__file__).parent.parent / "skills"
OUTPUT_FILE = Path(__file__).parent.parent / "SKILLS.md"


def extract_frontmatter(skill_path: Path) -> Optional[Dict]:
    """Extract YAML frontmatter from SKILL.md."""
    skill_md = skill_path / "SKILL.md"
    if not skill_md.exists():
        return None

    with open(skill_md, 'r', encoding='utf-8') as f:
        content = f.read()

    if not content.startswith('---'):
        return None

    parts = content.split('---', 2)
    if len(parts) < 3:
        return None

    try:
        frontmatter = yaml.safe_load(parts[1])
    except yaml.YAMLError:
        return None

    # Extract capabilities from metadata (or set defaults)
    if 'metadata' in frontmatter and 'capabilities' in frontmatter['metadata']:
        frontmatter['capabilities'] = frontmatter['metadata']['capabilities']
    else:
        frontmatter['capabilities'] = {
            'reads': False,
            'writes': False,
            'network': False,
            'external_apis': False
        }

    # Add skill directory name for reference
    frontmatter['_dir'] = skill_path.name

    return frontmatter


def generate_skills_md():
    """Generate SKILLS.md catalog."""
    skills = []

    # Scan all skill directories
    for skill_dir in sorted(SKILLS_DIR.iterdir()):
        if not skill_dir.is_dir():
            continue

        fm = extract_frontmatter(skill_dir)
        if not fm:
            print(f"⚠️  Skipping {skill_dir.name} - no valid frontmatter")
            continue

        skills.append(fm)

    # Categorize skills
    categories = {
        "Filesystem": ["fs", "folder-config"],
        "Notes": ["notes"],
        "Documents": ["docx", "xlsx", "pptx", "pdf"],
        "Web": ["web-save", "web-crawler-policy", "subdomain-discover", "jina-reader"],
        "Media": ["youtube-download", "youtube-transcribe", "audio-transcribe"],
        "Google Drive": ["drive-search", "drive-write"],
        "Development": ["skill-creator", "mcp-builder", "list-skills"],
        "Security": ["doppler-secrets"],
    }

    # Generate markdown
    lines = [
        "# sideBar Skills Catalog",
        "",
        f"**Last Updated:** {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}",
        f"**Total Skills:** {len(skills)}",
        "",
        "This file is auto-generated from skill frontmatter. Do not edit manually.",
        "",
        "---",
        "",
        "## Active Skills",
        ""
    ]

    # Group by category
    for category, skill_names in categories.items():
        matching = [s for s in skills if s["name"] in skill_names and not s.get("deprecated", False)]
        if not matching:
            continue

        lines.append(f"### {category}")
        lines.append("")

        for skill in matching:
            caps = skill.get('capabilities', {})
            cap_tags = []
            if caps.get('reads'):
                cap_tags.append("reads")
            if caps.get('writes'):
                cap_tags.append("writes")
            if caps.get('network'):
                cap_tags.append("network")
            if caps.get('external_apis'):
                cap_tags.append("external_apis")

            cap_str = f" `[{', '.join(cap_tags)}]`" if cap_tags else ""

            lines.append(f"#### [{skill['name']}](./skills/{skill['_dir']}/SKILL.md){cap_str}")
            lines.append(skill['description'])
            lines.append("")

    # Uncategorized skills
    categorized_names = [name for names in categories.values() for name in names]
    uncategorized = [s for s in skills if s["name"] not in categorized_names and not s.get("deprecated", False)]

    if uncategorized:
        lines.append("### Other")
        lines.append("")
        for skill in uncategorized:
            caps = skill.get('capabilities', {})
            cap_tags = []
            if caps.get('reads'):
                cap_tags.append("reads")
            if caps.get('writes'):
                cap_tags.append("writes")
            if caps.get('network'):
                cap_tags.append("network")
            if caps.get('external_apis'):
                cap_tags.append("external_apis")

            cap_str = f" `[{', '.join(cap_tags)}]`" if cap_tags else ""

            lines.append(f"#### [{skill['name']}](./skills/{skill['_dir']}/SKILL.md){cap_str}")
            lines.append(skill['description'])
            lines.append("")

    # Deprecated section
    deprecated = [s for s in skills if s.get("deprecated")]
    if deprecated:
        lines.append("---")
        lines.append("")
        lines.append("## Deprecated Skills")
        lines.append("")
        lines.append("These skills have been replaced or are no longer maintained.")
        lines.append("")
        for skill in deprecated:
            lines.append(f"- **{skill['name']}**: {skill['description']}")
        lines.append("")

    # Write file
    with open(OUTPUT_FILE, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines))

    print(f"✓ Generated {OUTPUT_FILE}")
    print(f"  {len([s for s in skills if not s.get('deprecated')])} active skills")
    print(f"  {len(deprecated)} deprecated skills")


if __name__ == "__main__":
    generate_skills_md()
