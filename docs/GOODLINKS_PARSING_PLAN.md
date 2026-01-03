# Web-Save Skill: GoodLinks-Quality Parsing Implementation Plan

## Executive Summary

This document outlines a comprehensive plan to evolve the **web-save skill** (`/backend/skills/web-save/`) from its current Jina.ai API-based approach to a local, deterministic parsing system inspired by GoodLinks' proven architecture.

### What We're Building

A high-fidelity web content parser that:
- Uses local, deterministic parsing (Arc90 Readability + custom rule engine)
- Produces clean Markdown with rich YAML frontmatter optimized for AI ingestion
- Handles JavaScript-heavy sites via Playwright headless browser
- Supports extensible, declarative per-site parsing rules
- Integrates seamlessly with existing database schema and frontend

### Why This Change

**Current State (Jina.ai API)**:
- External dependency with per-request costs
- Black box processing with limited control
- Inconsistent output quality across sites
- No ability to customize extraction logic

**Target State (Local Parsing)**:
- Full control over extraction quality
- Zero per-request costs
- Extensible rule system for site-specific handling
- Deterministic, inspectable output
- Better metadata extraction (author, tags, word count)

### Key Metrics

| Aspect | Current | Target |
|--------|---------|--------|
| Parsing Method | Jina API | Readability + Rules |
| Cost per Save | ~$0.001 | $0 |
| JS Rendering | Yes (via Jina) | Yes (via Playwright) |
| Custom Rules | None | ~50+ declarative rules |
| Metadata Fields | 3 (title, source, date) | 7+ (author, tags, word count, etc.) |
| Output Format | Plain markdown | Markdown + YAML frontmatter |

---

## Current State: Web-Save Skill Analysis

### Architecture Overview

```
User Request (URL)
    ↓
save_url.py script
    ↓
Jina.ai Reader API (external)
    ↓
Parse Jina metadata (regex)
    ↓
WebsitesService.upsert_website()
    ↓
PostgreSQL (websites table)
```

### Current Implementation

**Location**: `/backend/skills/web-save/`

**Key Files**:
- `scripts/save_url.py` - Main ingestion (150 LOC)
- `scripts/read_website.py` - Retrieval
- `scripts/list_websites.py` - Filtering/search
- `scripts/{pin,archive,delete}_website.py` - Metadata operations

**Database Schema** (`api/models/website.py`):
```python
class Website(Base):
    id = UUID                           # Primary key
    user_id = Text                      # User ownership
    url = Text                          # Normalized URL (no query/fragment)
    url_full = Text                     # Original full URL
    domain = Text                       # Extracted domain
    title = Text                        # Article title
    content = Text                      # Markdown content
    source = Text                       # Source attribution
    saved_at = DateTime                 # When user saved it
    published_at = DateTime             # Original publish date
    metadata_ = JSONB                   # Flexible metadata (pinned, archived, etc.)
    created_at = DateTime
    updated_at = DateTime
    last_opened_at = DateTime
    deleted_at = DateTime               # Soft delete
```

### Current Metadata Extraction

Jina API returns inline metadata that is parsed via regex:

```python
def parse_jina_metadata(content: str) -> Tuple[Dict, str]:
    # Extracts:
    # - Title: <title>
    # - URL Source: <canonical_url>
    # - Published Time: <iso_datetime>
    # Then removes these lines from content
```

**Extracted Fields**:
- `title` - Page title (with fallbacks to H1, first line, domain)
- `url_source` - Canonical URL after redirects
- `published_time` - ISO 8601 datetime

**Limitations**:
- No author extraction
- No word count or reading time
- No tags or categorization
- No image metadata
- Content quality depends on Jina's black-box algorithm

---

## GoodLinks Architecture: Empirical Findings

> This section documents the proven approach that GoodLinks uses, which we'll adapt for web-save.

### Core Insight: Deterministic Pipeline

GoodLinks' quality comes from a carefully engineered, deterministic pipeline:

1. **Arc90 Readability** - Baseline article extraction
2. **Declarative DOM Rule Engine** - Site-specific fixes
3. **Dual Trigger Mechanisms**:
   - Host-specific rules (e.g., theguardian.com)
   - DOM signature rules (e.g., detect Squarespace, Medium)
4. **Clean post-processing** - Reader-friendly output

### Rule Engine Structure

GoodLinks ships with `~56 declarative rules` in JSON format. Each rule describes DOM mutations:

**Observed Rule Fields**:

| Key | Meaning |
|-----|---------|
| `a` | Article root selector override |
| `we` | Wrapper element selector |
| `e` | Elements to remove |
| `i` | Elements to force include |
| `ac` | Transform actions (retag, unwrap, move) |
| `m` | Metadata extraction overrides |
| `ea` | Apply to entire article |
| `d` | Discard rule / disable extraction |

**Example Rule** (simplified):
```json
{
  "a": "article",
  "e": ".related, .footer, .ads",
  "ac": [
    { "s": "figure img", "tp": "figure" }
  ]
}
```

### Trigger Mechanisms

**A. Host-Based Rules**

