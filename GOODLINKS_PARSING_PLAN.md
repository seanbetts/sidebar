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

### Implementation Status (2026-01-05)

- ✅ Phase 1 (Core Local Parsing) implemented: local fetch + Readability + Markdown + frontmatter, image normalization, YouTube embed tracking.
- ✅ Phase 2 (JavaScript Rendering) implemented: Playwright rendering with auto/force/never controls and per-rule wait/timeout.
- ✅ Phase 3 (Rule Engine) implemented: schema, actions, include reinsertion, discard handling, rendering controls.
- ✅ Phase 4 (Auto-Tagging & Enrichment) implemented: tags + reading time in frontmatter.
- ✅ Phase 5 (Migration Script) implemented and run: 144 migrated / 46 failed (left unchanged).
- ✅ Parallel running (`WEB_SAVE_MODE=compare`) implemented for side-by-side logging.
- ✅ GoodLinks test corpus + comparison harness added for regression tracking.
- ⏳ Gradual rollout not started: local default + Jina fallback still pending.
- ⏳ Full migration to local-only (remove Jina dependencies) pending.
- ⏳ Manual testing checklist pending (paywalled, JS-heavy, long-form, media-heavy).
- ⏳ Image/link parity tuning still in progress (extra images/links vs. GoodLinks).

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

## Conceptual Model: Deterministic Reshaping, Not Understanding

**Critical Philosophy**: This parsing system is **not trying to "understand" web pages**. It is **deterministically reshaping the DOM** using:

1. **A trusted baseline extractor** (Arc90 Readability)
2. **A small number of explicit rules** (declarative YAML)
3. **Applied in a predictable order** (pre-phase → Readability → post-phase)

### Why This Mental Model Matters

**Engineering, Not Inference**:
- We don't use heuristics to "guess" article boundaries
- We don't use ML models to "interpret" page structure
- We use deterministic DOM transformations that work the same way every time

**Scales Cleanly**:
- Most pages (90%+) require **zero custom rules**
- A small minority (10%) benefit from **targeted, cheap fixes**
- Rules are **site-specific** or **platform-specific**, not page-specific

**Debuggable & Inspectable**:
- Every transformation is explicit in YAML
- Rule matches are logged in `metadata_` for analysis
- No black-box AI making unpredictable decisions

**This is why GoodLinks works so well**: It treats parsing as an **engineering problem** with **deterministic solutions**, not a pattern recognition problem requiring constant retraining.

---

## Key Architectural Alignments with GoodLinks

This implementation plan closely mirrors GoodLinks' proven architecture in these critical ways:

### 1. **Two-Phase Rule Application**

**GoodLinks Behavior**: Rules run both before and after Readability extraction.

**Our Implementation**:
- **Phase: pre** - Runs on raw HTML before Readability
  - Use case: Structural overrides (wrapper, article selectors)
  - Use case: Remove elements that confuse Readability
  - Use case: Force JS rendering for specific sites
- **Phase: post** - Runs on Readability's extracted HTML
  - Use case: Clean up leftover junk
  - Use case: Transform elements (retag, wrap, unwrap)
  - Use case: Extract metadata overrides

### 2. **Complete Rule Primitive Support**

**GoodLinks Fields** → **Our YAML Schema**:
- `a` (article root) → `selector_overrides.article`
- `we` (wrapper element) → `selector_overrides.wrapper`
- `e` (remove) → `remove: [...]`
- `i` (include) → `include: [...]`
- `ac` (actions) → `actions: [{op: ..., selector: ..., ...}]`
- `m` (metadata) → `metadata: {author: {...}, published: {...}}`
- `ea` (entire article) → Phase context
- `d` (discard) → `discard: bool`

**Supported Actions** (matching GoodLinks capability):
- `retag` - Change element tag names
- `wrap` - Wrap elements in containers
- `unwrap` - Remove wrapper, keep children
- `move` - Move elements to different parents
- `remove_attrs` - Strip attributes
- `replace_with_text` - Replace with text template

### 3. **Host Normalization & Matching (Robust)**

**GoodLinks Approach**: MD5 hashing of normalized hosts + flexible matching.

**Our Implementation** (supports www variants and eTLD+1 fallback):

```python
def normalize_host(url: str) -> Dict[str, str]:
    """
    Normalize host into multiple variants for matching.

    Returns:
        {
            "host_raw": "www.example.com",
            "host_nw": "example.com",       # Primary (no-www)
            "host_with_www": "www.example.com",
            "etld_plus_one": "example.com"  # For rules that opt in
        }
    """
    from urllib.parse import urlparse

    netloc = urlparse(url).netloc.lower()

    # Strip port if present
    if ':' in netloc:
        netloc = netloc.split(':')[0]

    host_raw = netloc
    host_nw = netloc.lstrip("www.")
    host_with_www = f"www.{host_nw}" if not netloc.startswith("www.") else netloc

    # eTLD+1 extraction (optional, for domain family matching)
    parts = host_nw.split('.')
    if len(parts) >= 2:
        etld_plus_one = '.'.join(parts[-2:])  # "example.com"
    else:
        etld_plus_one = host_nw

    return {
        "host_raw": host_raw,
        "host_nw": host_nw,
        "host_with_www": host_with_www,
        "etld_plus_one": etld_plus_one
    }
```

**Trigger Options**:
- `host.equals` - Exact match against `host_nw` (primary)
- `host.equals_www` - Exact match against `host_with_www`
- `host.ends_with` - Domain family matching (tries `host_nw`, then `etld_plus_one`)
- `host.etld_plus_one` - Match eTLD+1 only (e.g., `example.com` matches `blog.example.com`)

**Matching Logic**:
```python
def _rule_matches_host(self, rule: Dict, host_variants: Dict) -> bool:
    """Match host triggers with robustness."""
    host_config = rule.get('trigger', {}).get('host', {})

    if not host_config:
        return False

    # Exact match (no-www primary)
    if 'equals' in host_config:
        if host_config['equals'] == host_variants["host_nw"]:
            return True

    # Exact match (with-www)
    if 'equals_www' in host_config:
        if host_config['equals_www'] == host_variants["host_with_www"]:
            return True

    # Ends-with (tries no-www first, then eTLD+1)
    if 'ends_with' in host_config:
        target = host_config['ends_with']
        if host_variants["host_nw"].endswith(target):
            return True
        # Fallback to eTLD+1 for subdomain matching
        if host_variants["etld_plus_one"].endswith(target):
            return True

    # eTLD+1 matching (opt-in only)
    if 'etld_plus_one' in host_config:
        if host_config['etld_plus_one'] == host_variants["etld_plus_one"]:
            return True

    return False
```

**Why This Matters**:
- A single rule for `theguardian.com` matches `www.theguardian.com`, `theguardian.com`
- Rules can explicitly target `www.` hosts when needed (e.g., `www.reddit.com` vs `old.reddit.com`)
- Subdomain matching works: `example.com` rule can match `blog.example.com` via `etld_plus_one`
- Robust against host normalization edge cases

### 4. **Pure DOM Signature Rules**

**GoodLinks Finding**: Many rules trigger on DOM patterns alone, not URLs.

**Our Implementation**: Platform rules use only `dom` triggers:
```yaml
- id: swiper-carousel
  phase: post
  trigger:
    dom:
      any: [".swiper-slide-duplicate"]  # No host constraint
  remove: [".swiper-slide-duplicate"]
```

This allows rules to work across **any site** using Swiper, Squarespace, WordPress, etc.

### 5. **Rule Matching on Correct DOM**

**Critical Detail**: Pre-rules match against raw DOM, post-rules against Readability output.

**Our Implementation**:
```python
# Pre-phase: match on raw HTML
pre_rules, context = rule_engine.match_rules(url, raw_html, phase='pre')

# Post-phase: match on Readability's clean HTML
post_rules, _ = rule_engine.match_rules(url, readability_html, phase='post')
```

This prevents false matches and ensures selectors work reliably.

### 6. **Minimal Operational Metadata**

**Philosophy**: No debugging metadata or rule tracking. Keep database clean and focused.

