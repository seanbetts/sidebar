#!/usr/bin/env python3
"""Helper script to scan skill Python scripts and add missing dependencies to pyproject.toml.

Usage:
    python scripts/add_skill_dependencies.py <skill-name>
    python scripts/add_skill_dependencies.py skills/my-skill

Examples:
    python scripts/add_skill_dependencies.py pdf
    python scripts/add_skill_dependencies.py skills/docx
    python scripts/add_skill_dependencies.py my-new-skill --auto
"""

import ast
import sys
import tomllib
from pathlib import Path


def get_imports_from_file(file_path: Path) -> set[str]:
    """Extract top-level package names from imports in a Python file."""
    try:
        with open(file_path, encoding="utf-8") as f:
            tree = ast.parse(f.read(), filename=str(file_path))
    except (SyntaxError, UnicodeDecodeError) as e:
        print(f"⚠️  Warning: Could not parse {file_path}: {e}")
        return set()

    imports = set()

    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                # Get top-level package (e.g., 'requests' from 'requests.api')
                top_level = alias.name.split(".")[0]
                imports.add(top_level)
        elif isinstance(node, ast.ImportFrom):
            if node.module:
                # Get top-level package (e.g., 'PIL' from 'PIL.Image')
                top_level = node.module.split(".")[0]
                imports.add(top_level)

    return imports


def get_skill_directory(skill_arg: str) -> Path:
    """Convert skill name or path to skill directory Path."""
    skill_path = Path(skill_arg)

    # If it's already a path to skills/<name>, use it
    if skill_path.is_dir() and (skill_path / "SKILL.md").exists():
        return skill_path

    # If it's just a name, look in skills/
    skills_dir = Path("skills") / skill_arg
    if skills_dir.is_dir() and (skills_dir / "SKILL.md").exists():
        return skills_dir

    # Try as absolute path
    if skill_path.is_absolute() and skill_path.is_dir():
        return skill_path

    raise ValueError(f"Could not find skill directory for: {skill_arg}")


def scan_skill_scripts(skill_dir: Path) -> set[str]:
    """Scan all Python scripts in a skill and return imported packages."""
    scripts_dir = skill_dir / "scripts"

    if not scripts_dir.exists():
        print(f"ℹ️  No scripts directory found in {skill_dir}")
        return set()

    all_imports = set()
    python_files = list(scripts_dir.rglob("*.py"))

    if not python_files:
        print(f"ℹ️  No Python files found in {scripts_dir}")
        return set()

    print(f"\n📂 Scanning {len(python_files)} Python file(s) in {scripts_dir}...")

    for py_file in python_files:
        imports = get_imports_from_file(py_file)
        if imports:
            print(f"   {py_file.name}: {', '.join(sorted(imports))}")
            all_imports.update(imports)

    return all_imports


def filter_stdlib_and_local(imports: set[str]) -> set[str]:
    """Filter out standard library modules and local imports."""
    # Python 3.10+ has sys.stdlib_module_names
    stdlib_modules = sys.stdlib_module_names

    # Also filter out local packages (relative imports or known local modules)
    local_modules = {"ooxml", "skills", "scripts", "references", "assets"}

    external = set()
    for imp in imports:
        if imp not in stdlib_modules and imp not in local_modules:
            external.add(imp)

    return external


def get_current_dependencies() -> set[str]:
    """Read current dependencies from pyproject.toml."""
    pyproject_path = Path("pyproject.toml")

    if not pyproject_path.exists():
        print("❌ pyproject.toml not found")
        sys.exit(1)

    with open(pyproject_path, "rb") as f:
        data = tomllib.load(f)

    dependencies = data.get("project", {}).get("dependencies", [])

    # Extract package names (everything before >=, ==, etc.)
    current = set()
    for dep in dependencies:
        # Handle both "package>=1.0" and "package @ git+..." formats
        pkg_name = dep.split(">=")[0].split("==")[0].split("[")[0].split("@")[0].strip()
        current.add(pkg_name.lower())

    return current