Keyed by `md5(normalized_host)`:

```
theguardian.com → Custom media + caption handling
wsj.com → Paywall and media restructuring
cnn.com → Image inclusion + author extraction
medium.com → Draft.js content unwrapping
```

**B. DOM Signature Rules**

Triggered by detecting specific DOM patterns:

| Platform | Selector Pattern |
|----------|-----------------|
| Swiper carousels | `.swiper-slide-duplicate` |
| Squarespace | `.sqs-col-*` |
| Medium / Draft.js | `.public-DraftEditor-content` |
| Intercom help centers | `.intercom-interblocks-*` |
| Dotdash Meredith | `.mntl-*` |

**Key Finding**: Some rules never matched URLs in a 40k-article dataset, yet correctly matched DOM features when present. This proves GoodLinks uses **DOM fingerprinting**, not just URL mapping.

### Why This Works

- Treats extraction as **engineering**, not inference
- Uses **small, targeted fixes** vs. global heuristics
- Avoids ML brittleness
- Keeps rules **declarative and inspectable**
- **Separates concerns** cleanly

Most pages require no special handling. A small minority benefit enormously from precise, cheap fixes.

---

## Target Architecture for SideBar

### Overview

```
URL
 ↓
[Fetch HTML (requests)]
 ↓
[JS Rendering? (Playwright)] ← Optional, detect if needed
 ↓
[Pre-Readability DOM pass] ← Optional, for specific sites
 ↓
[Readability extraction (readability-lxml)]
 ↓
[Rule engine: Host + DOM signature matching]
 ↓
[Apply declarative DOM mutations]
 ↓
[Metadata extraction & enrichment]
 ↓
[Markdown conversion (markdownify)]
 ↓
[YAML frontmatter assembly]
 ↓
[Generate final content with frontmatter]
 ↓
[WebsitesService.upsert_website()]
 ↓
PostgreSQL (websites table)
```

### Target YAML Frontmatter

Based on your requirements, every saved website will have:

```yaml
---
source: https://example.com/article
title: Article Title
author: John Doe
published_date: 2025-03-19
domain: example.com
word_count: 1543
tags: [technology, ai]
saved_at: 2025-03-19T10:30:00Z
---

# Article Title

Article content in clean markdown...
```

**Field Specifications**:

| Field | Type | Source | Required |
|-------|------|--------|----------|
| `source` | URL | Canonical URL (after redirects) | Yes |
| `title` | String | Readability → H1 → domain | Yes |
| `author` | String | Meta tags → JSON-LD → byline | No |
| `published_date` | ISO 8601 | Meta tags → JSON-LD | No |
| `domain` | String | Extracted from URL | Yes |
| `word_count` | Integer | Calculated from content | Yes |
| `tags` | Array | Auto-generated + manual | No |
| `saved_at` | ISO 8601 | Current timestamp | Yes |

### Storage Strategy

**Keep current database structure**, add frontmatter to `content` field:

```python
# Database columns (unchanged)
title: str              # For querying
published_at: datetime  # For filtering
domain: str             # For grouping

# content field (updated)
content: str = f"""---
source: {source}
title: {title}
author: {author}
...
---

{markdown_body}
"""
```

**Benefits**:
- Database columns enable efficient querying/filtering
- Frontmatter in content makes it AI-ready for direct consumption
- Backward compatible (existing queries work unchanged)

---

## Implementation Roadmap

### Phase 1: Core Local Parsing (Week 1-2)

**Goal**: Replace Jina with local Readability, maintain feature parity.

**Tasks**:

1. **Add Dependencies** (`pyproject.toml`):
   ```toml
   readability-lxml = "^0.8.1"
   markdownify = "^0.11.6"
   lxml = "^4.9.3"
   beautifulsoup4 = "^4.12.0"
   ```

2. **Create `parsers/` Module**:
   ```
   skills/web-save/parsers/
   ├── __init__.py
   ├── fetcher.py          # HTTP fetching with headers
   ├── readability.py      # Readability wrapper
   ├── metadata.py         # Metadata extraction
   ├── markdown.py         # HTML → Markdown conversion
   └── frontmatter.py      # YAML frontmatter generation
   ```

3. **Implement `fetcher.py`**:
   ```python
   def fetch_html(url: str, timeout: int = 30) -> Tuple[str, str]:
       """
       Fetch HTML from URL.

       Returns:
           (html_content, final_url)  # final_url after redirects
       """
       headers = {
           "User-Agent": "Mozilla/5.0 (compatible; SideBar/1.0; +https://sidebar.app)"
       }
       response = requests.get(url, headers=headers, timeout=timeout)
       response.raise_for_status()
       return response.text, response.url
   ```

4. **Implement `readability.py`**:
   ```python
   from readability import Document

   def extract_article(html: str, url: str) -> Dict[str, Any]:
       """
       Extract article using Readability.

       Returns:
           {
               "title": str,
               "content": str,  # Simplified HTML
               "excerpt": str
           }
       """
       doc = Document(html)
       return {
           "title": doc.title(),
           "content": doc.summary(html_partial=False),
           "excerpt": doc.summary(html_partial=True)
       }
   ```

