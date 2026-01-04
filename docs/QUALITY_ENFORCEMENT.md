# Quality Enforcement Setup

**For humans setting up the development environment. AI agents see AGENTS.md instead.**

This document explains how to set up automated enforcement of code quality standards.

---

## Overview

This document explains how to set up automated enforcement of code quality standards, including:
- Pre-commit hooks (block commits that don't meet standards)
- CI/CD checks (verify on every push)
- IDE integration (catch issues early)

---

## Pre-Commit Hooks

### Installation

```bash
# Install pre-commit framework
pip install pre-commit

# Install hooks
pre-commit install
```

### Configuration

Create `.pre-commit-config.yaml` in project root:

```yaml
# .pre-commit-config.yaml
repos:
  # Python - Ruff (linting + formatting)
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.1.9
    hooks:
      - id: ruff
        args: [--fix, --exit-non-zero-on-fix]
      - id: ruff-format

  # Python - Type checking
  - repo: https://github.com/pre-commit/mirrors-mypy
    rev: v1.8.0
    hooks:
      - id: mypy
        additional_dependencies: [types-all]
        args: [--strict, --ignore-missing-imports]
        files: ^backend/

  # Python - Docstring coverage
  - repo: https://github.com/econchick/interrogate
    rev: 1.5.0
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

  # TypeScript/JavaScript - ESLint
  - repo: https://github.com/pre-commit/mirrors-eslint
    rev: v8.56.0
    hooks:
      - id: eslint
        files: \.(ts|tsx|js|jsx|svelte)$
        types: [file]
        args: [--fix, --max-warnings=0]
        additional_dependencies:
          - eslint@9.39.2
          - eslint-plugin-jsdoc@61.5.0
          - '@typescript-eslint/eslint-plugin@8.50.1'
          - '@typescript-eslint/parser@8.50.1'

  # TypeScript - Type checking
  - repo: local
    hooks:
      - id: svelte-check
        name: svelte-check
        entry: npm run check
        language: system
        files: \.(ts|svelte)$
        pass_filenames: false

  # General - Remove debugging artifacts
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.5.0
    hooks:
      - id: check-added-large-files
        args: [--maxkb=1000]
      - id: check-json
      - id: check-yaml
      - id: check-merge-conflict
      - id: end-of-file-fixer
      - id: trailing-whitespace
      - id: debug-statements  # Catches print(), pdb, debugger
      - id: no-commit-to-branch
        args: [--branch, main, --branch, master]

  # Custom - Check for console.log
  - repo: local
    hooks:
      - id: check-console-log
        name: check-console-log
        entry: bash -c 'if grep -r "console\\.log" frontend/src --exclude-dir=node_modules; then echo "❌ Found console.log statements"; exit 1; fi'
        language: system
        pass_filenames: false
        files: \.(ts|js|svelte)$

  # Custom - Check file size limits
  - repo: local
    hooks:
      - id: check-file-size-limits
        name: check-file-size-limits
        entry: python scripts/check_file_sizes.py
        language: system
        pass_filenames: false
```

### Scripts

Create `scripts/check_file_sizes.py`:

```python
#!/usr/bin/env python3
"""Check file size limits according to AGENTS.md standards.

Backend:
- Services: 400 LOC soft, 600 LOC hard
- Routers: 350 LOC soft, 500 LOC hard
- Utilities: 200 LOC soft, 300 LOC hard

Frontend:
- Components: 400 LOC soft, 600 LOC hard
- Stores: 400 LOC soft, 600 LOC hard
- Utilities: 200 LOC soft, 300 LOC hard
"""
import sys
from pathlib import Path

# Limits: (soft, hard)
LIMITS = {
    'backend/api/services': (400, 600),
    'backend/api/routers': (350, 500),
    'backend/api/utils': (200, 300),
    'frontend/src/lib/components': (400, 600),
    'frontend/src/lib/stores': (400, 600),
    'frontend/src/lib/utils': (200, 300),
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
                    f"⚠️  {py_file}: {lines} LOC (soft limit: {soft_limit}, approaching hard limit: {hard_limit})"
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
                        f"⚠️  {file}: {lines} LOC (soft limit: {soft_limit}, approaching hard limit: {hard_limit})"
                    )

    # Print results
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

Make it executable:
```bash
chmod +x scripts/check_file_sizes.py
```

---

## Backend Enforcement (Python)

### Ruff Configuration

Create `ruff.toml`:

```toml
# ruff.toml
[lint]
select = [
    "E",   # pycodestyle errors
    "W",   # pycodestyle warnings
    "F",   # pyflakes
    "I",   # isort
    "N",   # pep8-naming
    "D",   # pydocstyle
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
"tests/**/*.py" = ["D"]  # Don't require docstrings in tests
"__init__.py" = ["D104"]  # Don't require docstrings in __init__

[format]
quote-style = "double"
indent-style = "space"
line-ending = "auto"
```

### pytest Configuration

Already in `backend/pyproject.toml`:

```toml
[tool.pytest.ini_options]
testpaths = ["tests"]
python_files = ["test_*.py"]
python_classes = ["Test*"]
python_functions = ["test_*"]
addopts = [
    "-v",
    "--strict-markers",
    "--tb=short",
    "--cov=api",
    "--cov-report=term-missing",
    "--cov-fail-under=90"  # ENFORCE 90%+ coverage
]
```

### interrogate Configuration

Already in `backend/pyproject.toml`:

```toml
[tool.interrogate]
ignore-init-method = true
ignore-init-module = false
ignore-magic = true
ignore-module = false
ignore-nested-functions = false
ignore-nested-classes = true
ignore-private = true
fail-under = 80  # ENFORCE 80%+ docstring coverage
exclude = ["setup.py", "docs", "tests", "alembic"]
verbose = 2
color = true
```

### mypy Configuration

Create `backend/mypy.ini`:

```ini
# mypy.ini
[mypy]
python_version = 3.11
warn_return_any = True
warn_unused_configs = True
disallow_untyped_defs = True
disallow_any_unimported = False
no_implicit_optional = True
warn_redundant_casts = True
warn_unused_ignores = True
warn_no_return = True
check_untyped_defs = True
strict_equality = True

[mypy-tests.*]
disallow_untyped_defs = False
```

---

## Frontend Enforcement (TypeScript)

### ESLint Configuration

Create `frontend/.eslintrc.cjs`:

```javascript
// .eslintrc.cjs
module.exports = {
  root: true,
  parser: '@typescript-eslint/parser',
  extends: [
    'eslint:recommended',
    'plugin:@typescript-eslint/recommended',
    'plugin:jsdoc/recommended'
  ],
  plugins: [
    '@typescript-eslint',
    'jsdoc'
  ],
  parserOptions: {
    sourceType: 'module',
    ecmaVersion: 2020,
    extraFileExtensions: ['.svelte']
  },
  env: {
    browser: true,
    es2017: true,
    node: true
  },
  rules: {
    // JSDoc enforcement
    'jsdoc/require-jsdoc': ['error', {
      require: {
        FunctionDeclaration: true,
        MethodDefinition: true,
        ClassDeclaration: true,
        ArrowFunctionExpression: false,
        FunctionExpression: false
      },
      publicOnly: true
    }],
    'jsdoc/require-param': 'error',
    'jsdoc/require-param-type': 'error',
    'jsdoc/require-returns': 'error',
    'jsdoc/require-returns-type': 'error',
    'jsdoc/require-description': 'error',
    'jsdoc/require-example': ['warn', {
      exemptedBy: ['private', 'internal']
    }],

    // Code quality
    'no-console': ['error', { allow: ['warn', 'error'] }],
    'no-debugger': 'error',
    '@typescript-eslint/no-unused-vars': ['error', {
      argsIgnorePattern: '^_'
    }],
    '@typescript-eslint/explicit-function-return-type': ['error', {
      allowExpressions: true
    }],

    // Prefer const
    'prefer-const': 'error',

    // No var
    'no-var': 'error'
  },
  overrides: [
    {
      files: ['*.svelte'],
      parser: 'svelte-eslint-parser',
      parserOptions: {
        parser: '@typescript-eslint/parser'
      }
    },
    {
      files: ['*.test.ts', '*.spec.ts'],
      rules: {
        'jsdoc/require-jsdoc': 'off'
      }
    }
  ]
};
```

### TypeScript Configuration

Update `frontend/tsconfig.json`:

```json
{
  "extends": "./.svelte-kit/tsconfig.json",
  "compilerOptions": {
    "strict": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "noImplicitReturns": true,
    "noFallthroughCasesInSwitch": true,
    "noUncheckedIndexedAccess": true,
    "exactOptionalPropertyTypes": true,
    "forceConsistentCasingInFileNames": true
  }
}
```

### Vitest Configuration

Update `frontend/vitest.config.ts`:

```typescript
import { defineConfig } from 'vitest/config';
import { svelte } from '@sveltejs/vite-plugin-svelte';

export default defineConfig({
  plugins: [svelte()],
  test: {
    globals: true,
    environment: 'jsdom',
    coverage: {
      provider: 'v8',
      reporter: ['text', 'json', 'html'],
      exclude: [
        'node_modules/',
        'src/tests/',
        '**/*.d.ts',
        '**/*.config.*',
        '**/mockData',
        'src/routes/**'
      ],
      // ENFORCE coverage thresholds
      thresholds: {
        lines: 70,
        functions: 70,
        branches: 65,
        statements: 70
      },
      // Don't fail builds on threshold
      // (warnings only per requirements)
      all: true
    },
    // Fail tests that take too long
    testTimeout: 10000
  }
});
```

---

## CI/CD Integration

### GitHub Actions

Create `.github/workflows/quality-checks.yml`:

```yaml
name: Quality Checks

on:
  push:
    branches: [dev, main]
  pull_request:
    branches: [dev, main]

jobs:
  backend-quality:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.11'

      - name: Install dependencies
        run: |
          cd backend
          pip install -r requirements.txt
          pip install ruff mypy interrogate pydocstyle

      - name: Run Ruff (lint + format check)
        run: |
          cd backend
          ruff check .
          ruff format --check .

      - name: Run mypy (type check)
        run: |
          cd backend
          mypy api/

      - name: Run interrogate (docstring coverage)
        run: |
          cd backend
          interrogate api/ --fail-under=80 --verbose

      - name: Run pydocstyle (docstring style)
        run: |
          cd backend
          pydocstyle api/ --convention=google

      - name: Run tests with coverage
        run: |
          cd backend
          pytest --cov=api --cov-report=xml --cov-fail-under=90

      - name: Upload coverage to Codecov
        uses: codecov/codecov-action@v3
        with:
          file: ./backend/coverage.xml

  frontend-quality:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up Node
        uses: actions/setup-node@v4
        with:
          node-version: '20'

      - name: Install dependencies
        run: |
          cd frontend
          npm ci

      - name: Run ESLint
        run: |
          cd frontend
          npm run lint

      - name: Run TypeScript check
        run: |
          cd frontend
          npm run check

      - name: Run tests with coverage
        run: |
          cd frontend
          npm run coverage

      - name: Upload coverage to Codecov
        uses: codecov/codecov-action@v3
        with:
          file: ./frontend/coverage/coverage-final.json

  file-size-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.11'

      - name: Check file size limits
        run: python scripts/check_file_sizes.py
```

---

## IDE Integration

### VS Code

Create `.vscode/settings.json`:

```json
{
  // Python
  "python.linting.enabled": true,
  "python.linting.ruffEnabled": true,
  "python.linting.mypyEnabled": true,
  "python.formatting.provider": "none",
  "[python]": {
    "editor.defaultFormatter": "charliermarsh.ruff",
    "editor.formatOnSave": true,
    "editor.codeActionsOnSave": {
      "source.organizeImports": true
    }
  },

  // TypeScript/JavaScript
  "eslint.validate": ["javascript", "typescript", "svelte"],
  "editor.codeActionsOnSave": {
    "source.fixAll.eslint": true
  },
  "[typescript]": {
    "editor.defaultFormatter": "esbenp.prettier-vscode",
    "editor.formatOnSave": true
  },
  "[svelte]": {
    "editor.defaultFormatter": "svelte.svelte-vscode",
    "editor.formatOnSave": true
  },

  // General
  "files.trimTrailingWhitespace": true,
  "files.insertFinalNewline": true,
  "editor.rulers": [100],

  // Test coverage
  "coverage-gutters.showLineCoverage": true,
  "coverage-gutters.showRulerCoverage": true
}
```

Create `.vscode/extensions.json`:

```json
{
  "recommendations": [
    "charliermarsh.ruff",
    "ms-python.python",
    "ms-python.vscode-pylance",
    "dbaeumer.vscode-eslint",
    "svelte.svelte-vscode",
    "esbenp.prettier-vscode",
    "ryanluker.vscode-coverage-gutters"
  ]
}
```

---

## Setup Instructions

### Initial Setup

```bash
# 1. Install pre-commit
pip install pre-commit

# 2. Install hooks
pre-commit install

# 3. Make scripts executable
chmod +x scripts/check_file_sizes.py

# 4. Run hooks on all files (first time)
pre-commit run --all-files

# 5. Install VS Code extensions (if using VS Code)
# Extensions will be recommended automatically
```

### Daily Workflow

**Pre-commit hooks will automatically run on `git commit`:**

```bash
# Make changes
# ...

# Stage changes
git add .

# Commit (hooks run automatically)
git commit -m "feat: add task filtering"

# If hooks fail:
# - Fix issues
# - Stage fixes
# - Commit again
```

### Manual Checks

**Run checks without committing:**

```bash
# Backend
cd backend
ruff check .
mypy api/
interrogate api/ --fail-under=80
pytest --cov=api --cov-report=term-missing

# Frontend
cd frontend
npm run lint
npm run check
npm run coverage

# File sizes
python scripts/check_file_sizes.py
```

---

## Bypassing Hooks (Emergency Only)

**NEVER bypass hooks unless absolutely necessary:**

```bash
# Skip hooks (ONLY in emergency)
git commit --no-verify -m "fix: emergency hotfix"

# You must fix the issues in a follow-up commit immediately
```

**Valid reasons to skip:**
- Emergency production hotfix
- Reverting a broken commit
- Merging auto-generated files

**Invalid reasons:**
- "I'll fix it later"
- "Tests are annoying"
- "Deadline pressure"

---

## Troubleshooting

### Pre-commit hooks not running

```bash
# Reinstall hooks
pre-commit uninstall
pre-commit install

# Verify installation
ls -la .git/hooks/pre-commit
```

### Hooks failing on unchanged files

```bash
# Clear pre-commit cache
pre-commit clean

# Update hook versions
pre-commit autoupdate

# Run again
pre-commit run --all-files
```

### Coverage below threshold

```bash
# Generate coverage report
pytest --cov=api --cov-report=html

# Open in browser
open htmlcov/index.html

# Add tests for uncovered lines
```

### Docstring coverage below threshold

```bash
# Find files missing docstrings
interrogate api/ --verbose

# Add Google-style docstrings to flagged files
```

---

## Summary

**Enforcement Levels:**

| Check | Pre-commit | CI/CD | Blocks Commit |
|-------|-----------|-------|---------------|
| Ruff (lint/format) | ✅ | ✅ | ✅ Yes |
| mypy (type check) | ✅ | ✅ | ✅ Yes |
| interrogate (docstrings) | ✅ | ✅ | ✅ Yes |
| pytest (tests) | ❌ | ✅ | ❌ No (CI only) |
| ESLint | ✅ | ✅ | ✅ Yes |
| Svelte check | ✅ | ✅ | ✅ Yes |
| Vitest (tests) | ❌ | ✅ | ❌ No (CI only) |
| File size limits | ✅ | ✅ | ✅ Yes |
| No console.log | ✅ | ✅ | ✅ Yes |
| No debugger | ✅ | ✅ | ✅ Yes |

**Quality Standards Enforced:**
- ✅ Code formatting (Ruff, ESLint)
- ✅ Type safety (mypy, TypeScript)
- ✅ Documentation (interrogate, JSDoc)
- ✅ File size limits (custom script)
- ✅ No debugging artifacts
- ✅ Test coverage (CI only, warnings in dev)

---

**For more details on code quality standards, see [AGENTS.md](../AGENTS.md)**
