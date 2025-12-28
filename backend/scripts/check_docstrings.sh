#!/bin/bash
# Check docstring coverage and style

set -e

cd "$(dirname "$0")/.."

echo "========================================="
echo "Checking Docstring Coverage and Style"
echo "========================================="
echo ""

# Check if tools are installed
if ! command -v interrogate &> /dev/null; then
    echo "❌ interrogate not installed"
    echo "   Run: pip install interrogate"
    exit 1
fi

if ! command -v pydocstyle &> /dev/null; then
    echo "❌ pydocstyle not installed"
    echo "   Run: pip install pydocstyle"
    exit 1
fi

# Run interrogate
echo "📊 Checking docstring coverage..."
echo "-----------------------------------------"
interrogate -v api/ || true
echo ""

# Run pydocstyle
echo "✅ Checking docstring style (Google)..."
echo "-----------------------------------------"
pydocstyle api/ || true
echo ""

# Summary
echo "========================================="
echo "Done! Review output above for issues."
echo "========================================="
echo ""
echo "To fix issues:"
echo "  1. See: docs/GOOGLE_DOCSTRING_STYLE_GUIDE.md"
echo "  2. Use VS Code autoDocstring extension"
echo "  3. Run: pydocstyle api/path/to/file.py"