5. **Implement `metadata.py`**:
   ```python
   def extract_metadata(html: str, url: str) -> Dict[str, Any]:
       """
       Extract rich metadata from HTML.

       Extracts:
       - title (og:title, twitter:title, <title>)
       - author (article:author, meta[name="author"])
       - published_date (article:published_time, meta[name="date"])
       - description (og:description)
       - image (og:image)

       Also checks JSON-LD structured data.
       """
       soup = BeautifulSoup(html, 'lxml')

       # Meta tags
       meta = {}
       for tag in soup.find_all('meta'):
           if tag.get('property'):
               meta[tag['property']] = tag.get('content')
           if tag.get('name'):
               meta[tag['name']] = tag.get('content')

       # JSON-LD
       jsonld = extract_jsonld(soup)

       return {
           "author": (
               jsonld.get("author", {}).get("name") or
               meta.get("article:author") or
               meta.get("author")
           ),
           "published_date": (
               meta.get("article:published_time") or
               meta.get("date") or
               jsonld.get("datePublished")
           ),
           "title": (
               meta.get("og:title") or
               meta.get("twitter:title") or
               soup.find("title")
           ),
           # ... more fields
       }
   ```

6. **Implement `markdown.py`**:
   ```python
   from markdownify import markdownify as md

   def html_to_markdown(html: str) -> str:
       """
       Convert HTML to clean markdown.

       Custom configuration:
       - Strip attributes from tags
       - Convert images to ![alt](url) format
       - Preserve heading hierarchy
       - Remove scripts, styles, ads
       """
       return md(
           html,
           heading_style="ATX",
           bullets="-",
           code_language="",
           strip=['script', 'style', 'meta', 'link']
       )
   ```

7. **Implement `frontmatter.py`**:
   ```python
   import yaml

   def generate_frontmatter(metadata: Dict[str, Any]) -> str:
       """
       Generate YAML frontmatter block.

       Args:
           metadata: Dict with keys: source, title, author, published_date,
                     domain, word_count, tags, saved_at

       Returns:
           "---\nkey: value\n...\n---\n"
       """
       # Filter out None values
       clean_meta = {k: v for k, v in metadata.items() if v is not None}

       yaml_str = yaml.dump(
           clean_meta,
           default_flow_style=False,
           allow_unicode=True,
           sort_keys=False  # Preserve field order
       )

       return f"---\n{yaml_str}---\n"
   ```

8. **Update `save_url.py`**:
   ```python
   from parsers import fetcher, readability, metadata, markdown, frontmatter

   def save_url_local(url: str, user_id: str) -> Dict[str, Any]:
       """New implementation using local parsing."""

       # 1. Fetch HTML
       html, final_url = fetcher.fetch_html(url)

       # 2. Extract article with Readability
       article = readability.extract_article(html, final_url)

       # 3. Extract metadata
       meta = metadata.extract_metadata(html, final_url)

       # 4. Convert to markdown
       md_content = markdown.html_to_markdown(article["content"])

       # 5. Calculate word count
       word_count = len(md_content.split())

       # 6. Generate frontmatter
       fm_data = {
           "source": final_url,
           "title": article["title"] or meta["title"],
           "author": meta.get("author"),
           "published_date": meta.get("published_date"),
           "domain": urlparse(final_url).netloc,
           "word_count": word_count,
           "tags": [],  # TODO: Auto-tagging in Phase 3
           "saved_at": datetime.now(timezone.utc).isoformat()
       }
       fm = frontmatter.generate_frontmatter(fm_data)

       # 7. Combine frontmatter + content
       full_content = fm + "\n" + md_content

       # 8. Save to database
       db = SessionLocal()
       set_session_user_id(db, user_id)
       try:
           website = WebsitesService.upsert_website(
               db,
               user_id,
               url=normalize_url(final_url),
               url_full=final_url,
               title=fm_data["title"],
               content=full_content,  # Now includes frontmatter
               source=final_url,
               saved_at=datetime.now(timezone.utc),
               published_at=parse_published_at(fm_data.get("published_date")),
               pinned=False,
               archived=False,
           )
           return {
               "id": str(website.id),
               "title": website.title,
               "url": website.url,
               "domain": website.domain,
               "word_count": word_count
           }
       finally:
           db.close()
   ```

**Testing**:
- Test on 10-20 diverse URLs (news, blogs, technical docs, Medium)
- Compare output quality vs. Jina
- Validate frontmatter generation
- Ensure database compatibility

---

### Phase 2: JavaScript Rendering (Week 2-3)

**Goal**: Handle JS-heavy sites (SPAs, React apps) with Playwright.

**Tasks**:

1. **Add Dependency**:
   ```toml
   playwright = "^1.40.0"
   ```

2. **Install Playwright Browsers**:
   ```bash
   playwright install chromium
   ```

