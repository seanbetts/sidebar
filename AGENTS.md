# AGENTS.md

This file provides instructions for AI coding agents working on the agent-smith project.

## Project Overview

Agent-smith is a lightweight development environment for creating and managing [Agent Skills](https://agentskills.io). It provides:
- Docker container with bash + Unix environment for skill execution
- Python tooling with skills-ref for validation
- Anthropic's skill-creator for scaffolding new skills
- Collection of document processing skills (docx, xlsx, pptx, pdf, mcp-builder)

## Golden Rules (must-follow)

1. **Always validate before committing.**
   Run `./scripts/validate-all.sh` before any git commit. If validation fails, fix the issues before committing.

2. **Never modify existing skill SKILL.md without explicit user instruction.**
   Skills in `skills/` are functional units. Do not edit, reformat, or "improve" SKILL.md files unless the user explicitly requests changes to that specific skill.

3. **Use skill-creator for new skills.**
   Follow `skills/skill-creator/SKILL.md` when creating new skills. Do not create skills from scratch without using the skill-creator guidance.

4. **Follow the Agent Skills specification.**
   All skills must conform to the [Agent Skills specification](https://agentskills.io/specification). Required: YAML frontmatter with `name` and `description` fields.

5. **Keep the Docker container clean.**
   Never commit secrets, credentials, or sensitive data to skills. The Docker container is for execution only—no validation tools or dev dependencies.

6. **Run verification after any changes.**
   After editing any skill files, run `./scripts/validate-all.sh` to ensure integrity. This checks spec compliance, not correctness.

## Working Loop (default workflow)

When creating or modifying skills, follow this workflow:

1. **Use skill-creator skill to initialize**
   Read `skills/skill-creator/SKILL.md` for guidance, then run:
   `python skills/skill-creator/scripts/init_skill.py <skill-name> --path ./skills`

2. **Edit SKILL.md following spec**
   - Required YAML frontmatter: `name`, `description`
   - Markdown body with instructions
   - Optional: `scripts/`, `references/`, `assets/` directories

3. **Validate with skills-ref**
   Run: `.venv/bin/skills-ref validate skills/<skill-name>`
   Expected output: `Valid skill: skills/<skill-name>`

4. **Test in Docker if needed**
   If skill includes bundled scripts:
   ```bash
   docker compose up -d
   docker compose exec agent-smith bash
   # Test skill execution inside container
   ```

5. **Validate all skills before committing**
   Run: `./scripts/validate-all.sh`
   Expected output: `✓ All skills valid!`

6. **Commit with proper format**
   See "Commit Message Format" section below.

## Skills (authoritative procedures)

These skills provide detailed guidance for specific tasks. When the use case matches, read the relevant SKILL.md file for comprehensive instructions:

- **[skill-creator](./skills/skill-creator/SKILL.md)** - Use when creating new skills or updating existing skills. Covers skill anatomy, core principles, bundled resources, and best practices.

- **[docx](./skills/docx/SKILL.md)** - Use when working with Word documents (.docx files). Covers creation, editing, analysis, tracked changes, and comments.

- **[xlsx](./skills/xlsx/SKILL.md)** - Use when working with Excel spreadsheets (.xlsx files). Covers spreadsheet processing and manipulation.

- **[pptx](./skills/pptx/SKILL.md)** - Use when working with PowerPoint presentations (.pptx files). Covers slide creation and editing.

- **[pdf](./skills/pdf/SKILL.md)** - Use when processing PDF files. Covers text/table extraction, PDF creation, merging/splitting, and form handling.

- **mcp-builder** - Use when building MCP (Model Context Protocol) servers. Covers FastMCP (Python) and MCP SDK (Node/TypeScript) implementations.

**Principle:** Skills are authoritative. Read the relevant SKILL.md for detailed procedures rather than improvising.

## Validation (mandatory)

### When to Run Validation

- **Before every commit** - Run `./scripts/validate-all.sh`
- **After creating a new skill** - Run `.venv/bin/skills-ref validate skills/<skill-name>`
- **After editing any SKILL.md** - Run validation to ensure spec compliance

### What Passing Validation Means

- Skill name matches directory name
- YAML frontmatter is valid and complete
- Description length is 1-1024 characters
- File structure follows Agent Skills spec

**Note:** Validation checks format compliance, NOT whether the skill's instructions are correct or useful.

### What to Do if Validation Fails

1. Read the error message from skills-ref
2. Fix the specific issue (usually frontmatter or structure)
3. Re-run validation
4. Do not commit until validation passes

## File Artefacts (maintain these)

- **`skills/`** - All Agent Skills. Each subdirectory is a skill with SKILL.md.
- **`scripts/validate-all.sh`** - Validation script for all skills. Keep updated if validation logic changes.
- **`docker/Dockerfile`** - Docker configuration for bash + Unix environment. Keep minimal (no dev tools).
- **`docker-compose.yml`** - Development environment config. Mounts skills/ as volume.
- **`pyproject.toml`** - Python project config. Dev dependencies only (skills-ref).
- **`AGENTS.md`** - This file. Keep updated as project evolves.
- **`README.md`** - Human-readable documentation.

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

# Inside container - skills are mounted at /skills
ls /skills
python /skills/skill-creator/scripts/init_skill.py new-skill --path /skills

# Stop container
docker compose down
```

## Project Structure

```
agent-smith/
├── skills/              # All Agent Skills (mounted to /skills in Docker)
│   ├── skill-creator/   # Meta-skill for creating skills
│   ├── docx/            # Word document processing
│   ├── xlsx/            # Excel spreadsheet processing
│   ├── pptx/            # PowerPoint processing
│   ├── pdf/             # PDF processing
│   └── mcp-builder/     # MCP server development
├── scripts/             # Utility scripts (validate-all.sh)
├── docker/              # Docker configuration
│   └── Dockerfile       # Python 3.11-slim + bash + Unix tools
├── docker-compose.yml   # Development environment
├── pyproject.toml       # Python project config (dev dependencies only)
├── .gitignore           # Standard Python gitignore
├── .python-version      # Python 3.11
├── README.md            # Human-readable documentation
└── AGENTS.md            # This file

Skills are mounted as volumes in Docker, allowing live editing on host.
```

## Commit Message Format

Follow this format for commit messages:

```
<type>: <brief description>

<detailed description>

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
```

**Types:**
- `feat`: New feature or skill
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Formatting, whitespace
- `refactor`: Code restructuring
- `test`: Test additions
- `chore`: Maintenance tasks

**Example:**
```
feat: add web-scraping skill

Add new skill for web scraping with BeautifulSoup.
Includes example scripts and common patterns.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
```

## Security Considerations

- **Never commit secrets or credentials** to skills (API keys, passwords, tokens)
- **Be cautious with bundled scripts** that execute external commands
- **Validate all skills before deployment** to catch malformed or malicious content
- **Docker container runs as non-root** for security isolation
- **Review scripts in skills/** before execution, especially from external sources

## Validation Requirements

Before merging any changes:
- [ ] All skills pass `./scripts/validate-all.sh`
- [ ] Docker image builds successfully: `docker compose build`
- [ ] No secrets or credentials in commits
- [ ] SKILL.md files follow Agent Skills specification
- [ ] Commit message follows format above

## Useful Resources

- [Agent Skills Specification](https://agentskills.io/specification) - Complete format requirements
- [skills-ref Documentation](https://github.com/agentskills/agentskills/tree/main/skills-ref) - Validation library
- [Skill Creator Guide](./skills/skill-creator/SKILL.md) - Authoritative guide for creating skills
- [Example Skills](https://github.com/anthropics/skills) - Anthropic's official collection

## Common Issues

**SSL Certificate Errors with uv:**
```bash
# Use native TLS instead of bundled certificates
uv sync --native-tls
```

**Permission denied on scripts:**
```bash
# Make script executable
chmod +x scripts/<script-name>.sh
```

**Docker container can't access skills:**
```bash
# Ensure you're in project root when running docker compose
# Skills are mounted from ./skills to /skills in container
pwd  # Should show /Users/sean.betts/Coding/agent-smith
```

**Validation fails after editing:**
```bash
# Check exact error message
.venv/bin/skills-ref validate skills/<skill-name>

# Common issues:
# - Name in frontmatter doesn't match directory name
# - Description too long (>1024 chars) or too short (<1 char)
# - Invalid YAML frontmatter syntax
# - Missing required fields (name, description)
```

**Skill not available in Docker:**
```bash
# Ensure Docker container is running and skills are mounted
docker compose up -d
docker compose exec agent-smith ls /skills
# Should show: skill-creator docx xlsx pptx pdf mcp-builder
```
