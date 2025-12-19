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

## Managing Skill Dependencies

When creating skills with bundled scripts that require external Python packages:

### Automated Approach (Recommended)

1. **Scan skill for dependencies**
   ```bash
   python scripts/add_skill_dependencies.py <skill-name>
   ```
   This helper script will:
   - Scan all Python scripts in the skill's `scripts/` directory
   - Detect imported packages using AST parsing
   - Filter out standard library modules
   - Show which external packages are needed
   - Update `pyproject.toml` with missing dependencies

2. **Rebuild Docker container**
   ```bash
   docker compose build
   docker compose up -d
   ```
   The Docker container automatically installs all dependencies from `pyproject.toml` at build time.

3. **Verify in container**
   ```bash
   docker compose exec agent-smith python -c "import requests; import pypdf"
   ```

### Manual Approach

If you prefer manual control or the helper script doesn't detect something:

1. **Add dependency to pyproject.toml**
   Edit the `dependencies` list in `pyproject.toml`:
   ```toml
   dependencies = [
       "your-package>=1.0.0",
   ]
   ```

2. **Rebuild Docker container**
   ```bash
   docker compose build
   docker compose up -d
   ```

### Currently Installed Packages

These packages are already available in the Docker container:
- **pypdf** - PDF processing (pdf skill)
- **python-pptx** - PowerPoint processing (pptx skill)
- **Pillow** - Image manipulation (used by pptx skill)
- **defusedxml** - Safe XML parsing (used by docx/pptx ooxml scripts)
- **requests** - HTTP library (for custom scripts)

### Important Notes

- **All skill dependencies** must go in `pyproject.toml` `dependencies` (not `dev` group)
- **Dev dependencies** (like `skills-ref`) stay in `[dependency-groups]` and are NOT installed in Docker
- **Local modules** (like `ooxml/` in docx/pptx skills) don't need to be added - they're bundled with the skill
- **Rebuild required** - You must rebuild Docker whenever dependencies change

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

## Testing (TDD workflow)

### Running Tests

**Before every commit** - Run tests to ensure no regressions:

```bash
# Run all tests on host
python scripts/run_tests.py

# Run specific test file
python scripts/run_tests.py tests/scripts/test_add_skill_dependencies.py

# Run tests in Docker
./scripts/run_tests_docker.sh

# Run tests with coverage report
python scripts/run_tests.py --cov
```

### Test-Driven Development (TDD)

When adding new features to scripts or utilities:

1. **Write tests first**
   ```bash
   # Create test file
   vim tests/scripts/test_my_new_feature.py

   # Write test cases for expected behavior
   def test_my_new_feature_basic_case():
       result = my_new_feature("input")
       assert result == "expected output"
   ```

2. **Run tests (they should fail)**
   ```bash
   python scripts/run_tests.py tests/scripts/test_my_new_feature.py
   # Expected: FAILED (feature not implemented yet)
   ```

3. **Implement the feature**
   ```bash
   vim scripts/my_new_script.py
   # Write the actual implementation
   ```

4. **Run tests again (they should pass)**
   ```bash
   python scripts/run_tests.py tests/scripts/test_my_new_feature.py
   # Expected: PASSED
   ```

5. **Run all tests before committing**
   ```bash
   python scripts/run_tests.py
   ./scripts/validate-all.sh
   git add .
   git commit -m "feat: add my new feature"
   ```

### What to Test

**Test these:**
- ✅ Scripts that modify files (add_skill_dependencies.py)
- ✅ Validation logic (quick_validate.py)
- ✅ Helper modules used by multiple scripts (utilities.py, XMLEditor)
- ✅ Complex domain logic (text extraction, document manipulation)

**Don't test these:**
- ❌ Simple glue scripts (one-time utilities)
- ❌ Scripts that only call other libraries
- ❌ SKILL.md files (validated by skills-ref)

### Test Structure

All tests live in the central `tests/` directory:

```
tests/
├── scripts/           # Tests for scripts/ directory
├── skills/            # Tests for skills/**/scripts/
├── fixtures/          # Test data (sample files)
└── conftest.py        # Shared fixtures
```

### Writing Good Tests

**Use fixtures from conftest.py:**
```python
def test_with_temp_directory(temp_dir):
    # temp_dir is a Path object to temporary directory
    test_file = temp_dir / "test.txt"
    test_file.write_text("content")
    assert test_file.exists()
```

**Test edge cases:**
```python
def test_handles_missing_file():
    with pytest.raises(FileNotFoundError):
        process_file("nonexistent.txt")
```

**Use descriptive names:**
```python
# Good
def test_add_skill_dependencies_filters_stdlib_modules():
    ...

# Bad
def test_filter():
    ...
```

### Test Coverage

Focus on testing critical functionality:
- ✅ Dependency management workflow (add_skill_dependencies.py)
- ✅ Skill validation (quick_validate.py)
- ✅ Skill discovery (list_skills.py)

Coverage reports are generated in `htmlcov/` directory after running tests with `--cov`.

## File Artefacts (maintain these)

- **`skills/`** - All Agent Skills. Each subdirectory is a skill with SKILL.md.
- **`tests/`** - Test suite for critical scripts and utilities. Uses pytest framework.
- **`scripts/validate-all.sh`** - Validation script for all skills. Keep updated if validation logic changes.
- **`scripts/add_skill_dependencies.py`** - Helper script to scan skill imports and update pyproject.toml.
- **`scripts/run_tests.py`** - Test runner for host environment.
- **`scripts/run_tests_docker.sh`** - Test runner for Docker environment.
- **`docker/Dockerfile`** - Docker configuration for bash + Unix environment with auto-installed dependencies.
- **`docker-compose.yml`** - Development environment config. Mounts skills/ and tests/ as volumes.
- **`pyproject.toml`** - Python project config. Runtime dependencies for skills, dev dependencies for validation and testing.
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