3. **Create `parsers/js_renderer.py`**:
   ```python
   from playwright.sync_api import sync_playwright

   def render_with_js(url: str, timeout: int = 30000) -> Tuple[str, str]:
       """
       Render page with JavaScript using headless Chromium.

       Returns:
           (html_content, final_url)
       """
       with sync_playwright() as p:
           browser = p.chromium.launch(headless=True)
           context = browser.new_context(
               user_agent="Mozilla/5.0 (compatible; SideBar/1.0)"
           )
           page = context.new_page()

           # Navigate and wait for network idle
           page.goto(url, wait_until="networkidle", timeout=timeout)

           # Get rendered HTML
           html = page.content()
           final_url = page.url

           browser.close()

           return html, final_url
   ```

4. **Add JS Detection Heuristic** (`parsers/fetcher.py`):
   ```python
   def requires_js_rendering(html: str) -> bool:
       """
       Detect if page likely needs JS rendering.

       Heuristics:
       - Very short HTML (<500 chars)
       - Contains React/Vue/Angular markers
       - Has <noscript> warning messages
       """
       if len(html) < 500:
           return True

       js_frameworks = [
           'react-root',
           'ng-app',
           '__NEXT_DATA__',
           'nuxt',
           '__gatsby'
       ]

       return any(marker in html for marker in js_frameworks)
   ```

5. **Update `save_url.py`** with Fallback Logic:
   ```python
   def save_url_local(url: str, user_id: str) -> Dict[str, Any]:
       # Try standard fetch first
       html, final_url = fetcher.fetch_html(url)

       # Detect if JS rendering needed
       if fetcher.requires_js_rendering(html):
           html, final_url = js_renderer.render_with_js(url)

       # ... rest of parsing logic
   ```

**Testing**:
- Test on JS-heavy sites:
  - Medium.com articles
  - Next.js documentation
  - React app pages
  - Vue.js sites
- Verify rendered content matches browser view
- Measure performance impact (should be <5s for most pages)

---

### Phase 3: Rule Engine (Week 3-5)

**Goal**: Implement declarative rule system for site-specific optimizations.

**Tasks**:

1. **Design Rule Schema** (`parsers/rules_schema.yaml`):
   ```yaml
   # Example: Remove duplicate Swiper carousel slides
   - id: swiper-carousel
     priority: 100
     trigger:
       dom:
         any:
           - ".swiper-slide-duplicate"
     actions:
       remove:
         - ".swiper-slide-duplicate"

   # Example: Guardian custom handling
   - id: theguardian
     priority: 90
     trigger:
       host:
         equals: "www.theguardian.com"
     actions:
       remove:
         - ".related-links"
         - "aside"
       transform:
         - selector: "figure img"
           wrap: "figure"
       metadata:
         author_selector: ".dcr-byline a"
   ```

2. **Create Rules Storage** (`parsers/rules/`):
   ```
   parsers/rules/
   ├── __init__.py
   ├── common.yaml         # Platform rules (Squarespace, Medium, etc.)
   ├── news.yaml           # News sites (Guardian, NYT, WSJ, etc.)
   ├── technical.yaml      # Dev blogs, docs sites
   └── social.yaml         # Medium, Substack, etc.
   ```

3. **Implement Rule Engine** (`parsers/rule_engine.py`):
   ```python
   from typing import List, Dict, Any
   from lxml import html as lxml_html
   import yaml

   class RuleEngine:
       def __init__(self, rules_dir: Path):
           self.rules = self._load_rules(rules_dir)

       def _load_rules(self, rules_dir: Path) -> List[Dict]:
           """Load all YAML rule files."""
           rules = []
           for file in rules_dir.glob("*.yaml"):
               with open(file) as f:
                   rules.extend(yaml.safe_load(f))
           return sorted(rules, key=lambda r: r.get('priority', 50), reverse=True)

       def match_rules(self, url: str, html: str) -> List[Dict]:
           """Find all matching rules for URL and HTML."""
           tree = lxml_html.fromstring(html)
           domain = urlparse(url).netloc

           matched = []
           for rule in self.rules:
               if self._rule_matches(rule, domain, tree):
                   matched.append(rule)

           return matched

       def _rule_matches(self, rule: Dict, domain: str, tree) -> bool:
           """Check if rule triggers match."""
           trigger = rule.get('trigger', {})

           # Host-based trigger
           if 'host' in trigger:
               if trigger['host'].get('equals') == domain:
                   return True
               if domain.endswith(trigger['host'].get('ends_with', '')):
                   return True

           # DOM-based trigger
           if 'dom' in trigger:
               if 'any' in trigger['dom']:
                   for selector in trigger['dom']['any']:
                       if tree.cssselect(selector):
                           return True
               if 'all' in trigger['dom']:
                   if all(tree.cssselect(sel) for sel in trigger['dom']['all']):
                       return True

           return False

       def apply_rules(self, html: str, rules: List[Dict]) -> str:
           """Apply matched rules to HTML."""
           tree = lxml_html.fromstring(html)

           for rule in rules:
               actions = rule.get('actions', {})

               # Remove elements
               if 'remove' in actions:
                   for selector in actions['remove']:
                       for elem in tree.cssselect(selector):
                           elem.getparent().remove(elem)

               # Transform elements
               if 'transform' in actions:
                   for transform in actions['transform']:
                       self._apply_transform(tree, transform)

           return lxml_html.tostring(tree, encoding='unicode')

       def _apply_transform(self, tree, transform: Dict):
           """Apply individual transform (wrap, unwrap, retag)."""
           selector = transform.get('selector')
           elements = tree.cssselect(selector)

           if 'wrap' in transform:
               # Wrap elements in new tag
               tag = transform['wrap']
               for elem in elements:
                   wrapper = lxml_html.Element(tag)
                   elem.addprevious(wrapper)
                   wrapper.append(elem)

           # TODO: Add unwrap, retag, move, etc.
   ```

