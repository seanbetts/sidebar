"""Regression tests for Apple testing taxonomy documentation."""

from __future__ import annotations

from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
ROOT_AGENTS_PATH = REPO_ROOT / "AGENTS.md"
TESTS_AGENTS_PATH = REPO_ROOT / "tests" / "AGENTS.md"
ENGINEERING_TESTING_PATH = REPO_ROOT / "docs" / "engineering" / "TESTING.md"
IOS_TESTING_PATH = REPO_ROOT / "ios" / "sideBar" / "TESTING.md"


def _read(path: Path) -> str:
    """Return the text content for a required documentation file."""
    assert path.exists(), f"Missing required documentation file: {path}"
    return path.read_text()


def test_apple_testing_docs_define_taxonomy_and_branch_policy() -> None:
    """The repo should document the Apple taxonomy and branch behavior."""
    root_agents = _read(ROOT_AGENTS_PATH)
    tests_agents = _read(TESTS_AGENTS_PATH)
    engineering_testing = _read(ENGINEERING_TESTING_PATH)
    ios_testing = _read(IOS_TESTING_PATH)

    combined = "\n".join([root_agents, tests_agents, engineering_testing, ios_testing])

    for required_phrase in [
        "Apple test taxonomy",
        "Logic",
        "Surface",
        "UI Smoke",
        "dev",
        "main",
        "lowest appropriate Apple test layer",
    ]:
        assert required_phrase in combined


def test_repo_local_agent_docs_define_apple_tdd_layer_selection() -> None:
    """Repo-local agent docs should guide Apple TDD without editing third-party skills."""
    root_agents = _read(ROOT_AGENTS_PATH)
    tests_agents = _read(TESTS_AGENTS_PATH)
    combined = "\n".join([root_agents, tests_agents])

    for required_phrase in [
        "default new Apple tests to `logic`",
        "choose `surface` only when the logic layer cannot prove the behavior",
        "choose `ui_smoke` only for true end-to-end coverage",
        "layer repo-local Apple testing rules on top of third-party skills",
    ]:
        assert required_phrase in combined
