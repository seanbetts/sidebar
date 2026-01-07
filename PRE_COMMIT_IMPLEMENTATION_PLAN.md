# Pre-Commit Hooks Implementation Plan

## Executive Summary

This document outlines a phased approach to implementing pre-commit hooks for the sideBar project. Pre-commit automation will enforce code quality standards across Python (backend), TypeScript/Svelte (frontend), and Swift (iOS - future) codebases, preventing standards drift during context switching and multi-platform development.

**Current State**: Comprehensive quality tooling configured but no automated enforcement
**Target State**: Automated pre-commit hooks catch quality issues before commit
**Timeline**: 1-2 sessions for Phase 1, incremental additions over 2-3 weeks
**Complexity**: Low (leveraging existing configurations)

---

## Current State Analysis

### Existing Configuration (Well Established)

**Backend Python:**
- ✅ mypy configured (strict mode, `backend/pyproject.toml` lines 142-149)
- ✅ interrogate configured (80% docstring coverage, lines 117-135)
- ✅ pydocstyle configured (Google convention, lines 137-140)
- ✅ pytest with 90%+ coverage target (lines 95-115)
- ⚠️ **Ruff config location to confirm** (prefer `backend/pyproject.toml` to avoid drift)
- ❌ **No automatic code formatting**

**Frontend TypeScript/Svelte:**
- ✅ ESLint configured (`frontend/eslint.config.js`, 111 lines)
- ✅ TypeScript strict mode (`frontend/tsconfig.json`)
- ✅ JSDoc enforcement (warnings only, not errors)
- ❌ **No Prettier or code formatter configured**
- ❌ **ESLint only checks `src/lib/**/*.ts` (missing .svelte, routes)**

**Documentation:**
- ✅ Comprehensive `docs/QUALITY_ENFORCEMENT.md` (838 lines)
- ✅ Complete pre-commit config templates
- ✅ File size checking script template
- ❌ **Templates not activated** (no `.pre-commit-config.yaml` in repo)

### Quality Gaps Identified

1. **No automated enforcement** - relies on manual discipline
2. **Inconsistent formatting** - depends on IDE settings
3. **Partial linting coverage** - ESLint misses .svelte files, routes
4. **JSDoc warnings only** - not enforced as errors
5. **No debug artifact detection** - console.log, print() can slip through
6. **No protection against large commits** - file size limits not enforced

### Why Pre-Commit Now?

**Multi-Platform Complexity:**
- Python backend + TypeScript frontend + Swift iOS (upcoming)
- Three different ecosystems need consistent quality gates

**Solo Development with Context Switching:**
- Planning to alternate between iOS development and other features
- Pre-commit prevents standards drift during context switches
- No need to remember "did I run the linter?"

**Excellent Foundation:**
- Tools already configured and documented
- Just need to activate automation layer
- Code already follows standards (minimal disruption)

---

## Implementation Plan

### Phase 1: Essential Automation (Week 1)
**Effort**: 1-2 hours | **Priority**: Critical

#### Objectives
- Set up pre-commit framework
- Enable Python formatting and linting
- Enable frontend formatting
- Add basic file hygiene checks

#### Deliverables

**1.1 Create `.pre-commit-config.yaml`**

```yaml
# .pre-commit-config.yaml
repos:
  # Python - Ruff (linting + formatting)
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.8.4
    hooks:
      - id: ruff
        args: [--fix]
      - id: ruff-format

  # Python - Type checking
  - repo: https://github.com/pre-commit/mirrors-mypy
    rev: v1.13.0
    hooks:
      - id: mypy
        files: ^backend/api/
        args: [--config-file=backend/pyproject.toml]
        additional_dependencies:
          - sqlalchemy[mypy]
          - pydantic
          - fastapi
          - types-requests

  # Frontend - Prettier formatting
  - repo: https://github.com/pre-commit/mirrors-prettier
    rev: v4.0.0-alpha.8
    hooks:
      - id: prettier
        files: \.(ts|js|svelte|json|md|yml|yaml)$
        args: [--write, --plugin=prettier-plugin-svelte]
        additional_dependencies:
          - prettier@3.4.2
          - prettier-plugin-svelte@3.2.8

  # General - File hygiene
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v5.0.0
    hooks:
      - id: check-added-large-files
        args: [--maxkb=1000]
      - id: check-json
      - id: check-yaml
      - id: check-merge-conflict
      - id: end-of-file-fixer
      - id: trailing-whitespace
      - id: no-commit-to-branch
        args: [--branch, main]
```