**Stored in metadata_ JSONB** (minimal operational fields only):
```json
{
  "parser_version": "1.0",
  "used_js_rendering": true,
  "content_hash": "a1b2c3d4e5f6g7h8"
}
```

**What We Store**:
- `parser_version` - For migration tracking
- `used_js_rendering` - Operational flag (did we use Playwright?)
- `content_hash` - For deduplication

**What We Don't Store**:
- ❌ Matched rule IDs
- ❌ Rule signatures
- ❌ DOM selector matches
- ❌ Action counts
- ❌ Debug flags

**Rationale**: The output is the truth. If parsing failed, fix the rules and re-parse. No need for per-save debugging artifacts.

### 7. **Image Format & Caption Preservation**

**Requirement**: `[![alt](url)](url)` format with preserved captions.

**Our Implementation**:
```python
class CustomMarkdownConverter(MarkdownConverter):
    def convert_img(self, el, text, convert_as_inline):
        return f'[![{alt}]({src})]({src})'

    def convert_figure(self, el, text, convert_as_inline):
        content = text
        if figcaption:
            content += f'\n\n*{caption_text}*'
        return content
```

**Output**:
```markdown
[![Image description](https://example.com/image.jpg)](https://example.com/image.jpg)

*Original caption from article*
```

This gives Claude both the image reference and contextual caption text.

### 8. **Metadata Extraction Priority**

**GoodLinks Behavior**: Rule overrides win over generic extraction.

**Our Implementation**:
```python
# 1. Extract generic metadata
meta = metadata.extract_metadata(html, url)

# 2. Apply rule overrides (highest priority)
meta.update(rule_metadata_overrides)
```

**Priority Order**:
1. Rule overrides (`metadata:` in rules)
2. JSON-LD structured data
3. OpenGraph / Twitter meta tags
4. Generic meta tags
5. Fallback heuristics

### What We've Improved Beyond GoodLinks

1. **Explicit YAML Schema**: More readable than GoodLinks' compact JSON
2. **Phase Labels**: Clear `pre`/`post`/`both` vs. implicit behavior
3. **Hard Rendering Control**: Per-rule JS rendering with `mode: auto|force|never`
4. **Rich Frontmatter**: YAML frontmatter optimized for AI consumption
5. **Minimal Metadata**: Clean database with only operational fields (no debug clutter)
6. **Trigger Mode Control**: Explicit `mode: any` for platform rules that should fire on DOM signature alone
7. **Text Contains Triggers**: `dom.any_text_contains` for string-based matching
8. **Structured Discard**: Discarded content returns Markdown with `discarded: true` in frontmatter
9. **Hero Image Extraction**: Deterministic priority (in-article → og:image → twitter:image)
10. **Include Reinsertion**: Complete v1 with smart anchoring (text similarity → position → heading → append)
11. **Robust Host Matching**: Handles www variants, eTLD+1, subdomain matching with explicit opt-in
12. **Text/Markdown Output**: Clean API contract (input: URL, output: Markdown)

---

## Critical Implementation Details (Final Fixes)

### 1. **selector_overrides (we / a) Are Hard Scoping Constraints**

**GoodLinks Fields**: `we` (wrapper), `a` (article root)

**Critical Invariant**: Scoping is enforced as a **hard constraint in both phases**.

**Pre-Phase** (before Readability):
- If `wrapper` or `article` is defined, **extract that subtree** from the DOM
- Wrap in minimal document structure
- Pass ONLY the scoped subtree to Readability
- Readability **never sees content outside the scope**

**Post-Phase** (after Readability):
- All transforms and removals **operate within the scoped subtree only**
- If a `wrapper`/`article` was applied in pre-phase, post-phase rules respect that boundary

**Implementation**:

```python
# PRE-PHASE: Scope HTML before Readability
if phase == 'pre' and 'selector_overrides' in rule:
    overrides = rule['selector_overrides']

    # Prefer article over wrapper
    scope_selector = overrides.get('article') or overrides.get('wrapper')

    if scope_selector:
        try:
            scoped_elems = tree.cssselect(scope_selector)
            if scoped_elems:
                # HARD CONSTRAINT: Replace tree with scoped element
                scoped_elem = scoped_elems[0]

                # Create minimal wrapper
                new_doc = lxml_html.Element('html')
                body = lxml_html.SubElement(new_doc, 'body')
                body.append(scoped_elem)
                tree = new_doc

                # Readability sees ONLY this scope
                metadata_overrides['scoped_to'] = scope_selector
        except Exception:
            pass

# POST-PHASE: All transforms respect scoping
# (Post-phase rules operate on Readability output, which is already scoped)
```

**Why This Matters**:
- WSJ paywall rules: Scope to `#main-content`, ignore entire paywall scaffold
- Medium: Scope to `.article-content`, ignore sidebars/ads
- "we-only" rules (rules with ONLY a wrapper selector) work because scoping alone changes what Readability extracts

**This is a requirement for GoodLinks-parity**: Without scoping as a hard constraint, many real-world rules become inert.

### 2. **include Reinsertion (v1 Complete Implementation)**

**Problem**: `elem.set('data-include', 'true')` does nothing for Readability. GoodLinks' `i` field forces content back into the extracted article.

**Solution**: Complete post-extraction reinsertion pipeline.

**Implementation**:

```python
def apply_include_reinsertion(
    extracted_html: str,
    original_dom: Element,
    include_selectors: List[str],
    removal_rules: List[str]
) -> str:
    """
    Reinsert forcibly included elements after Readability extraction.

    Args:
        extracted_html: Clean HTML from Readability
        original_dom: Saved copy of pre-Readability DOM
        include_selectors: List of CSS selectors to force include
        removal_rules: Removal selectors to sanitize included elements

    Returns:
        Modified extracted HTML with reinserted elements
    """
    from lxml import html as lxml_html

    extracted_tree = lxml_html.fromstring(extracted_html)

    for selector in include_selectors:
        try:
            # Find matching nodes in original DOM
            included_nodes = original_dom.cssselect(selector)

            for node in included_nodes:
                # Clone the node
                cloned = deepcopy(node)

                # Sanitize with removal rules (same as main pipeline)
                for removal_selector in removal_rules:
                    for elem in cloned.cssselect(removal_selector):
                        parent = elem.getparent()
                        if parent is not None:
                            parent.remove(elem)

                # Find insertion point in extracted content
                # Strategy (in priority order):
                # 1. Match by text similarity to surrounding content
                # 2. Match by original DOM position
                # 3. Insert after nearest preceding heading
                # 4. Append to body

                insertion_target = find_insertion_point(
                    extracted_tree,
                    cloned,
                    original_dom,
                    node
                )

                if insertion_target:
                    parent, index = insertion_target
                    parent.insert(index, cloned)
                else:
                    # Fallback: append to body
                    body = extracted_tree.find('.//body')
                    if body is not None:
                        body.append(cloned)
                    else:
                        extracted_tree.append(cloned)
        except Exception:
            # Failed to reinsert - log but don't crash pipeline
            continue

    return lxml_html.tostring(extracted_tree, encoding='unicode')


def find_insertion_point(
    extracted_tree: Element,
    cloned_node: Element,
    original_dom: Element,
    original_node: Element
) -> Optional[Tuple[Element, int]]:
    """
    Find optimal insertion point for included element.

    Strategy (in priority order):
    1. Text similarity to surrounding content
    2. Original DOM position matching
    3. Nearest preceding heading
    4. None (caller appends to body)

    Returns:
        (parent, index) or None
    """
    from difflib import SequenceMatcher

    # Get text content of node to insert
    node_text = cloned_node.text_content().strip()[:200]  # First 200 chars

    if not node_text:
        # No text content - fallback to position-based
        return find_by_position(extracted_tree, original_dom, original_node)

    # Strategy 1: Text similarity
    # Find elements in extracted content with similar text
    best_match = None
    best_ratio = 0.3  # Minimum similarity threshold

    for elem in extracted_tree.iter():
        if elem.tag in ('script', 'style', 'meta', 'link'):
            continue

        elem_text = elem.text_content().strip()[:200]
        if not elem_text:
            continue

        # Calculate similarity
        ratio = SequenceMatcher(None, node_text, elem_text).ratio()

        if ratio > best_ratio:
            best_ratio = ratio
            best_match = elem

    if best_match is not None:
        # Insert after best match
        parent = best_match.getparent()
        if parent is not None:
            index = parent.index(best_match) + 1
            return (parent, index)

    # Strategy 2: Original DOM position
    position_match = find_by_position(extracted_tree, original_dom, original_node)
    if position_match:
        return position_match

    # Strategy 3: Nearest preceding heading
    headings = extracted_tree.cssselect('h1, h2, h3, h4, h5, h6')
    if headings:
        last_heading = headings[-1]
        parent = last_heading.getparent()
        if parent is not None:
            index = parent.index(last_heading) + 1
            return (parent, index)

    # Strategy 4: No good match, return None (caller appends)
    return None


def find_by_position(
    extracted_tree: Element,
    original_dom: Element,
    original_node: Element
) -> Optional[Tuple[Element, int]]:
    """
    Find insertion point by matching original DOM position.

    Look for preceding sibling in original DOM,
    find that sibling in extracted DOM,
    insert after it.

    Returns:
        (parent, index) or None
    """
    # Find preceding sibling with meaningful text
    preceding = original_node.getprevious()
    while preceding is not None:
        preceding_text = preceding.text_content().strip()[:100]
        if preceding_text and len(preceding_text) > 20:
            # Found meaningful preceding sibling
            # Try to find it in extracted DOM
            for elem in extracted_tree.iter():
                elem_text = elem.text_content().strip()[:100]
                if preceding_text in elem_text or elem_text in preceding_text:
                    # Found match - insert after this element
                    parent = elem.getparent()
                    if parent is not None:
                        index = parent.index(elem) + 1
                        return (parent, index)
            break  # Don't search further back
        preceding = preceding.getprevious()

    return None
```