def normalize_package_name(name: str) -> str:
    """Normalize package name for PyPI (handle special cases)."""
    # Map import names to PyPI package names
    name_map = {
        "PIL": "Pillow",
        "cv2": "opencv-python",
        "sklearn": "scikit-learn",
        "yaml": "PyYAML",
        # Add more mappings as needed
    }

    return name_map.get(name, name)


def add_dependencies_to_pyproject(packages: set[str], auto_confirm: bool = False):
    """Add missing packages to pyproject.toml dependencies."""
    if not packages:
        print("\n✅ No new dependencies to add!")
        return

    print(f"\n📦 New dependencies to add: {', '.join(sorted(packages))}")

    if not auto_confirm:
        response = input("\n❓ Add these dependencies to pyproject.toml? (y/n): ")
        if response.lower() != "y":
            print("❌ Cancelled")
            return

    pyproject_path = Path("pyproject.toml")
    content = pyproject_path.read_text()

    # Find the dependencies list
    lines = content.split("\n")

    # Find where to insert new dependencies (before the closing bracket)
    insert_index = None
    for i, line in enumerate(lines):
        if "dependencies = [" in line:
            # Find the closing bracket
            for j in range(i + 1, len(lines)):
                if lines[j].strip() == "]":
                    insert_index = j
                    break
            break

    if insert_index is None:
        print("❌ Could not find dependencies list in pyproject.toml")
        return

    # Add new dependencies with comments
    new_lines = []
    for pkg in sorted(packages):
        normalized = normalize_package_name(pkg)
        new_lines.append(f'    "{normalized}",  # Added by add_skill_dependencies.py')

    # Insert new lines before the closing bracket
    lines[insert_index:insert_index] = new_lines

    # Write back
    pyproject_path.write_text("\n".join(lines))

    print(f"\n✅ Added {len(packages)} new dependencies to pyproject.toml")
    print("\n⚠️  Next steps:")
    print("   1. Review the changes in pyproject.toml")
    print("   2. Rebuild Docker: docker compose build")
    print("   3. Test: docker compose up -d")


def main():
    if len(sys.argv) < 2:
        print("Usage: python scripts/add_skill_dependencies.py <skill-name> [--auto]")
        print("\nExamples:")
        print("  python scripts/add_skill_dependencies.py pdf")
        print("  python scripts/add_skill_dependencies.py skills/my-skill")
        print("  python scripts/add_skill_dependencies.py docx --auto")
        sys.exit(1)

    skill_arg = sys.argv[1]
    auto_confirm = "--auto" in sys.argv

    try:
        skill_dir = get_skill_directory(skill_arg)
    except ValueError as e:
        print(f"❌ Error: {e}")
        sys.exit(1)

    print(f"\n🔍 Analyzing skill: {skill_dir.name}")

    # Step 1: Scan scripts for imports
    all_imports = scan_skill_scripts(skill_dir)

    if not all_imports:
        print("\n✅ No imports found or no scripts to analyze")
        return

    # Step 2: Filter out stdlib and local modules
    external_packages = filter_stdlib_and_local(all_imports)

    if not external_packages:
        print("\n✅ No external packages detected (only standard library imports)")
        return

    print(f"\n🔎 External packages detected: {', '.join(sorted(external_packages))}")

    # Step 3: Check what's already in pyproject.toml
    current_deps = get_current_dependencies()
    print(
        f"📋 Current dependencies: {', '.join(sorted(current_deps)) if current_deps else 'none'}"
    )

    # Step 4: Find what's missing
    missing = set()
    for pkg in external_packages:
        normalized = normalize_package_name(pkg).lower()
        if normalized not in current_deps:
            missing.add(pkg)

    if not missing:
        print("\n✅ All detected packages are already in pyproject.toml!")
        return

    # Step 5: Add missing dependencies
    add_dependencies_to_pyproject(missing, auto_confirm)


if __name__ == "__main__":
    main()
