# AGENTS.md

This file provides instructions for AI coding agents working on the agent-smith project.

## Project Overview

Agent-smith is a lightweight development environment for creating and managing [Agent Skills](https://agentskills.io). It provides:
- Docker container with bash + Unix environment for skill execution
- Python tooling with skills-ref for validation
- Anthropic's skill-creator for scaffolding new skills
- Collection of document processing skills (docx, xlsx, pptx, pdf, mcp-builder)

## Setup Commands

```bash
# Install development dependencies (skills-ref for validation)
uv sync --native-tls

# Note: Use --native-tls flag if encountering SSL certificate errors
# Alternatively, use the virtual environment directly:
.venv/bin/skills-ref validate skills/skill-creator
```

## Docker Commands

```bash
# Build Docker image
docker compose build

# Start container (detached)
docker compose up -d

# Enter interactive shell
docker compose exec agent-smith bash

# Stop container
docker compose down
```

## Validation & Testing

```bash
# Validate a single skill
.venv/bin/skills-ref validate skills/<skill-name>

# Validate all skills in repository
./scripts/validate-all.sh

# Expected output: "✓ All skills valid!"
```

## Creating New Skills

Use the included skill-creator skill:

```bash
# Initialize new skill
python skills/skill-creator/scripts/init_skill.py <skill-name> --path ./skills

# Edit the skill
vim skills/<skill-name>/SKILL.md

# Validate before committing
.venv/bin/skills-ref validate skills/<skill-name>
```

## Skill Structure

Every skill must have:
- `SKILL.md` - Required file with YAML frontmatter (name, description) and Markdown instructions
- `scripts/` - Optional executable code
- `references/` - Optional documentation files
- `assets/` - Optional templates and resources

## Code Style

- Use standard Markdown formatting for SKILL.md files
- Shell scripts should be executable (`chmod +x`)
- Python scripts should include shebang line (`#!/usr/bin/env python3`)
- Keep SKILL.md files under 500 lines (use references/ for extended docs)

## Commit Message Format

Follow this format for commit messages:

```
<type>: <brief description>

<detailed description>

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
```

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`

## Development Workflow

1. **Before starting work**: Pull latest changes, run validation
2. **Creating skills**: Use skill-creator, follow Agent Skills spec
3. **Validation**: Always validate before committing (`./scripts/validate-all.sh`)
4. **Docker testing**: Test skills in container environment if using bundled scripts
5. **Committing**: Stage files, write descriptive commit message, push

## Project Structure

```
agent-smith/
├── skills/              # All Agent Skills (mounted to /skills in Docker)
├── scripts/             # Utility scripts (validate-all.sh)
├── docker/              # Docker configuration
│   └── Dockerfile       # Python 3.11-slim + bash + Unix tools
├── docker-compose.yml   # Development environment
├── pyproject.toml       # Python project config (dev dependencies only)
├── .gitignore           # Standard Python gitignore
├── .python-version      # Python 3.11
├── README.md            # Human-readable documentation
└── AGENTS.md            # This file

Skills are mounted as volumes in Docker, allowing live editing.
```

## Security Considerations

- Never commit secrets or credentials to skills
- Be cautious with bundled scripts that execute external commands
- Validate all skills before deployment
- Docker container runs as non-root user for security

## Validation Requirements

Before merging:
- [ ] All skills pass `./scripts/validate-all.sh`
- [ ] Docker image builds successfully
- [ ] No secrets or credentials in commits
- [ ] SKILL.md files follow Agent Skills specification

## Useful Resources

- [Agent Skills Specification](https://agentskills.io/specification)
- [skills-ref Documentation](https://github.com/agentskills/agentskills/tree/main/skills-ref)
- [Skill Creator Guide](./skills/skill-creator/SKILL.md)
- [Example Skills](https://github.com/anthropics/skills)

## Common Issues

**SSL Certificate Errors with uv:**
```bash
# Use native TLS
uv sync --native-tls
```

**Permission denied on scripts:**
```bash
# Make script executable
chmod +x scripts/<script-name>.sh
```

**Docker container can't access skills:**
```bash
# Ensure you're in the project root when running docker compose
# Skills are mounted from ./skills to /skills in container
```