**Pipeline Integration**:
1. **Pre-phase**: Collect `include` selectors from matched rules
2. **Before Readability**: Save parsed copy of original DOM
3. **After Readability**: Reinsert included elements with sanitization
4. **Post-phase rules**: Operate on DOM with reinserted elements

**Deterministic & Safe**:
- Sanitization uses same removal rules as main pipeline
- **Smart insertion anchoring** (4-level strategy):
  1. Text similarity matching (finds semantically related content)
  2. Original DOM position matching (preserves relative placement)
  3. Nearest preceding heading (structural anchor)
  4. Append to body (safe fallback)
- Never crashes (exceptions caught and logged)
- No `data-include` tagging (Readability ignores it anyway)

### 3. **Smart Include Insertion Anchoring**

**Why This Matters**: Simply appending included elements to the end of extracted content can place them semantically far from where they belong (e.g., a pull quote that should be mid-article ends up at the bottom).

**4-Level Anchoring Strategy** (in priority order):

1. **Text Similarity Matching**:
   - Compare first 200 chars of included element to all elements in extracted content
   - Use `SequenceMatcher` to find best match (threshold: 0.3 similarity)
   - Insert after best match
   - **Best for**: Elements with unique text content

2. **Original DOM Position Matching**:
   - Find preceding sibling in original DOM with meaningful text (>20 chars)
   - Search for that sibling in extracted content
   - Insert after matching sibling
   - **Best for**: Preserving relative placement when structure is maintained

3. **Nearest Preceding Heading**:
   - Find last heading (h1-h6) in extracted content
   - Insert after it
   - **Best for**: Structural anchoring when semantic matching fails

4. **Append to Body**:
   - Safe fallback that never crashes
   - **Best for**: When all else fails

**Benefits**:
- Semantically correct placement in most cases
- Preserves article flow and readability
- Degrades gracefully (always succeeds)

### 4. **Trigger Mode: any vs all**

**Problem**: Original logic required BOTH host AND dom to match if both specified. This is too strict for platform rules that should fire on DOM signature alone (e.g., Swiper on any site).

**Solution**: Added `trigger.mode`:

```yaml
# Platform rule - fires on ANY site with Swiper
- id: swiper-carousel
  phase: post
  trigger:
    mode: any  # Fire if dom OR host matches (dom is enough)
    dom:
      any: [".swiper-slide-duplicate"]
  remove: [".swiper-slide-duplicate"]
```

**Default**: `mode: all` (both must match, backward compatible).

### 4. **Text-Based Triggers**

**Added**: `dom.any_text_contains` for string matching:

```yaml
- id: amp-detector
  phase: pre
  trigger:
    dom:
      any_text_contains: ["⚡ AMP", "Accelerated Mobile Page"]
  # Handle AMP pages specially
```

**Use Case**: Detect AMP pages, regional variants, or content types by text tokens when CSS selectors are unreliable.

### 5. **Discard Returns Structured Frontmatter**

**Problem**: Discard returned empty string with no context.

**Solution**: Generates YAML frontmatter explaining discard:

```yaml
---
source: https://example.com/spam
domain: example.com
discarded: true
reason: Content discarded by rule
rule_id: spam-detector
saved_at: 2025-03-19T10:00:00Z
---

[Content discarded by parsing rule]
```

**Behavior**: Discarded content is:
- Saved to database with minimal record
- Auto-archived for review
- Flagged in `metadata_['discarded']`
- Returned with `discarded: true` in API response

---

## Target Architecture for SideBar

### Overview

```
URL
 ↓
[Fetch HTML (requests)]
 ↓
[JS Rendering? (Playwright)] ← Optional, per-rule or heuristic
 ↓
[Host Normalization (raw + no-www)]
 ↓
[PHASE 1: PRE-READABILITY RULES]
  ├─ Match rules (host + DOM signature on raw HTML)
  ├─ Apply structural overrides (wrapper, article selectors)
  ├─ Remove interfering elements
  └─ Log matched pre-rules
 ↓
[Readability extraction (readability-lxml)]
 ↓
[PHASE 2: POST-READABILITY RULES]
  ├─ Match rules (host + DOM signature on clean HTML)
  ├─ Remove leftover junk
  ├─ Transform elements (retag, wrap, unwrap)
  ├─ Extract metadata overrides
  └─ Log matched post-rules
 ↓
[Metadata extraction & enrichment]
  ├─ Rule overrides (highest priority)
  ├─ JSON-LD structured data
  ├─ OpenGraph / Twitter meta
  ├─ Generic meta tags
  └─ Fallback heuristics
 ↓
[Markdown conversion with custom image handler]
 ↓
[YAML frontmatter assembly]
 ↓
[Store matched rules in metadata_ JSONB]
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
hero_image: https://example.com/images/hero.jpg
tags: [technology, ai]
saved_at: 2025-03-19T10:30:00Z
---

[![Article hero image](https://example.com/images/hero.jpg)](https://example.com/images/hero.jpg)

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
| `hero_image` | URL | First image in content → og:image | No |
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

**Status (2026-01-05)**:
- ✅ Local parsing pipeline implemented (fetch → Readability → Markdown → frontmatter).
- ✅ Metadata extraction (title/author/published/canonical/image).
- ✅ Image normalization and hero image inclusion.
- ✅ YouTube embed tracking in markdown output.

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
       - hero_image (first image from content, fallback to og:image)

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
           "hero_image": (
               meta.get("og:image") or
               meta.get("twitter:image")
           ),
           # ... more fields
       }

   def extract_hero_image(
       readability_html: str,
       fallback_og_image: Optional[str]
   ) -> Optional[str]:
       """
       Extract hero/featured image for the article.

       Strategy:
       1. If Readability kept at least one image → use first as hero
       2. Else: Fall back to OpenGraph og:image
       3. Validate URL exists (basic check)

       Args:
           readability_html: HTML content after Readability extraction
           fallback_og_image: OpenGraph image URL from metadata

       Returns:
           Hero image URL or None
       """
       from lxml import html as lxml_html

       tree = lxml_html.fromstring(readability_html)

       # Try to find first image in Readability output
       images = tree.cssselect('img')
       if images:
           first_img_src = images[0].get('src')
           if first_img_src:
               # Basic validation: check if URL looks valid
               if first_img_src.startswith(('http://', 'https://', '//')):
                   return first_img_src

       # Fallback to OpenGraph image
       if fallback_og_image:
           if fallback_og_image.startswith(('http://', 'https://')):
               return fallback_og_image

       return None
   ```