4. **Integrate into Pipeline** (`save_url.py`):
   ```python
   from parsers.rule_engine import RuleEngine

   # Initialize once (module-level)
   rule_engine = RuleEngine(Path(__file__).parent / "parsers" / "rules")

   def save_url_local(url: str, user_id: str) -> Dict[str, Any]:
       html, final_url = fetcher.fetch_html(url)

       # Apply rules BEFORE Readability
       matched_rules = rule_engine.match_rules(final_url, html)
       if matched_rules:
           html = rule_engine.apply_rules(html, matched_rules)

       # Continue with Readability extraction
       article = readability.extract_article(html, final_url)
       # ...
   ```

5. **Populate Initial Rules**:

   **`common.yaml`**:
   ```yaml
   - id: swiper-carousel
     priority: 100
     trigger:
       dom:
         any: [".swiper-slide-duplicate"]
     actions:
       remove: [".swiper-slide-duplicate"]

   - id: squarespace
     priority: 95
     trigger:
       dom:
         any: [".sqs-block"]
     actions:
       remove: [".sqs-announcement-bar", ".sqs-cookie-banner"]

   - id: medium
     priority: 95
     trigger:
       dom:
         any: [".metabar", "article"]
       host:
         ends_with: "medium.com"
     actions:
       remove: [".metabar", "aside", ".pw-responses"]
   ```

   **`news.yaml`**:
   ```yaml
   - id: theguardian
     priority: 90
     trigger:
       host:
         equals: "www.theguardian.com"
     actions:
       remove:
         - "aside"
         - ".submeta"
         - "[data-component='nav3']"
       metadata:
         author_selector: "[rel='author']"

   - id: nytimes
     priority: 90
     trigger:
       host:
         ends_with: "nytimes.com"
     actions:
       remove:
         - ".ad"
         - "#story-footer"
         - ".supplemental"
       metadata:
         author_selector: "[itemprop='author']"
   ```

**Testing**:
- Create test suite with sample HTML from each target site
- Verify rules match correctly
- Validate DOM mutations produce cleaner output
- Test rule priority ordering

---

### Phase 4: Auto-Tagging & Enrichment (Week 5-6)

**Goal**: Add intelligent metadata enrichment.

**Tasks**:

1. **Simple Keyword-Based Tagging** (`parsers/tagger.py`):
   ```python
   import re
   from collections import Counter

   # Common stop words
   STOP_WORDS = set(['the', 'a', 'an', 'and', 'or', 'but', 'in', 'on', 'at', ...])

   # Domain-to-category mapping
   DOMAIN_CATEGORIES = {
       'github.com': ['programming', 'code'],
       'stackoverflow.com': ['programming', 'qa'],
       'medium.com': ['blog'],
       'dev.to': ['programming', 'tutorial'],
       # ... more mappings
   }

   def extract_tags(
       content: str,
       domain: str,
       title: str,
       max_tags: int = 5
   ) -> List[str]:
       """
       Extract tags from content.

       Strategy:
       1. Domain-based category tags
       2. Common programming keywords
       3. Most frequent meaningful words
       """
       tags = set()

       # Domain categories
       if domain in DOMAIN_CATEGORIES:
           tags.update(DOMAIN_CATEGORIES[domain])

       # Programming keywords
       prog_keywords = {
           'python', 'javascript', 'react', 'vue', 'typescript',
           'api', 'database', 'docker', 'kubernetes', 'aws',
           'machine learning', 'ai', 'data science'
       }

       content_lower = content.lower()
       for keyword in prog_keywords:
           if keyword in content_lower or keyword in title.lower():
               tags.add(keyword)

       # Frequency-based (fallback)
       if len(tags) < max_tags:
           words = re.findall(r'\b\w{4,}\b', content.lower())
           filtered = [w for w in words if w not in STOP_WORDS]
           common = Counter(filtered).most_common(10)
           tags.update([word for word, count in common if count > 3])

       return list(tags)[:max_tags]
   ```

2. **Reading Time Calculation**:
   ```python
   def calculate_reading_time(word_count: int, wpm: int = 200) -> str:
       """
       Calculate reading time.

       Args:
           word_count: Total words
           wpm: Words per minute (default 200)

       Returns:
           "5 min" or "1 min"
       """
       minutes = max(1, round(word_count / wpm))
       return f"{minutes} min"
   ```