**1.2 Configure Ruff (single source of truth)**

```toml
# Prefer ruff config in backend/pyproject.toml to avoid a second config file.
# If a separate file is needed, keep only one source of truth.
[lint]
select = [
    "E",   # pycodestyle errors
    "W",   # pycodestyle warnings
    "F",   # pyflakes
    "I",   # isort (import sorting)
    "N",   # pep8-naming
    "D",   # pydocstyle (docstrings)
    "UP",  # pyupgrade
    "B",   # flake8-bugbear
    "C4",  # flake8-comprehensions
    "T20", # flake8-print (no print statements)
    "SIM", # flake8-simplify
]

ignore = [
    "D104",  # Missing docstring in public package
    "D107",  # Missing docstring in __init__
]

[lint.pydocstyle]
convention = "google"

[lint.per-file-ignores]
"tests/**/*.py" = ["D"]              # Don't require docstrings in tests
"__init__.py" = ["D104"]             # Don't require package docstrings
"api/alembic/versions/*.py" = ["D"]  # Don't require docstrings in migrations

[format]
quote-style = "double"
indent-style = "space"
line-ending = "auto"
```

**1.3 Create `.prettierrc`**

```json
{
  "useTabs": true,
  "singleQuote": true,
  "trailingComma": "none",
  "printWidth": 100,
  "plugins": ["prettier-plugin-svelte"],
  "overrides": [
    {
      "files": "*.svelte",
      "options": {
        "parser": "svelte"
      }
    }
  ]
}
```
Note: If the existing codebase uses spaces for indentation, switch `useTabs` to `false` before rollout to avoid large formatting churn.

**1.4 Update `frontend/package.json` scripts**

Add formatting scripts:

```json
{
  "scripts": {
    "lint": "eslint 'src/**/*.{ts,js,svelte}'",
    "lint:fix": "eslint 'src/**/*.{ts,js,svelte}' --fix",
    "format": "prettier --write 'src/**/*.{ts,js,svelte,json}'",
    "format:check": "prettier --check 'src/**/*.{ts,js,svelte,json}'"
  }
}
```

**1.5 Installation and Initial Run**

```bash
# Install pre-commit
pip install pre-commit

# Install git hooks
pre-commit install

# Run on all existing files (will reformat code)
pre-commit run --all-files

# Review changes, commit
git add .
git commit -m "chore: add pre-commit hooks for code quality"
```

#### Expected Impact

- Python code automatically formatted on commit (ruff-format)
- Import statements automatically sorted (isort via ruff)
- Type errors caught before commit (mypy)
- Frontend code consistently formatted (Prettier)
- Large files rejected (>1MB)
- Basic hygiene enforced (trailing whitespace, merge conflicts)
- ~30 second delay per commit for checks

#### Success Criteria

- [ ] Pre-commit hooks installed and running
- [ ] All existing code passes checks (after initial formatting)
- [ ] Commits automatically formatted
- [ ] Type errors caught at commit time
- [ ] No disruption to development workflow

---

### Phase 2: Documentation Enforcement (Week 2-3)
**Effort**: 30 minutes | **Priority**: High

#### Objectives
- Enforce docstring coverage (already at 80%+)
- Enforce docstring style (already Google convention)

#### Deliverables

**2.1 Add to `.pre-commit-config.yaml`**

```yaml
  # Python - Docstring coverage
  - repo: https://github.com/econchick/interrogate
    rev: 1.7.0
    hooks:
      - id: interrogate
        args: [--fail-under=80, --verbose, --ignore-init-method, backend/api/]

  # Python - Docstring style
  - repo: https://github.com/pycqa/pydocstyle
    rev: 6.3.0
    hooks:
      - id: pydocstyle
        args: [--convention=google]
        files: ^backend/api/
```

**2.2 Run and verify**

```bash
# Update hooks
pre-commit autoupdate

# Test on all files
pre-commit run --all-files
```

#### Expected Impact

- Missing docstrings caught at commit time
- Incorrect docstring format rejected
- Maintains 80%+ documentation coverage standard
- Adds ~10 seconds to commit time

#### Success Criteria

- [ ] interrogate enforces 80% coverage
- [ ] pydocstyle enforces Google convention
- [ ] Existing code passes (already compliant)