6. **Implement `markdown.py`** (with custom image handler):
   ```python
   from markdownify import MarkdownConverter
   from lxml import html as lxml_html

   class CustomMarkdownConverter(MarkdownConverter):
       """
       Custom markdown converter with proper image and caption handling.
       """
       def convert_img(self, el, text, convert_as_inline):
           """
           Convert images to [![alt](url)](url) format.

           This allows images to be both displayed and clickable to full size.
           """
           alt = el.get('alt', '') or ''
           src = el.get('src', '') or ''
           title = el.get('title', '') or ''

           if not src:
               return ''

           # Format: [![alt](src)](src)
           # This makes images clickable to view full size
           if title:
               return f'[![{alt}]({src} "{title}")]({src})'
           else:
               return f'[![{alt}]({src})]({src})'

       def convert_figure(self, el, text, convert_as_inline):
           """
           Convert <figure> elements with captions.

           Output format:
           [![alt](url)](url)

           *Caption text*
           """
           # Process the figure's content normally
           content = text

           # Look for figcaption
           figcaption = el.find('.//figcaption')
           if figcaption is not None:
               caption_text = figcaption.text_content().strip()
               if caption_text:
                   content += f'\n\n*{caption_text}*'

           return content + '\n\n'

   def html_to_markdown(html: str) -> str:
       """
       Convert HTML to clean markdown with custom image handling.

       Features:
       - Images as [![alt](url)](url) for click-to-view
       - Preserved figcaptions as italic text
       - Clean heading hierarchy
       - Stripped scripts, styles, ads
       """
       converter = CustomMarkdownConverter(
           heading_style="ATX",
           bullets="-",
           code_language="",
           strip=['script', 'style', 'meta', 'link', 'noscript']
       )

       return converter.convert(html)
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

       # 4. Extract hero image (from Readability output, fallback to OG)
       hero_image = metadata.extract_hero_image(
           article["content"],
           meta.get("hero_image")
       )

       # 5. Convert to markdown
       md_content = markdown.html_to_markdown(article["content"])

       # 6. Prepend hero image to content if found
       if hero_image:
           # Add clickable hero image at top of content
           hero_markdown = f'[![Article hero image]({hero_image})]({hero_image})\n\n'
           md_content = hero_markdown + md_content

       # 7. Calculate word count
       word_count = len(md_content.split())

       # 8. Generate frontmatter
       fm_data = {
           "source": final_url,
           "title": article["title"] or meta["title"],
           "author": meta.get("author"),
           "published_date": meta.get("published_date"),
           "domain": urlparse(final_url).netloc,
           "word_count": word_count,
           "hero_image": hero_image,  # Include in frontmatter
           "tags": [],  # TODO: Auto-tagging in Phase 3
           "saved_at": datetime.now(timezone.utc).isoformat()
       }
       fm = frontmatter.generate_frontmatter(fm_data)

       # 9. Combine frontmatter + content
       full_content = fm + "\n" + md_content

       # 10. Save to database
       db = SessionLocal()
       set_session_user_id(db, user_id)
       try:
           website = WebsitesService.upsert_website(
               db,
               user_id,
               url=normalize_url(final_url),
               url_full=final_url,
               title=fm_data["title"],
               content=full_content,  # Now includes frontmatter + hero image
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

**Status (2026-01-05)**:
- ✅ Playwright rendering support with auto/force/never modes.
- ✅ JS rendering heuristics + per-rule wait/timeout settings.

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

**Status (2026-01-05)**:
- ✅ Rule schema implemented: `phase`, `priority`, `trigger` (host/dom, any/all, text contains), `selector_overrides`, `remove`, `include`, `actions`, `metadata`.
- ✅ Rule engine supports host variants (no-www, www, eTLD+1) and trigger `mode: any`.
- ✅ Action support implemented: retag, wrap/unwrap/remove_container, remove_parent/remove_outer_parent/remove_to_parent, move (append/prepend/before/after), remove_attrs, set_attr, replace_with_text, group_siblings, reorder.
- ✅ Metadata overrides applied post-extraction (title/author/published).
- ✅ Starter rulesets added and expanded (common/news/platforms/docs/social + top GoodLinks domains).
- ✅ Rendering controls (`rendering` block) implemented.
- ✅ Include reinsertion logic implemented.
- ✅ Discard flag handling implemented.

1. **Design Rule Schema** (Aligned with GoodLinks Architecture):

   **Rule Schema Fields** (matching GoodLinks primitives):

   ```yaml
   - id: string              # Unique rule identifier
     phase: pre|post|both    # When to apply:
                             # pre = before Readability (on raw/rendered DOM)
                             # post = after Readability (on extracted content)
                             # both = run in both phases
     priority: int           # Higher = runs first (within phase)

     # Triggering (host OR dom OR both)
     trigger:
       mode: all|any                     # all = both must match, any = either matches (default: all)
       host:
         equals: "domain.com"            # Exact match against host_nw (primary, no-www)
         equals_www: "www.domain.com"    # Exact match against host_with_www (explicit www)
         ends_with: "domain.com"         # Suffix match (tries host_nw, then eTLD+1)
         etld_plus_one: "domain.com"     # eTLD+1 only (opt-in for subdomain matching)
       dom:
         any: [".selector"]              # Match if ANY selector exists
         all: [".selector"]              # Match if ALL selectors exist
         any_text_contains: ["token"]    # Match if text content contains any token

     # Rendering control (optional)
     rendering:
       mode: auto|force|never        # JS rendering decision
                                     # auto = use heuristic (default)
                                     # force = always render with Playwright
                                     # never = never use JS, even if heuristic suggests it
       wait_for: ".selector"         # Wait for selector before continuing (force mode)
       timeout: int                  # Override default timeout (ms)

     # Selector overrides (pre-Readability only)
     selector_overrides:
       wrapper: ".main-container"    # Wrapper element (GoodLinks 'we')
       article: "article"            # Article root (GoodLinks 'a')

     # Simple removals (both phases)
     remove: [".selector"]           # Elements to remove (GoodLinks 'e')

     # Force inclusions (both phases)
     include: [".selector"]          # Force include (GoodLinks 'i')

     # Complex transformations (both phases)
     # Actions are a mini-DSL for DOM manipulation, matching GoodLinks 'ac' field
     actions:
       # Tag manipulation
       - op: retag                   # Change tag name (GoodLinks 'rt')
         selector: ".class"
         tag: "figcaption"

       # Container operations
       - op: wrap                    # Wrap in container
         selector: "img"
         wrapper_tag: "figure"

       - op: unwrap                  # Remove wrapper, keep children (GoodLinks 'rc')
         selector: ".container"

       - op: remove_container        # Remove container, keep children (alias for unwrap)
         selector: ".wrapper"

       # Parent/ancestor operations
       - op: remove_parent           # Remove immediate parent (GoodLinks 'rp')
         selector: ".child"

       - op: remove_outer_parent     # Remove grandparent (GoodLinks 'rop')
         selector: ".child"

       - op: remove_to_parent        # Remove up to specific parent (GoodLinks 'rtp')
         selector: ".child"
         parent: ".ancestor"

       # Movement operations
       - op: move                    # Move to different parent (GoodLinks 't', 'tp')
         selector: ".child"
         target: ".new-parent"
         position: append|prepend|before|after  # Optional

       # Attribute operations
       - op: remove_attrs            # Strip attributes (GoodLinks 'ra')
         selector: "div"
         attrs: ["style", "class"]

       - op: set_attr                # Set attribute value
         selector: "a"
         attr: "target"
         value: "_blank"

       # Content operations
       - op: replace_with_text       # Replace with text template
         selector: "iframe"
         template: "[Embedded: {src}]"

       # Grouping operations (GoodLinks 'g', 'gs')
       - op: group_siblings          # Group consecutive siblings
         selector: "p.caption"
         wrapper_tag: "div"
         class: "caption-group"

       # Priority/ordering (GoodLinks 'p', 'ts')
       - op: reorder                 # Change element order
         selector: ".reorder-me"
         method: move_to_top|move_to_bottom

     # Metadata extraction overrides (both phases)
     metadata:                       # Metadata overrides (GoodLinks 'm')
       author:
         selector: ".byline"
         attr: null                  # Text content
       published:
         selector: "time"
         attr: "datetime"            # Attribute value
       title:
         selector: "h1.title"

     # Special flags
     discard: bool                   # Discard extraction entirely (GoodLinks 'd')
   ```

   **Example: Platform Rule (DOM Signature, Post-Readability)**
   ```yaml
   - id: swiper-carousel
     phase: post
     priority: 100
     trigger:
       dom:
         any: [".swiper-slide-duplicate"]
     remove: [".swiper-slide-duplicate"]
   ```

   **Example: Host Rule with Full Features (Pre + Post)**
   ```yaml
   - id: theguardian
     phase: post
     priority: 90
     trigger:
       host:
         equals: "theguardian.com"  # Matches both www.theguardian.com and theguardian.com
     remove:
       - "aside"
       - ".submeta"
       - "[data-component='nav3']"
     actions:
       - op: retag
         selector: ".dcr-immersive-article-header__headline"
         tag: "h1"
       - op: wrap
         selector: "figure img"
         wrapper_tag: "figure"
     metadata:
       author:
         selector: "[rel='author']"
       published:
         selector: "time"
         attr: "datetime"
   ```

   **Example: Pre-Readability Structural Rule**
   ```yaml
   - id: wsj-paywall
     phase: pre
     priority: 90
     trigger:
       host:
         ends_with: "wsj.com"
     selector_overrides:
       wrapper: "#main-content"
       article: "[itemprop='articleBody']"
     remove:
       - ".snippet"
       - ".wsj-snippet-login"
   ```

   **Example: JS Rendering Rule**
   ```yaml
   - id: react-docs
     phase: pre
     priority: 85
     trigger:
       host:
         equals: "react.dev"
     rendering:
       mode: force               # Always use Playwright for React docs
       wait_for: ".main-content"
       timeout: 45000
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
   from typing import List, Dict, Any, Tuple, Optional
   from lxml import html as lxml_html
   from lxml.etree import Element
   from urllib.parse import urlparse
   from pathlib import Path
   import yaml

   class RuleEngine:
       def __init__(self, rules_dir: Path):
           self.rules = self._load_rules(rules_dir)
           # Rules can be pre, post, or both
           self.pre_rules = [r for r in self.rules if r.get('phase') in ('pre', 'both')]
           self.post_rules = [r for r in self.rules if r.get('phase') in ('post', 'both')]

       def _load_rules(self, rules_dir: Path) -> List[Dict]:
           """Load all YAML rule files."""
           rules = []
           for file in rules_dir.glob("*.yaml"):
               with open(file) as f:
                   loaded = yaml.safe_load(f) or []
                   rules.extend(loaded)
           # Sort by priority (higher first)
           return sorted(rules, key=lambda r: r.get('priority', 50), reverse=True)

       def normalize_host(self, url: str) -> Dict[str, str]:
           """
           Normalize host into multiple variants for robust matching.

           Returns:
               {
                   "host_raw": "www.example.com",
                   "host_nw": "example.com",
                   "host_with_www": "www.example.com",
                   "etld_plus_one": "example.com"
               }
           """
           netloc = urlparse(url).netloc.lower()

           # Strip port if present
           if ':' in netloc:
               netloc = netloc.split(':')[0]

           host_raw = netloc
           host_nw = netloc.lstrip("www.")
           host_with_www = f"www.{host_nw}" if not netloc.startswith("www.") else netloc

           # eTLD+1 extraction
           parts = host_nw.split('.')
           if len(parts) >= 2:
               etld_plus_one = '.'.join(parts[-2:])
           else:
               etld_plus_one = host_nw

           return {
               "host_raw": host_raw,
               "host_nw": host_nw,
               "host_with_www": host_with_www,
               "etld_plus_one": etld_plus_one
           }

       def match_rules(
           self,
           url: str,
           html: str,
           phase: str
       ) -> Tuple[List[Dict], Dict[str, str]]:
           """
           Find all matching rules for URL and HTML in specified phase.

           Args:
               url: The URL being parsed
               html: The HTML content (raw for pre, Readability output for post)
               phase: 'pre' or 'post'

           Returns:
               (matched_rules, context)
               context = host variants for reference
           """
           tree = lxml_html.fromstring(html)
           host_variants = self.normalize_host(url)

           context = {
               "host_raw": host_variants["host_raw"],
               "host_nw": host_variants["host_nw"]
           }

           # Filter rules by phase
           rules = self.pre_rules if phase == 'pre' else self.post_rules

           matched = []
           for rule in rules:
               if self._rule_matches(rule, host_variants, tree):
                   matched.append(rule)

           return matched, context

       def _rule_matches(
           self,
           rule: Dict,
           host_variants: Dict[str, str],
           tree: Element
       ) -> bool:
           """Check if rule triggers match with robust host matching."""
           trigger = rule.get('trigger', {})

           # If no triggers specified, never match
           if not trigger:
               return False

           host_match = False
           dom_match = False

           # Host-based trigger (robust matching)
           if 'host' in trigger:
               host_config = trigger['host']

               # Exact match (no-www primary)
               if 'equals' in host_config:
                   if host_config['equals'] == host_variants["host_nw"]:
                       host_match = True

               # Exact match (with-www)
               if 'equals_www' in host_config:
                   if host_config['equals_www'] == host_variants["host_with_www"]:
                       host_match = True

               # Ends-with (tries no-www first, then eTLD+1)
               if 'ends_with' in host_config:
                   target = host_config['ends_with']
                   if host_variants["host_nw"].endswith(target):
                       host_match = True
                   # Fallback to eTLD+1 for subdomain matching
                   elif host_variants["etld_plus_one"].endswith(target):
                       host_match = True

               # eTLD+1 matching (opt-in only)
               if 'etld_plus_one' in host_config:
                   if host_config['etld_plus_one'] == host_variants["etld_plus_one"]:
                       host_match = True

           # DOM-based trigger
           if 'dom' in trigger:
               dom_config = trigger['dom']

               # Match if ANY selector exists
               if 'any' in dom_config:
                   for selector in dom_config['any']:
                       try:
                           if tree.cssselect(selector):
                               dom_match = True
                               break
                       except Exception:
                           continue

               # Match if ALL selectors exist
               if 'all' in dom_config:
                   try:
                       if all(tree.cssselect(sel) for sel in dom_config['all']):
                           dom_match = True
                   except Exception:
                       pass

               # Match if text content contains any token
               if 'any_text_contains' in dom_config:
                   try:
                       text_content = tree.text_content().lower()
                       for token in dom_config['any_text_contains']:
                           if token.lower() in text_content:
                               dom_match = True
                               break
                   except Exception:
                       pass

           # Trigger combination logic based on mode
           has_host_trigger = 'host' in trigger
           has_dom_trigger = 'dom' in trigger
           mode = trigger.get('mode', 'all')  # Default: all must match

           if has_host_trigger and has_dom_trigger:
               if mode == 'any':
                   return host_match or dom_match  # Either is sufficient
               else:  # mode == 'all'
                   return host_match and dom_match  # Both must match
           elif has_host_trigger:
               return host_match
           elif has_dom_trigger:
               return dom_match
           else:
               return False

       def apply_rules(
           self,
           html: str,
           rules: List[Dict],
           phase: str
       ) -> Tuple[str, Dict[str, Any]]:
           """
           Apply matched rules to HTML.

           Returns:
               (modified_html, extracted_metadata)
           """
           tree = lxml_html.fromstring(html)
           metadata_overrides = {}

           # Track elements to forcibly include (for post-extraction reinsertion)
           included_elements = []

           for rule in rules:
               # Check for discard flag
               if rule.get('discard'):
                   # Return minimal frontmatter indicating discard
                   discard_frontmatter = {
                       "discarded": True,
                       "reason": "Rule flagged content as discard",
                       "rule_id": rule.get('id')
                   }
                   return "", discard_frontmatter

               # Selector overrides (pre-phase only)
               # CRITICAL: Actually scope the HTML to wrapper/article
               if phase == 'pre' and 'selector_overrides' in rule:
                   overrides = rule['selector_overrides']

                   # Prefer article over wrapper
                   scope_selector = overrides.get('article') or overrides.get('wrapper')

                   if scope_selector:
                       try:
                           scoped_elems = tree.cssselect(scope_selector)
                           if scoped_elems:
                               # Replace tree with scoped element
                               # Wrap in minimal document structure
                               scoped_elem = scoped_elems[0]

                               # Create minimal wrapper
                               new_doc = lxml_html.Element('html')
                               body = lxml_html.SubElement(new_doc, 'body')
                               body.append(scoped_elem)
                               tree = new_doc

                               # Store for logging
                               metadata_overrides['scoped_to'] = scope_selector
                       except Exception:
                           pass

               # Simple removals
               if 'remove' in rule:
                   for selector in rule['remove']:
                       try:
                           for elem in tree.cssselect(selector):
                               parent = elem.getparent()
                               if parent is not None:
                                   parent.remove(elem)
                       except Exception:
                           continue

               # Force inclusions (collect selectors, reinsertion happens after Readability)
               if 'include' in rule:
                   # Store selectors for post-Readability reinsertion
                   if 'include_selectors' not in metadata_overrides:
                       metadata_overrides['include_selectors'] = []
                   metadata_overrides['include_selectors'].extend(rule['include'])

               # Complex actions
               if 'actions' in rule:
                   for action in rule['actions']:
                       self._apply_action(tree, action)

               # Metadata extraction overrides
               if 'metadata' in rule:
                   for field, config in rule['metadata'].items():
                       try:
                           selector = config.get('selector')
                           attr = config.get('attr')

                           elem = tree.cssselect(selector)
                           if elem:
                               value = elem[0].get(attr) if attr else elem[0].text_content()
                               metadata_overrides[field] = value.strip()
                       except Exception:
                           continue

           return lxml_html.tostring(tree, encoding='unicode'), metadata_overrides

       def _apply_action(self, tree: Element, action: Dict):
           """
           Apply individual transform action.

           This is a mini-DSL for DOM transformations, matching GoodLinks 'ac' field.
           Unknown operations log and no-op to ensure pipeline stability.
           """
           op = action.get('op')
           selector = action.get('selector')

           if not op or not selector:
               return

           try:
               elements = tree.cssselect(selector)
           except Exception:
               # Invalid selector - log and continue
               return

           # Tag manipulation
           if op == 'retag':
               new_tag = action.get('tag')
               if new_tag:
                   for elem in elements:
                       elem.tag = new_tag

           # Container operations
           elif op == 'wrap':
               wrapper_tag = action.get('wrapper_tag')
               wrapper_class = action.get('class')
               for elem in elements:
                   wrapper = lxml_html.Element(wrapper_tag)
                   if wrapper_class:
                       wrapper.set('class', wrapper_class)
                   parent = elem.getparent()
                   if parent is not None:
                       parent.insert(parent.index(elem), wrapper)
                       parent.remove(elem)
                       wrapper.append(elem)

           elif op in ('unwrap', 'remove_container'):
               # Remove wrapper, keep children (GoodLinks 'rc')
               for elem in elements:
                   parent = elem.getparent()
                   if parent is not None:
                       index = parent.index(elem)
                       for child in elem:
                           parent.insert(index, child)
                           index += 1
                       parent.remove(elem)

           # Parent/ancestor operations
           elif op == 'remove_parent':
               # Remove immediate parent (GoodLinks 'rp')
               for elem in elements:
                   parent = elem.getparent()
                   if parent is not None:
                       grandparent = parent.getparent()
                       if grandparent is not None:
                           index = grandparent.index(parent)
                           # Move children to grandparent
                           for child in parent:
                               grandparent.insert(index, child)
                               index += 1
                           grandparent.remove(parent)

           elif op == 'remove_outer_parent':
               # Remove grandparent (GoodLinks 'rop')
               for elem in elements:
                   parent = elem.getparent()
                   if parent is not None:
                       grandparent = parent.getparent()
                       if grandparent is not None:
                           great_grandparent = grandparent.getparent()
                           if great_grandparent is not None:
                               index = great_grandparent.index(grandparent)
                               # Move children to great-grandparent
                               for child in grandparent:
                                   great_grandparent.insert(index, child)
                                   index += 1
                               great_grandparent.remove(grandparent)

           elif op == 'remove_to_parent':
               # Remove up to specific parent (GoodLinks 'rtp')
               parent_selector = action.get('parent')
               if parent_selector:
                   for elem in elements:
                       current = elem.getparent()
                       while current is not None:
                           if current.cssselect(parent_selector):
                               # Found target parent, stop
                               break
                           parent_of_current = current.getparent()
                           if parent_of_current is not None:
                               index = parent_of_current.index(current)
                               for child in current:
                                   parent_of_current.insert(index, child)
                                   index += 1
                               parent_of_current.remove(current)
                           current = parent_of_current

           # Movement operations
           elif op == 'move':
               # Move to different parent (GoodLinks 't', 'tp')
               target_selector = action.get('target')
               position = action.get('position', 'append')
               target_elements = tree.cssselect(target_selector)

               if target_elements:
                   target = target_elements[0]
                   for elem in elements:
                       parent = elem.getparent()
                       if parent is not None:
                           parent.remove(elem)

                           if position == 'prepend':
                               target.insert(0, elem)
                           elif position == 'before':
                               target_parent = target.getparent()
                               if target_parent is not None:
                                   target_parent.insert(target_parent.index(target), elem)
                           elif position == 'after':
                               target_parent = target.getparent()
                               if target_parent is not None:
                                   target_parent.insert(target_parent.index(target) + 1, elem)
                           else:  # append (default)
                               target.append(elem)

           # Attribute operations
           elif op == 'remove_attrs':
               # Strip attributes (GoodLinks 'ra')
               attrs = action.get('attrs', [])
               for elem in elements:
                   for attr in attrs:
                       if attr in elem.attrib:
                           del elem.attrib[attr]

           elif op == 'set_attr':
               # Set attribute value
               attr = action.get('attr')
               value = action.get('value')
               if attr and value:
                   for elem in elements:
                       elem.set(attr, value)

           # Content operations
           elif op == 'replace_with_text':
               # Replace with text template
               template = action.get('template', '')
               for elem in elements:
                   text = template
                   for key, value in elem.attrib.items():
                       text = text.replace(f'{{{key}}}', value)

                   parent = elem.getparent()
                   if parent is not None:
                       text_elem = lxml_html.Element('p')
                       text_elem.text = text
                       parent.replace(elem, text_elem)

           # Grouping operations (GoodLinks 'g', 'gs')
           elif op == 'group_siblings':
               # Group consecutive siblings matching selector
               wrapper_tag = action.get('wrapper_tag', 'div')
               wrapper_class = action.get('class')

               if elements:
                   # Group consecutive matching elements
                   groups = []
                   current_group = [elements[0]]

                   for i in range(1, len(elements)):
                       prev_elem = elements[i-1]
                       curr_elem = elements[i]

                       # Check if consecutive siblings
                       if (prev_elem.getparent() == curr_elem.getparent() and
                           prev_elem.getnext() == curr_elem):
                           current_group.append(curr_elem)
                       else:
                           groups.append(current_group)
                           current_group = [curr_elem]

                   groups.append(current_group)

                   # Wrap each group
                   for group in groups:
                       if len(group) > 1:  # Only wrap if multiple siblings
                           first = group[0]
                           parent = first.getparent()
                           if parent is not None:
                               wrapper = lxml_html.Element(wrapper_tag)
                               if wrapper_class:
                                   wrapper.set('class', wrapper_class)

                               parent.insert(parent.index(first), wrapper)
                               for elem in group:
                                   parent.remove(elem)
                                   wrapper.append(elem)

           # Priority/ordering (GoodLinks 'p', 'ts')
           elif op == 'reorder':
               # Change element order
               method = action.get('method', 'move_to_top')
               for elem in elements:
                   parent = elem.getparent()
                   if parent is not None:
                       parent.remove(elem)
                       if method == 'move_to_top':
                           parent.insert(0, elem)
                       elif method == 'move_to_bottom':
                           parent.append(elem)

           # Unknown operation - log and no-op
           else:
               # In production, log: f"Unknown action operation: {op}"
               pass
   ```

4. **Integrate into Pipeline** (`save_url.py`):
   ```python
   from parsers.rule_engine import RuleEngine
   from parsers.include_reinsertion import apply_include_reinsertion

   # Initialize once (module-level)
   rule_engine = RuleEngine(Path(__file__).parent / "parsers" / "rules")

   def save_url_local(url: str, user_id: str) -> str:
       """
       Parse URL and return Markdown with YAML frontmatter.

       Args:
           url: URL to parse
           user_id: User ID for database storage

       Returns:
           text/markdown content (frontmatter + body)
       """
       # 1. Fetch HTML (with JS rendering control)
       html, final_url, used_js_rendering = fetch_with_rendering_control(
           url,
           rule_engine
       )

       # Save original DOM for include reinsertion
       from lxml import html as lxml_html
       original_dom = lxml_html.fromstring(html)

       all_metadata_overrides = {}
       include_selectors = []
       removal_selectors = []

       # 2. PHASE 1: PRE-READABILITY RULES
       pre_rules, context = rule_engine.match_rules(final_url, html, phase='pre')

       if pre_rules:
           html, pre_metadata = rule_engine.apply_rules(html, pre_rules, phase='pre')

           # Collect include selectors
           if 'include_selectors' in pre_metadata:
               include_selectors.extend(pre_metadata['include_selectors'])

           # Collect removal selectors for sanitization
           for rule in pre_rules:
               if 'remove' in rule:
                   removal_selectors.extend(rule['remove'])

           # Check for discard
           if pre_metadata.get('discarded'):
               # Return Markdown with discard frontmatter
               discard_fm = frontmatter.generate_frontmatter({
                   "source": final_url,
                   "domain": context["host_nw"],
                   "discarded": True,
                   "discard_reason": pre_metadata.get('reason', 'Content discarded by parsing rule'),
                   "saved_at": datetime.now(timezone.utc).isoformat()
               })
               # Save to DB and return Markdown
               save_to_database(user_id, final_url, discard_fm + "\n", context, used_js_rendering)
               return discard_fm + "\n"

           all_metadata_overrides.update(pre_metadata)

       # 3. Readability extraction (sees scoped HTML if selector_overrides applied)
       article = readability.extract_article(html, final_url)

       # 4. Include reinsertion (if any include selectors collected)
       if include_selectors:
           article["content"] = apply_include_reinsertion(
               article["content"],
               original_dom,
               include_selectors,
               removal_selectors
           )

       # 5. PHASE 2: POST-READABILITY RULES (operate on DOM with reinserted elements)
       post_rules, _ = rule_engine.match_rules(final_url, article["content"], phase='post')

       if post_rules:
           article["content"], post_metadata = rule_engine.apply_rules(
               article["content"],
               post_rules,
               phase='post'
           )

           # Check for discard in post-phase
           if post_metadata.get('discarded'):
               discard_fm = frontmatter.generate_frontmatter({
                   "source": final_url,
                   "domain": context["host_nw"],
                   "discarded": True,
                   "discard_reason": post_metadata.get('reason', 'Content discarded by parsing rule'),
                   "saved_at": datetime.now(timezone.utc).isoformat()
               })
               save_to_database(user_id, final_url, discard_fm + "\n", context, used_js_rendering)
               return discard_fm + "\n"

           all_metadata_overrides.update(post_metadata)

       # 6. Extract metadata (rule overrides win)
       meta = metadata.extract_metadata(html, final_url)
       meta.update(all_metadata_overrides)

       # 7. Extract hero image (deterministic priority order)
       hero_image = extract_hero_image_deterministic(article["content"], meta)

       # 8. Convert to markdown
       md_content = markdown.html_to_markdown(article["content"])

       # 9. Prepend hero image if found
       if hero_image:
           hero_markdown = f'[![Hero]({hero_image})]({hero_image})\n\n'
           md_content = hero_markdown + md_content

       # 10. Generate frontmatter
       fm_data = {
           "source": final_url,
           "title": article["title"] or meta.get("title"),
           "author": meta.get("author"),
           "published_date": meta.get("published_date"),
           "domain": context["host_nw"],
           "word_count": len(md_content.split()),
           "hero_image": hero_image,
           "tags": [],  # TODO: Auto-tagging in Phase 4
           "saved_at": datetime.now(timezone.utc).isoformat()
       }
       fm = frontmatter.generate_frontmatter(fm_data)

       # 11. Combine frontmatter + content
       full_markdown = fm + "\n" + md_content

       # 12. Save to database
       save_to_database(user_id, final_url, full_markdown, context, used_js_rendering)

       # 13. Return Markdown (text/markdown)
       return full_markdown


   def fetch_with_rendering_control(url: str, rule_engine: RuleEngine) -> Tuple[str, str, bool]:
       """
       Fetch HTML with hard rendering.mode control flow.

       Returns:
           (html, final_url, used_js_rendering)
       """
       # Initial fetch
       html, final_url = fetcher.fetch_html(url)

       # Match rules to check rendering requirements
       pre_rules, _ = rule_engine.match_rules(final_url, html, phase='pre')

       # Determine rendering mode (HARD CONTROL FLOW)
       rendering_mode = 'auto'  # Default
       wait_for = None
       timeout = 30000

       for rule in pre_rules:
           if 'rendering' in rule:
               rule_mode = rule['rendering'].get('mode', 'auto')
               if rule_mode == 'force':
                   # Any rule with force → MUST use Playwright
                   rendering_mode = 'force'
                   wait_for = rule['rendering'].get('wait_for')
                   timeout = rule['rendering'].get('timeout', 30000)
                   break
               elif rule_mode == 'never':
                   # Any rule with never → NEVER use Playwright
                   rendering_mode = 'never'

       # Apply rendering logic
       used_js_rendering = False

       if rendering_mode == 'force':
           # MUST render with JS
           html, final_url = js_renderer.render_with_js(url, wait_for, timeout)
           used_js_rendering = True

       elif rendering_mode == 'auto':
           # Use heuristic only when all rules are auto
           if fetcher.requires_js_rendering(html):
               html, final_url = js_renderer.render_with_js(url)
               used_js_rendering = True

       # rendering_mode == 'never': already have HTML, don't render

       return html, final_url, used_js_rendering


   def extract_hero_image_deterministic(
       readability_html: str,
       meta: Dict[str, Any]
   ) -> Optional[str]:
       """
       Extract hero image with deterministic priority.

       Priority:
       1. First meaningful in-article image (post-rules)
       2. OpenGraph og:image
       3. Twitter twitter:image

       Returns:
           Hero image URL or None (URL only, no download/proxy)
       """
       from lxml import html as lxml_html

       tree = lxml_html.fromstring(readability_html)

       # Priority 1: First meaningful in-article image
       images = tree.cssselect('img')
       for img in images:
           src = img.get('src')
           if src and src.startswith(('http://', 'https://', '//')):
               # Basic validation: not a tracking pixel
               width = img.get('width')
               height = img.get('height')
               if width and height:
                   try:
                       if int(width) < 50 or int(height) < 50:
                           continue  # Skip tiny images
                   except ValueError:
                       pass
               return src

       # Priority 2: OpenGraph image
       og_image = meta.get("hero_image")  # Already extracted from og:image
       if og_image and og_image.startswith(('http://', 'https://')):
           return og_image

       return None


   def save_to_database(
       user_id: str,
       url: str,
       markdown_content: str,
       context: Dict,
       used_js_rendering: bool
   ):
       """
       Save parsed content to database.

       Stores minimal operational metadata only:
       - parser_version
       - used_js_rendering
       - content_hash (for deduplication)
       """
       # Parse frontmatter to extract title, published_date
       import yaml
       parts = markdown_content.split('---\n', 2)
       if len(parts) >= 3:
           fm_data = yaml.safe_load(parts[1])
       else:
           fm_data = {}

       db = SessionLocal()
       set_session_user_id(db, user_id)
       try:
           website = WebsitesService.upsert_website(
               db,
               user_id,
               url=normalize_url(url),
               url_full=url,
               title=fm_data.get("title", "[Untitled]"),
               content=markdown_content,
               source=url,
               saved_at=datetime.now(timezone.utc),
               published_at=parse_published_at(fm_data.get("published_date")),
               pinned=False,
               archived=fm_data.get("discarded", False),
           )

           # Minimal operational metadata only
           website.metadata_['parser_version'] = '1.0'
           website.metadata_['used_js_rendering'] = used_js_rendering
           website.metadata_['content_hash'] = hashlib.sha256(
               markdown_content.encode()
           ).hexdigest()[:16]

           db.commit()
       finally:
           db.close()
   ```

5. **Populate Initial Rules** (Updated with phase and proper schema):

   **`common.yaml`** (Platform rules - DOM signatures only):
   ```yaml
   # Post-Readability cleanup rules for common platforms

   - id: swiper-carousel
     phase: post
     priority: 100
     trigger:
       dom:
         any: [".swiper-slide-duplicate"]
     remove: [".swiper-slide-duplicate"]

   - id: squarespace
     phase: post
     priority: 95
     trigger:
       dom:
         any: [".sqs-block"]
     remove:
       - ".sqs-announcement-bar"
       - ".sqs-cookie-banner"
       - "[data-test='sqs-blocks-newsletter-form']"

   - id: cookie-banners
     phase: pre
     priority: 95
     trigger:
       dom:
         any:
           - "[class*='cookie-banner']"
           - "#onetrust-consent-sdk"
     remove:
       - "[class*='cookie-banner']"
       - "#onetrust-consent-sdk"
       - "[id*='cookie-notice']"

   - id: chat-widgets
     phase: pre
     priority: 90
     trigger:
       dom:
         any:
           - "#intercom-container"
           - "[id*='drift-widget']"
     remove:
       - "#intercom-container"
       - "[id*='drift-widget']"
       - ".crisp-client"
   ```

   **`news.yaml`** (Host-specific rules):
   ```yaml
   # News sites with specific handling

   - id: theguardian
     phase: post
     priority: 90
     trigger:
       host:
         equals: "theguardian.com"  # Matches www.theguardian.com too
     remove:
       - "aside"
       - ".submeta"
       - "[data-component='nav3']"
     actions:
       - op: retag
         selector: ".dcr-immersive-article-header__headline"
         tag: "h1"
     metadata:
       author:
         selector: "[rel='author']"
       published:
         selector: "time"
         attr: "datetime"

   - id: nytimes
     phase: post
     priority: 90
     trigger:
       host:
         ends_with: "nytimes.com"
     remove:
       - ".ad"
       - "#story-footer"
       - ".supplemental"
       - "[data-testid='photoviewer-wrapper']"
     metadata:
       author:
         selector: "[itemprop='author']"
       published:
         selector: "time"
         attr: "datetime"

   - id: wsj
     phase: pre
     priority: 90
     trigger:
       host:
         ends_with: "wsj.com"
     selector_overrides:
       wrapper: "#main-content"
       article: "[itemprop='articleBody']"
     remove:
       - ".snippet"
       - ".wsj-snippet-login"
   ```

   **`technical.yaml`** (Dev/docs sites):
   ```yaml
   # Technical and documentation sites

   - id: medium
     phase: post
     priority: 95
     trigger:
       dom:
         any: [".metabar", "[data-test='post-sidebar']"]
     remove:
       - ".metabar"
       - "aside"
       - ".pw-responses"
       - "[data-test='post-sidebar']"
     metadata:
       author:
         selector: "a[rel='author']"

   - id: devto
     phase: post
     priority: 90
     trigger:
       host:
         equals: "dev.to"
     remove:
       - ".crayons-article__aside"
       - "#comments-container"
     metadata:
       author:
         selector: ".crayons-article__header__meta a"

   - id: react-docs-js-required
     phase: pre
     priority: 85
     trigger:
       host:
         equals: "react.dev"
     rendering:
       js_required: true
       wait_for: ".main-content"
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