3. **Update Frontmatter Generation**:
   ```python
   fm_data = {
       "source": final_url,
       "title": article["title"],
       "author": meta.get("author"),
       "published_date": meta.get("published_date"),
       "domain": domain,
       "word_count": word_count,
       "reading_time": calculate_reading_time(word_count),
       "tags": extract_tags(md_content, domain, article["title"]),
       "saved_at": datetime.now(timezone.utc).isoformat()
   }
   ```

**Testing**:
- Verify tag extraction on technical vs. non-technical content
- Validate reading time calculations
- Check frontmatter includes all expected fields

---

### Phase 5: Migration Script (Week 6)

**Goal**: Re-parse all existing saved websites with new system.

**Create `scripts/migrate_existing_websites.py`**:

```python
#!/usr/bin/env python3
"""
Migrate Existing Websites to New Parsing System

Re-fetches and re-parses all saved websites using the new local parsing
pipeline with frontmatter generation.

Usage:
    python migrate_existing_websites.py --user-id USER_ID [--dry-run] [--limit N]
"""

import sys
import argparse
from pathlib import Path
from datetime import datetime

BACKEND_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(BACKEND_ROOT))

from api.db.session import SessionLocal, set_session_user_id
from api.services.websites_service import WebsitesService
from skills.web_save.scripts.save_url import save_url_local


def migrate_websites(user_id: str, dry_run: bool = False, limit: int = None):
    """
    Migrate all websites for a user.

    Args:
        user_id: User to migrate
        dry_run: If True, only print what would be done
        limit: Max number to migrate (for testing)
    """
    db = SessionLocal()
    set_session_user_id(db, user_id)

    try:
        # Get all non-deleted websites for user
        websites = db.query(Website).filter(
            Website.user_id == user_id,
            Website.deleted_at.is_(None)
        ).all()

        total = len(websites)
        if limit:
            websites = websites[:limit]

        print(f"Found {total} websites for user {user_id}")
        print(f"Will migrate: {len(websites)} websites")

        if dry_run:
            print("\nDRY RUN - No changes will be made\n")

        success_count = 0
        error_count = 0

        for i, website in enumerate(websites, 1):
            print(f"[{i}/{len(websites)}] {website.url}")

            if dry_run:
                print(f"  Would re-fetch and re-parse")
                continue

            try:
                # Preserve original saved_at and metadata
                original_saved_at = website.saved_at
                original_pinned = website.metadata_.get('pinned', False)
                original_archived = website.metadata_.get('archived', False)

                # Re-fetch and re-parse
                result = save_url_local(website.url_full or website.url, user_id)

                # Restore preserved fields
                updated = db.query(Website).filter(Website.id == result['id']).first()
                updated.saved_at = original_saved_at
                updated.metadata_['pinned'] = original_pinned
                updated.metadata_['archived'] = original_archived
                db.commit()

                print(f"  ✓ Migrated - {result['word_count']} words")
                success_count += 1

            except Exception as e:
                print(f"  ✗ Error: {str(e)}")
                error_count += 1
                continue

        print(f"\nMigration complete:")
        print(f"  Success: {success_count}")
        print(f"  Errors: {error_count}")

    finally:
        db.close()


def main():
    parser = argparse.ArgumentParser(
        description='Migrate existing websites to new parsing system'
    )
    parser.add_argument('--user-id', required=True, help='User ID to migrate')
    parser.add_argument('--dry-run', action='store_true', help='Print what would be done')
    parser.add_argument('--limit', type=int, help='Limit number to migrate (for testing)')

    args = parser.parse_args()

    migrate_websites(args.user_id, args.dry_run, args.limit)


if __name__ == '__main__':
    main()
```

**Usage**:
```bash
# Test on 5 websites first
python migrate_existing_websites.py --user-id USER_ID --limit 5

# Dry run to see what would happen
python migrate_existing_websites.py --user-id USER_ID --dry-run

# Full migration
python migrate_existing_websites.py --user-id USER_ID
```

---

## Technical Specifications

### Dependencies

**Add to `pyproject.toml`**:
```toml
[tool.poetry.dependencies]
# Existing
requests = "^2.31.0"
sqlalchemy = "^2.0.0"

# New for local parsing
readability-lxml = "^0.8.1"      # Readability algorithm
markdownify = "^0.11.6"          # HTML → Markdown
lxml = "^4.9.3"                  # XML/HTML parsing
beautifulsoup4 = "^4.12.0"       # HTML parsing for metadata
playwright = "^1.40.0"           # JS rendering
pyyaml = "^6.0.0"                # Rule definitions
```

### File Structure (Updated)

