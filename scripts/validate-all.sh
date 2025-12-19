#!/bin/bash
set -euo pipefail

# validate-all.sh - Validate all skills in the repository
# Returns exit code 0 if all valid, 1 if any invalid

echo "Validating all skills..."
echo ""

FAILURES=0
SUCCESSES=0
SKILLS_DIR="skills"

# Check if skills directory exists
if [[ ! -d "$SKILLS_DIR" ]]; then
    echo "Error: $SKILLS_DIR directory not found"
    exit 1
fi

# Check if any skills exist
if [[ -z "$(ls -A "$SKILLS_DIR" 2>/dev/null)" ]]; then
    echo "No skills found in $SKILLS_DIR/"
    exit 0
fi

# Validate each skill
for SKILL_DIR in "$SKILLS_DIR"/*/ ; do
    if [[ ! -d "$SKILL_DIR" ]]; then
        continue
    fi

    SKILL_NAME=$(basename "$SKILL_DIR")

    # Skip if no SKILL.md exists
    if [[ ! -f "$SKILL_DIR/SKILL.md" ]]; then
        echo "⊘ SKIP: $SKILL_NAME (no SKILL.md found)"
        continue
    fi

    echo -n "Validating $SKILL_NAME... "

    if .venv/bin/skills-ref validate "$SKILL_DIR" > /dev/null 2>&1; then
        echo "✓ PASS"
        ((SUCCESSES++))
    else
        echo "✗ FAIL"
        echo "  Error details:"
        .venv/bin/skills-ref validate "$SKILL_DIR" 2>&1 | sed 's/^/    /'
        ((FAILURES++))
    fi
done

echo ""
echo "Results: $SUCCESSES passed, $FAILURES failed"

if [[ $FAILURES -gt 0 ]]; then
    exit 1
fi

echo "✓ All skills valid!"