---

### Phase 3: Advanced Checks (Week 3-4, Optional)
**Effort**: 1 hour | **Priority**: Medium

#### Objectives
- Enforce ESLint with stricter settings
- Add custom file size limits
- Detect debugging artifacts

#### Deliverables

**3.1 ESLint Pre-Commit Hook**

```yaml
  # Frontend - ESLint (all files)
  - repo: https://github.com/pre-commit/mirrors-eslint
    rev: v9.17.0
    hooks:
      - id: eslint
        files: ^frontend/src/.*\.(ts|js|svelte)$
        args: [--fix, --max-warnings=0]
        additional_dependencies:
          - eslint@9.39.2
          - eslint-plugin-jsdoc@61.5.0
          - '@typescript-eslint/eslint-plugin@8.50.1'
          - '@typescript-eslint/parser@8.50.1'
```

**3.2 Update `frontend/eslint.config.js`**

Change JSDoc warnings to errors:

```javascript
// Change all 'warn' to 'error' in jsdocRules
const jsdocRules = jsdoc
  ? {
      'jsdoc/check-alignment': 'error',
      'jsdoc/check-param-names': 'error',
      // ... etc
    }
  : {};
```

**3.3 Create `scripts/check_file_sizes.py`**

Use template from `docs/QUALITY_ENFORCEMENT.md` lines 130-234.

```python
#!/usr/bin/env python3
"""Check file size limits according to AGENTS.md standards.

Backend:
- Services: 600 LOC hard (soft limit optional)
- Routers: 500 LOC hard (soft limit optional)

Frontend:
- Components: 600 LOC hard (soft limit optional)
- Stores: 600 LOC hard (soft limit optional)
"""
import sys
from pathlib import Path

LIMITS = {
    'backend/api/services': (0, 600),
    'backend/api/routers': (0, 500),
    'frontend/src/lib/components': (0, 600),
    'frontend/src/lib/stores': (0, 600),
}

def count_lines(file_path: Path) -> int:
    """Count non-empty lines in a file."""
    try:
        with open(file_path) as f:
            return sum(1 for line in f if line.strip())
    except Exception:
        return 0

def check_file_sizes() -> bool:
    """Check all files against size limits.

    Returns:
        True if all files pass, False otherwise.
    """
    violations = []
    warnings = []

    for directory, (soft_limit, hard_limit) in LIMITS.items():
        dir_path = Path(directory)
        if not dir_path.exists():
            continue

        # Check Python files
        for py_file in dir_path.rglob('*.py'):
            if '__pycache__' in str(py_file) or 'test_' in py_file.name:
                continue

            lines = count_lines(py_file)

            if lines > hard_limit:
                violations.append(
                    f"❌ {py_file}: {lines} LOC (hard limit: {hard_limit})"
                )
            elif lines > soft_limit:
                warnings.append(
                    f"⚠️  {py_file}: {lines} LOC (soft limit: {soft_limit})"
                )

        # Check TypeScript/Svelte files
        for file_ext in ['*.ts', '*.svelte']:
            for file in dir_path.rglob(file_ext):
                if 'node_modules' in str(file) or '.test.' in file.name:
                    continue

                lines = count_lines(file)

                if lines > hard_limit:
                    violations.append(
                        f"❌ {file}: {lines} LOC (hard limit: {hard_limit})"
                    )
                elif lines > soft_limit:
                    warnings.append(
                        f"⚠️  {file}: {lines} LOC (soft limit: {soft_limit})"
                    )

    if warnings:
        print("\nFile Size Warnings:")
        for warning in warnings:
            print(warning)

    if violations:
        print("\nFile Size Violations (MUST FIX):")
        for violation in violations:
            print(violation)
        print("\n💡 Tip: See AGENTS.md for file splitting strategies")
        return False

    if not warnings and not violations:
        print("✅ All files within size limits")

    return True

if __name__ == '__main__':
    sys.exit(0 if check_file_sizes() else 1)
```

**3.4 Add to `.pre-commit-config.yaml`**

```yaml
  # Custom - File size limits
  - repo: local
    hooks:
      - id: check-file-size-limits
        name: check-file-size-limits
        entry: python scripts/check_file_sizes.py
        language: system
        pass_filenames: false
```

#### Expected Impact