```
backend/skills/web-save/
├── SKILL.md
├── scripts/
│   ├── save_url.py              # ← Updated with new parsing
│   ├── read_website.py
│   ├── list_websites.py
│   ├── pin_website.py
│   ├── archive_website.py
│   ├── delete_website.py
│   └── migrate_existing_websites.py  # ← New migration script
├── parsers/                      # ← New module
│   ├── __init__.py
│   ├── fetcher.py               # HTTP fetching
│   ├── js_renderer.py           # Playwright integration
│   ├── readability.py           # Readability wrapper
│   ├── metadata.py              # Metadata extraction
│   ├── markdown.py              # HTML → Markdown
│   ├── frontmatter.py           # YAML generation
│   ├── tagger.py                # Auto-tagging
│   ├── rule_engine.py           # Rule matching & application
│   └── rules/                   # ← Rule definitions
│       ├── common.yaml
│       ├── news.yaml
│       ├── technical.yaml
│       └── social.yaml
└── tests/                        # ← New test suite
    ├── test_fetcher.py
    ├── test_readability.py
    ├── test_metadata.py
    ├── test_rule_engine.py
    └── fixtures/
        ├── guardian.html
        ├── medium.html
        ├── nytimes.html
        └── ...
```

### Database Schema (Unchanged)

No schema changes required. The `content` field will now contain frontmatter + markdown:

```sql
-- Example stored content
content = '---
source: https://example.com/article
title: Article Title
author: John Doe
published_date: 2025-03-19
domain: example.com
word_count: 1543
tags: [technology, ai]
saved_at: 2025-03-19T10:30:00Z
---

# Article Title

Article content...'
```

Existing database columns (`title`, `published_at`, `domain`) remain for efficient querying.

### Performance Targets

| Operation | Current (Jina) | Target (Local) |
|-----------|----------------|----------------|
| Simple page (HTML only) | 2-3s | 1-2s |
| JS-rendered page | 2-3s | 3-5s |
| Cost per save | ~$0.001 | $0 |
| Metadata fields | 3 | 7+ |

### Error Handling

**Enhanced error messages for new failure modes**:

```python
# Example: JS rendering timeout
{
  "success": false,
  "error": {
    "type": "RenderError",
    "message": "Failed to render page with JavaScript",
    "suggestions": [
      "Page may be blocking automation",
      "Try increasing timeout (default 30s)",
      "Check if site requires authentication",
      "Verify Playwright is installed: playwright install chromium"
    ]
  }
}
```

---

## Testing Strategy

### Unit Tests

```python
# tests/test_readability.py
def test_extract_article():
    html = load_fixture("guardian.html")
    article = readability.extract_article(html, "https://theguardian.com/test")
    assert article["title"]
    assert len(article["content"]) > 100

# tests/test_rule_engine.py
def test_guardian_rule_matches():
    engine = RuleEngine(rules_dir)
    html = load_fixture("guardian.html")
    rules = engine.match_rules("https://www.theguardian.com/article", html)
    assert any(r["id"] == "theguardian" for r in rules)

def test_rule_removes_elements():
    engine = RuleEngine(rules_dir)
    html = '<html><body><div class="ad">Ad</div><p>Content</p></body></html>'
    rule = {"actions": {"remove": [".ad"]}}
    result = engine.apply_rules(html, [rule])
    assert "Ad" not in result
    assert "Content" in result
```

### Integration Tests

```python
def test_full_pipeline_guardian():
    """Test complete parsing pipeline on Guardian article."""
    url = "https://www.theguardian.com/sample-article"
    result = save_url_local(url, "test-user")

    assert result["title"]
    assert result["word_count"] > 0

    # Verify database content
    db = SessionLocal()
    website = db.query(Website).filter(Website.id == result["id"]).first()

    # Check frontmatter
    assert website.content.startswith("---\n")
    assert "source:" in website.content
    assert "word_count:" in website.content

    db.close()
```

### Manual Testing Checklist

Test with diverse URLs:

**News Sites**:
- [ ] The Guardian
- [ ] New York Times
- [ ] Wall Street Journal
- [ ] BBC News

**Tech Blogs**:
- [ ] Medium article
- [ ] Dev.to post
- [ ] Personal WordPress blog
- [ ] Substack newsletter

**Documentation**:
- [ ] Python docs
- [ ] React docs
- [ ] MDN Web Docs

**Edge Cases**:
- [ ] Paywalled content (WSJ, NYT)
- [ ] JS-heavy SPA (React app)
- [ ] Very long article (>10k words)
- [ ] Article with many images
- [ ] Page with video embeds

---

## Migration Strategy

### Phase 1: Parallel Running (Week 1-2)

- Implement local parsing alongside Jina
- Add flag to toggle between implementations
- Compare outputs side-by-side
- Validate quality improvements

### Phase 2: Gradual Rollout (Week 3-4)

- Default to local parsing for new saves
- Keep Jina as fallback for failures
- Monitor error rates
- Gather user feedback

### Phase 3: Full Migration (Week 5-6)

- Run `migrate_existing_websites.py` on all users
- Remove Jina dependencies
- Archive Jina-based code
- Update documentation

### Rollback Plan

If issues arise:
1. Toggle flag back to Jina mode
2. Investigate failures
3. Fix issues in local parser
4. Re-test before re-enabling

---

## Success Metrics

**Quality Improvements**:
- [ ] 90%+ of articles have complete frontmatter (all 7+ fields)
- [ ] Author extraction works on 80%+ of news articles
- [ ] Tags are relevant (manual review of 50 samples)
- [ ] Markdown is cleaner (fewer HTML artifacts)