**Status (2026-01-05)**:
- ✅ Keyword-based tagging implemented.
- ✅ Reading time calculation implemented.
- ✅ Frontmatter updated with `tags`.

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

**Status (2026-01-05)**:
- ✅ Migration script implemented.
- ✅ Migration run completed (144 migrated / 46 failed, failures left unchanged).

**Create `backend/scripts/migrate_existing_websites.py`**:

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

### Regression Tracking (GoodLinks Corpus)

**Goal**: Track quality over time and spot regressions.

**Approach**:
- Use the GoodLinks corpus and `compare_goodlinks.py` output (`goodlinks-testing/comparison/summary.csv`).
- Append per-run metrics to `goodlinks-testing/comparison/history.csv` for trend tracking.
- Capture: timestamp, git commit, ok/failed counts, avg similarity, coverage ratios (cap at 1.0), and missing/extra counts (words/links/images/videos).

**Suggested Columns**:
```
run_at,git_sha,ok_count,error_count,avg_similarity,std_similarity,coverage_words,std_coverage_words,coverage_links,std_coverage_links,coverage_images,std_coverage_images,coverage_videos,std_coverage_videos,missing_words,extra_words,missing_links,extra_links,missing_images,extra_images,missing_videos,extra_videos
```

---

## Alignment With GoodLinks (Conversation Review)

