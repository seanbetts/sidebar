---
name: list-skills
description: Lists all available Agent Skills with their names and descriptions. Use when you need to show the user what skills are available or help them discover capabilities.
---

# List Skills

## Overview

This skill provides a quick way to retrieve all available Agent Skills in the system along with their descriptions. Use this skill when:

- The user asks "what skills are available?" or "what can you do?"
- You need to show available capabilities to help the user accomplish a task
- You want to discover which skills exist in the system
- You need to verify if a specific skill is available

## Quick Start

To list all skills, run the bundled script:

```bash
python /skills/list-skills/scripts/list_skills.py
```

**Output format:**
```
Available Skills:
1. skill-creator - Meta-skill for creating new Agent Skills...
2. docx - Process Word documents (.docx files)...
3. xlsx - Process Excel spreadsheets (.xlsx files)...
...
```

## When to Use This Skill

**Use this skill when:**
- User asks: "What skills do you have?", "What can you help me with?", "Show me available skills"
- You need to help the user discover relevant capabilities for their task
- You want to confirm a specific skill exists before attempting to use it
- The user is exploring what's possible with the agent

**Don't use this skill when:**
- You already know which specific skill to use for a task
- The user is asking about a specific skill's detailed functionality (use that skill's SKILL.md instead)

## Script Details

### list_skills.py

Scans the `/skills` directory and extracts skill information from each SKILL.md file.

**What it does:**
1. Finds all skill directories in `/skills`
2. Reads the YAML frontmatter from each SKILL.md
3. Extracts the `name` and `description` fields
4. Returns a formatted list

**Dependencies:** None (uses only Python standard library)

**Usage:**
```bash
# From inside Docker container
python /skills/list-skills/scripts/list_skills.py

# From host machine
docker compose exec agent-smith python /skills/list-skills/scripts/list_skills.py
```

## Example Usage

**User request:** "What skills are available?"

**Agent response:**
```
Let me show you all available skills:

[runs: python /skills/list-skills/scripts/list_skills.py]

Available Skills:
1. skill-creator - Meta-skill for creating new Agent Skills with proper structure...
2. docx - Process Word documents: create, edit, analyze, track changes...
3. xlsx - Process Excel spreadsheets: read, write, manipulate data...
4. pptx - Process PowerPoint presentations: create slides, edit content...
5. pdf - Process PDF files: extract text, merge, split, fill forms...
6. mcp-builder - Build MCP (Model Context Protocol) servers...
7. list-skills - Lists all available Agent Skills with descriptions...
```

## Notes

- The script only reads SKILL.md files, it doesn't execute any skills
- If a skill's SKILL.md is malformed or missing frontmatter, it will be skipped with a warning
- This skill is read-only and has no side effects
- The list is generated dynamically, so newly added skills appear automatically