**Performance**:
- [ ] 95%+ success rate (vs. current with Jina)
- [ ] Average save time <3s (excluding JS rendering)
- [ ] JS rendering works on 90%+ of SPA pages

**Cost Savings**:
- [ ] Zero API costs (down from ~$0.001/save)
- [ ] Estimated monthly savings: ~$X (based on save volume)

**User Experience**:
- [ ] No regression in frontend display
- [ ] Improved AI consumption (Claude can read frontmatter)
- [ ] Search/filter still works (database columns unchanged)

---

## Future Enhancements

### Post-Launch (Phase 6+)

**Advanced Tagging**:
- LLM-based topic extraction (send to Claude for analysis)
- User-defined tag rules
- Automatic tag suggestions based on past saves

**Content Analysis**:
- Sentiment analysis
- Reading level (Flesch-Kincaid)
- Key phrase extraction
- Summary generation (first 2-3 sentences)

**Archival Features**:
- Full-page screenshots (via Playwright)
- PDF generation
- Archive.org integration for link preservation
- Detect dead links and auto-refresh

**Rule Engine Extensions**:
- Per-user custom rules
- Community rule sharing
- Auto-learning (detect common patterns in user's saves)
- Visual rule builder UI

**Performance Optimizations**:
- Caching of common pages
- Background re-parsing queue
- Parallel batch processing
- CDN integration for image hosting

---

## Appendix A: Quick Reference

### Key Commands

```bash
# Install dependencies
cd backend
poetry add readability-lxml markdownify lxml beautifulsoup4 playwright pyyaml
playwright install chromium

# Test on single URL
python skills/web-save/scripts/save_url.py \
  "https://example.com/article" \
  --database \
  --user-id USER_ID \
  --json

# Migrate existing websites (dry run)
python skills/web-save/scripts/migrate_existing_websites.py \
  --user-id USER_ID \
  --dry-run

# Migrate existing websites (for real)
python skills/web-save/scripts/migrate_existing_websites.py \
  --user-id USER_ID

# Run tests
pytest skills/web-save/tests/
```

### Example Output

**Before (Jina)**:
```
Title: Article Title
URL Source: https://example.com/article
Published Time: 2025-03-19T10:00:00Z

Article content in markdown...
```

**After (Local + Frontmatter)**:
```yaml
---
source: https://example.com/article
title: Article Title
author: John Doe
published_date: 2025-03-19T10:00:00Z
domain: example.com
word_count: 1543
reading_time: 8 min
tags: [technology, ai, programming]
saved_at: 2025-03-19T15:30:00Z
---

# Article Title

Article content in markdown...
```

---

## Appendix B: Rule Examples

### Common Platform Rules

**Squarespace**:
```yaml
- id: squarespace
  priority: 95
  trigger:
    dom:
      any: [".sqs-block"]
  actions:
    remove:
      - ".sqs-announcement-bar"
      - ".sqs-cookie-banner"
      - "[data-test='sqs-blocks-newsletter-form']"
```

**Medium**:
```yaml
- id: medium
  priority: 95
  trigger:
    host:
      ends_with: "medium.com"
  actions:
    remove:
      - ".metabar"
      - "aside"
      - ".pw-responses"
      - "[data-test='post-sidebar']"
    metadata:
      author_selector: "a[rel='author']"
```

**WordPress (common theme)**:
```yaml
- id: wordpress-common
  priority: 80
  trigger:
    dom:
      any: [".wp-block-post-content"]
  actions:
    remove:
      - ".sharedaddy"
      - ".jp-relatedposts"
      - "#comments"
```

### News Site Rules

**The Guardian**:
```yaml
- id: theguardian
  priority: 90
  trigger:
    host:
      equals: "www.theguardian.com"
  actions:
    remove:
      - "aside"
      - ".submeta"
      - "[data-component='nav3']"
      - ".content__meta-container"
    metadata:
      author_selector: "[rel='author']"
      published_selector: "time[datetime]"
```

**New York Times**:
```yaml
- id: nytimes
  priority: 90
  trigger:
    host:
      ends_with: "nytimes.com"
  actions:
    remove:
      - ".ad"
      - "#story-footer"
      - ".supplemental"
      - "[data-testid='photoviewer-wrapper']"
    metadata:
      author_selector: "[itemprop='author']"
      published_selector: "time[datetime]"
```

---

## Conclusion

This plan transforms the web-save skill from a simple Jina API wrapper into a sophisticated, extensible parsing system that rivals GoodLinks' quality while optimizing for AI consumption.

**Key Advantages**:
- **Full control** over extraction quality
- **Zero API costs** (eliminate Jina dependency)
- **Rich metadata** optimized for AI assistants
- **Extensible rules** for continuous quality improvement
- **Backward compatible** with existing database schema
- **Future-proof** architecture supporting advanced features

By following this phased implementation, you'll achieve production-quality parsing in **6 weeks** while maintaining system stability and allowing iterative refinement based on real-world usage.