- JSDoc comments enforced (not just warnings)
- Large files caught before they become problems
- Adds ~15 seconds to commit time

#### Success Criteria

- [ ] ESLint catches all .ts and .svelte files
- [ ] JSDoc violations block commits
- [ ] File size limits enforced

---

## What NOT to Include

### Tests (Run in CI Only)

**Do NOT add to pre-commit:**
```yaml
# ❌ DON'T DO THIS
- id: pytest
- id: vitest
```

**Reasoning:**
- Tests can be slow (especially integration tests)
- Per `docs/TESTING.md`: "Tests don't block commits (only linting/docs do), but they block merge"
- Should run in CI/CD, not at commit time
- Allows for WIP commits with failing tests (local branches only)

### Slow Type Checkers

**Do NOT add:**
```yaml
# ❌ DON'T DO THIS
- id: svelte-check  # Too slow for pre-commit
```

**Reasoning:**
- `svelte-check` can take 30+ seconds on large frontends
- Better run manually or in CI
- mypy is fast enough for pre-commit

### Custom console.log Checker

**Not needed:**
- ESLint already has rules for this (though only on .ts files currently)
- Can be enforced when ESLint coverage is expanded in Phase 3

---

## Installation Guide

### Prerequisites

```bash
# Ensure pre-commit is installed
pip install pre-commit

# Verify installation
pre-commit --version
```

### Step-by-Step Setup

**1. Create configuration files**

```bash
# Copy configs from this plan
# - .pre-commit-config.yaml
# - ruff.toml
# - .prettierrc
```

**2. Install hooks**

```bash
cd /path/to/sideBar
pre-commit install
```

**3. Run on all existing files**

```bash
# This will reformat existing code
pre-commit run --all-files
```

**Expected output:**
```
ruff.....................................................................Passed
ruff-format..............................................................Passed
mypy.....................................................................Passed
prettier.................................................................Passed
check-added-large-files..................................................Passed
check-json...............................................................Passed
check-yaml...............................................................Passed
check-merge-conflict.....................................................Passed
end-of-file-fixer........................................................Passed
trailing-whitespace......................................................Passed
no-commit-to-branch......................................................Passed
```

**4. Review and commit changes**

```bash
# Review formatting changes
git diff

# If acceptable, commit
git add .
git commit -m "chore: add pre-commit hooks and reformat code"
```

---

## Daily Workflow

### Normal Commits

```bash
# Make changes
vim backend/api/services/example.py

# Stage changes
git add backend/api/services/example.py

# Commit (hooks run automatically)
git commit -m "feat: add example feature"

# If hooks fail:
# 1. Review errors
# 2. Fix issues (or let auto-fix handle it)
# 3. Re-stage files: git add .
# 4. Commit again
```

### Bypassing Hooks (Emergency Only)

```bash
# ONLY for emergencies
git commit --no-verify -m "fix: emergency hotfix"

# Must fix issues in next commit immediately
```

**Valid bypass reasons:**
- Emergency production hotfix
- Reverting a broken commit
- Merging auto-generated files

**Invalid bypass reasons:**
- "I'll fix it later"
- "Tests are annoying"
- "Deadline pressure"

### Manual Checks

Run checks without committing:

```bash
# Run all hooks
pre-commit run --all-files

# Run specific hook
pre-commit run ruff --all-files
pre-commit run prettier --all-files

# Backend only
cd backend
ruff check .
mypy api/
interrogate api/ --fail-under=80

# Frontend only
cd frontend
npm run lint
npm run format:check
npm run check
```

---

## Maintenance

### Updating Hook Versions

```bash
# Auto-update to latest versions
pre-commit autoupdate

# Review changes
git diff .pre-commit-config.yaml

# Test
pre-commit run --all-files

# Commit updates
git commit .pre-commit-config.yaml -m "chore: update pre-commit hook versions"
```

**Frequency**: Every 2-3 months

### Clearing Cache

If hooks fail on unchanged files:

```bash
pre-commit clean
pre-commit run --all-files
```

### Troubleshooting

**Hooks not running:**
```bash
pre-commit uninstall
pre-commit install
ls -la .git/hooks/pre-commit  # Verify hook exists
```

**Slow performance:**
```bash
# Run with timing
pre-commit run --all-files --verbose

# Identify slow hooks, consider removing from pre-commit
# and running them in CI instead
```

---

## Future Enhancements

