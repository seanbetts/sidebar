"""Tests for docs indexer frontmatter parsing."""

from pathlib import Path
from unittest.mock import patch

import pytest

from api.services.knowledge.docs_indexer import DocsIndexer
from api.services.knowledge.provider import get_docs_indexer, init_docs_indexer


@pytest.fixture()
def sample_docs(tmp_path: Path) -> Path:
    """Create a minimal docs directory with two markdown files."""
    manual = tmp_path / "manual"
    manual.mkdir()
    (manual / "introduction.md").write_text(
        "---\n"
        "title: Introduction\n"
        "summary: What sideBar is and how it works.\n"
        "tags: [manual, overview]\n"
        "audience: user\n"
        "surfaces: [app, website, internal-knowledge]\n"
        "---\n\n"
        "## What's in the App\n\n"
        "sideBar has notes, tasks, and more.\n\n"
        "## Where to Start\n\n"
        "Head to Getting Started.\n"
    )
    skills = tmp_path / "skills"
    skills.mkdir()
    (skills / "web-search.md").write_text(
        "---\n"
        "title: Web Search\n"
        "summary: Search the live web for current information.\n"
        "tags: [skills, web, search]\n"
        "audience: user\n"
        "surfaces: [app, website, internal-knowledge]\n"
        "skill_id: web-search\n"
        "---\n\n"
        "## What it does\n\n"
        "The Web Search skill searches the web.\n"
    )
    # A doc not surfaced to internal-knowledge should be excluded from the brief.
    (manual / "internal-only.md").write_text(
        "---\n"
        "title: Internal Only\n"
        "summary: Not for the assistant.\n"
        "tags: [internal]\n"
        "audience: engineer\n"
        "surfaces: [app]\n"
        "---\n\n"
        "Engineering details.\n"
    )
    return tmp_path


class TestDocsIndexer:
    """Tests for DocsIndexer."""

    def test_index_parses_frontmatter(self, sample_docs: Path) -> None:
        indexer = DocsIndexer(sample_docs)
        indexer.build()
        catalog = indexer.catalog

        assert len(catalog) == 3
        intro = next(d for d in catalog if d["title"] == "Introduction")
        assert intro["summary"] == "What sideBar is and how it works."
        assert intro["tags"] == ["manual", "overview"]
        assert intro["audience"] == "user"
        assert intro["surfaces"] == ["app", "website", "internal-knowledge"]
        assert intro["skill_id"] is None
        assert "What's in the App" in intro["headings"]
        assert "Where to Start" in intro["headings"]

    def test_index_captures_skill_id(self, sample_docs: Path) -> None:
        indexer = DocsIndexer(sample_docs)
        indexer.build()
        catalog = indexer.catalog

        ws = next(d for d in catalog if d["title"] == "Web Search")
        assert ws["skill_id"] == "web-search"

    def test_index_extracts_sections(self, sample_docs: Path) -> None:
        indexer = DocsIndexer(sample_docs)
        indexer.build()
        catalog = indexer.catalog

        ws = next(d for d in catalog if d["title"] == "Web Search")
        assert len(ws["sections"]) >= 1
        assert ws["sections"][0]["heading"] == "What it does"
        assert "searches the web" in ws["sections"][0]["content"]

    def test_brief_includes_internal_knowledge_docs(self, sample_docs: Path) -> None:
        indexer = DocsIndexer(sample_docs)
        indexer.build()
        brief = indexer.product_knowledge_brief

        assert "Introduction" in brief
        assert "What sideBar is and how it works." in brief
        assert "Web Search" in brief
        assert "Search the live web" in brief

    def test_brief_excludes_non_internal_knowledge_docs(
        self, sample_docs: Path,
    ) -> None:
        indexer = DocsIndexer(sample_docs)
        indexer.build()
        brief = indexer.product_knowledge_brief

        assert "Internal Only" not in brief
        assert "Not for the assistant" not in brief

    def test_brief_groups_by_section(self, sample_docs: Path) -> None:
        indexer = DocsIndexer(sample_docs)
        indexer.build()
        brief = indexer.product_knowledge_brief

        assert "Manual" in brief or "manual" in brief.lower()
        assert "Skills" in brief or "skills" in brief.lower()

    def test_search_matches_title(self, sample_docs: Path) -> None:
        indexer = DocsIndexer(sample_docs)
        indexer.build()
        results = indexer.search("introduction")

        assert len(results) >= 1
        assert results[0]["title"] == "Introduction"

    def test_search_matches_tags(self, sample_docs: Path) -> None:
        indexer = DocsIndexer(sample_docs)
        indexer.build()
        results = indexer.search("overview")

        assert any(r["title"] == "Introduction" for r in results)

    def test_search_matches_summary(self, sample_docs: Path) -> None:
        indexer = DocsIndexer(sample_docs)
        indexer.build()
        results = indexer.search("live web")

        assert any(r["title"] == "Web Search" for r in results)

    def test_search_matches_section_content(self, sample_docs: Path) -> None:
        indexer = DocsIndexer(sample_docs)
        indexer.build()
        results = indexer.search("notes tasks")

        assert any(r["title"] == "Introduction" for r in results)

    def test_search_returns_empty_for_no_match(self, sample_docs: Path) -> None:
        indexer = DocsIndexer(sample_docs)
        indexer.build()
        results = indexer.search("xyznonexistent")

        assert results == []

    def test_search_limits_results(self, sample_docs: Path) -> None:
        indexer = DocsIndexer(sample_docs)
        indexer.build()
        results = indexer.search("sidebar", max_results=1)

        assert len(results) <= 1


class TestKnowledgeProvider:
    """Tests for knowledge provider singleton."""

    def test_init_and_get(self, sample_docs: Path) -> None:
        with patch("api.services.knowledge.provider._indexer", None):
            init_docs_indexer(sample_docs)
            indexer = get_docs_indexer()
            assert indexer is not None
            assert len(indexer.catalog) > 0

    def test_get_without_init_raises(self) -> None:
        with patch("api.services.knowledge.provider._indexer", None):
            with pytest.raises(RuntimeError):
                get_docs_indexer()