### What We Already Match

- Readability-based extraction + deterministic post-rules.
- Two-phase rules (pre/post), include/removals, metadata overrides, rendering controls.
- Corpus comparison harness with similarity + coverage metrics.
- Playwright fallback for JS-heavy/blocked pages.

### Key Gaps Identified

- **GoodLinks ruleset parity**: `ck-rules.js` is the authoritative ruleset (≈56 rules). We are still hand-curating rules instead of importing the real set.
- **Rule action parity**: missing equivalents for GoodLinks actions (remove children, remove parent variants, move with target slot/index, remove attribute).
- **Canonical text output**: GoodLinks stores a text-first canonical snapshot (their `index.html`), while we compare Markdown structure directly.
- **Structure-level metrics**: we lack paragraph/list/code/blockquote/caption metrics for better clustering of failures.
- **Image/caption pairing**: need tighter handling to preserve captions with images.

### Next Tactics (Prioritized)

1) **Import and map `ck-rules.js`**  
   - Determine rule key hash (likely `md5(host)` or `md5(eTLD+1)`).
   - Convert rules into our YAML schema (article root, removals, includes, actions, metadata).
2) **Add missing action types**  
   - `remove_children` (GoodLinks `rc`)  
   - `remove_parent`/`remove_outer_parent` parity (GoodLinks `rp`)  
   - `move` with target slot/index (GoodLinks `ts`)  
   - `remove_attribute` (GoodLinks `ra`)  