### Phase 4: iOS Swift Linting (Post iOS Development Start)

When iOS development begins, add:

```yaml
  # Swift - SwiftLint
  - repo: https://github.com/realm/SwiftLint
    rev: 0.55.1
    hooks:
      - id: swiftlint
        files: \.swift$
        args: [--strict]
```

Create `ios/.swiftlint.yml`:
```yaml
included:
  - sideBar
excluded:
  - Pods
  - DerivedData
disabled_rules:
  - line_length  # Let Xcode handle
opt_in_rules:
  - empty_count
  - missing_docs
```

### Phase 5: CI/CD Integration

Translate pre-commit config to GitHub Actions:

```yaml
# .github/workflows/quality.yml
name: Code Quality
on: [push, pull_request]

jobs:
  pre-commit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
      - uses: pre-commit/action@v3.0.0

  tests-backend:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run tests
        run: |
          cd backend
          pytest --cov=api --cov-fail-under=90

  tests-frontend:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run tests
        run: |
          cd frontend
          npm run coverage
```

---

## Expected Timeline

| Phase | Duration | Effort | Can Start |
|-------|----------|--------|-----------|
| Phase 1: Essential | 1-2 hours | 1 session | Immediately |
| Phase 2: Docs | 30 min | 1 session | After 1 week with Phase 1 |
| Phase 3: Advanced | 1 hour | 1 session | After 1 week with Phase 2 |
| **Total** | **3-4 hours** | **3 sessions** | **2-3 weeks** |

**Recommended pace:**
- Week 1: Phase 1 (essential automation)
- Week 2: Use Phase 1, add Phase 2 when comfortable
- Week 3-4: Add Phase 3 if desired (optional)

---

## Success Metrics

**Definition of Done:**
- [ ] Pre-commit hooks installed and running
- [ ] All commits automatically formatted
- [ ] Type errors caught at commit time
- [ ] Docstrings enforced at 80%+ coverage
- [ ] Frontend code consistently formatted
- [ ] No large files or merge conflicts committed
- [ ] Workflow feels natural (not intrusive)
- [ ] Documentation updated in QUALITY_ENFORCEMENT.md

**Quality Improvements:**
- Zero commits with formatting inconsistencies
- Zero commits with type errors
- Zero commits with missing docstrings
- Consistent code style across all platforms
- Reduced time spent on code review for style issues

---

## Risks & Mitigations

### Risk 1: Initial Formatting Disruption
**Risk**: First run will reformat entire codebase
**Mitigation**:
- Run on separate branch first
- Review changes before merging
- Code already follows standards (minimal changes expected)

### Risk 2: Commit Time Delay
**Risk**: Pre-commit adds 30-60 seconds per commit
**Mitigation**:
- Only add fast checks to pre-commit
- Move slow checks (tests, svelte-check) to CI
- Can bypass with --no-verify in emergencies

### Risk 3: False Positives
**Risk**: Hooks might flag valid code
**Mitigation**:
- Proper exclusions in config (tests, migrations, generated files)
- Can disable specific rules with inline comments
- Regular review and tuning of rules

### Risk 4: Developer Frustration
**Risk**: Hooks might feel like obstacles
**Mitigation**:
- Start with Phase 1 only (minimal checks)
- Add phases gradually
- Document bypass procedures for emergencies
- Ensure auto-fix works for most issues

---

## Alignment with Existing Documentation

This plan implements the templates and standards already documented in:

- **docs/QUALITY_ENFORCEMENT.md**: Pre-commit config templates (activated here)
- **docs/AGENTS.md**: File size limits, code quality standards
- **docs/TESTING.md**: Testing philosophy (tests in CI, not pre-commit)
- **docs/GOOGLE_DOCSTRING_STYLE_GUIDE.md**: Google-style docstrings (enforced by pydocstyle)

**Key principle**: This plan doesn't introduce new standards, it automates enforcement of existing ones.

---

## Conclusion

Pre-commit hooks are highly recommended for sideBar given:
- Multi-platform development (Python, TypeScript, Swift)
- Solo development with frequent context switching
- Excellent existing documentation and configuration
- Upcoming iOS development requiring sustained focus elsewhere

The phased approach minimizes disruption while maximizing benefit. Phase 1 provides immediate value with minimal overhead. Phases 2-3 can be added as comfort level increases.

**Recommended action**: Implement Phase 1 immediately, before starting iOS development.