3) **Canonical text comparison**  
   - Add a normalized text mode for comparison to better align with GoodLinks’ text-first snapshot.
4) **Structure metrics + clustering**  
   - Track paragraph/list/blockquote/code counts, caption associations, and add std dev for these metrics.
5) **Caption + figure pairing**  
   - Ensure `figure > img + figcaption` remains together in Markdown.

### Tests to Add (If Implementing Above)

- Action parity tests for new rule operations.
- Canonical text normalization tests.
- Caption pairing tests (figure + figcaption).
- Structure metrics tests (paragraph/list/blockquote counts).

**Usage**:
- Run comparison, then append summary row for that run.
- Use the history CSV to plot trends and detect regressions.

---

## Migration Strategy

### Phase 1: Parallel Running (Week 1-2)

- Implement local parsing alongside Jina
- Add flag to toggle between implementations
- Compare outputs side-by-side
- Validate quality improvements

**Status (2026-01-05)**:
- ✅ Added `WEB_SAVE_MODE` with `jina|local|compare`.
- ✅ Quick-save + skill save support compare logging for side-by-side output.

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
hero_image: https://example.com/images/hero.jpg
reading_time: 8 min
tags: [technology, ai, programming]
saved_at: 2025-03-19T15:30:00Z
---

[![Article hero image](https://example.com/images/hero.jpg)](https://example.com/images/hero.jpg)

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
