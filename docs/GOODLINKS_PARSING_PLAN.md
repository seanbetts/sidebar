# Building a GoodLinks-Style Webpage Parser for AI Ingestion

## Summary

This document describes how to build a GoodLinks-quality webpage parsing system for server-side use in a FastAPI environment, producing high-fidelity Markdown with YAML frontmatter suitable for direct ingestion by an AI assistant.

Through empirical analysis of GoodLinks' local storage, exported data, and runtime behaviour, we identified that GoodLinks' excellent results are not driven by machine learning or opaque heuristics, but by a carefully engineered, deterministic pipeline:

1. A strong baseline extractor (Arc90 Readability)
2. A small, declarative DOM rule engine
3. Dual triggering mechanisms:
   - Host-specific rules
   - DOM signature (platform) rules
4. Clean, minimal post-processing into reader-friendly content

This document explains what was found, why it works, and provides a practical, extensible implementation plan to reproduce and improve this approach for single-page parsing.

---

## What We Found (Empirical Findings)

### 1. Core extraction is Arc90 Readability

GoodLinks uses the Arc90 Readability algorithm as its baseline extractor. This is confirmed by:
- Acknowledgements in the app
- The structure of saved index.html files
- The absence of original page scaffolding, scripts, ads, or layout DOM

Readability provides:
- Main article content
- Paragraph segmentation
- Inline images and captions (best effort)
- Title detection

However, Readability alone is insufficient for high-quality output across modern sites.

---

### 2. GoodLinks applies a declarative DOM rule engine after Readability

GoodLinks ships a JavaScript file (`ck-rules.js`) containing ~56 rules. Each rule is a small JSON object describing DOM mutations.

These rules are not imperative code. They are declarative instructions applied to the parsed DOM.

#### Observed rule fields

| Key | Meaning (inferred) |
|-----|-------------------|
| `a` | Article root selector override |
| `we` | Wrapper element selector |
| `e` | Elements to remove |
| `i` | Elements to force include |
| `ac` | Transform actions (retag, unwrap, move, remove attrs) |
| `m` | Metadata extraction overrides |
| `ea` | Apply to entire article |
| `d` | Discard rule / disable extraction |

#### Example (simplified):

```json
{
  "a": "article",
  "e": ".related, .footer, .ads",
  "ac": [
    { "s": "figure img", "tp": "figure" }
  ]
}
```

This approach is cheap, predictable, and easy to extend.

---

### 3. Rules are triggered in two distinct ways

This is the most important architectural insight.

#### A. Host-based rules

Some rules are keyed by:

```
md5(normalised_host)
```

Example mappings discovered:

| Host | Rule |
|------|------|
| theguardian.com | Custom media + caption handling |
| wsj.com | Paywall and media restructuring |
| cnn.com | Image inclusion + author extraction |
| lifehacker.com | Ad and widget stripping |

These rules activate before or after Readability, depending on intent.

#### B. DOM signature (platform) rules

Many rules do not map to any URL or host.

Instead, they trigger when specific DOM signatures are detected:

| Platform / Pattern | Example selector |
|-------------------|------------------|
| Swiper carousels | `.swiper-slide-duplicate` |
| Squarespace | `.sqs-col-*` |
| Intercom help centers | `.intercom-interblocks-*` |
| Medium / Draft.js | `.public-DraftEditor-content` |
| Dotdash Meredith | `.mntl-*`, Sailthru metadata |

**Key finding**: Some rules never matched any URL in a 40k-article dataset, yet correctly matched DOM features when present.

This proves GoodLinks uses DOM fingerprinting, not URL mapping, for platform handling.

---

### 4. Saved "HTML" files are already post-processed

The files in:

```
~/Library/Containers/com.ngocluu.goodlinks/.../articles/<uuid>/index.html
```

are not raw HTML. They are:
- Readability output
- Already cleaned
- Already transformed by applicable rules

This confirms the rule engine runs before persistence, not at render time.

---

## Why This Works So Well

GoodLinks succeeds because it:
- Treats extraction as engineering, not inference
- Uses small, targeted fixes rather than global heuristics
- Avoids ML brittleness
- Keeps rules declarative and inspectable
- Separates concerns cleanly

Most pages require no special handling. A small minority benefit enormously from precise, cheap fixes.

---

## Target Output Format

The desired output is Markdown with YAML frontmatter, preserving:
- Source URL
- Published date
- Title
- Clean Markdown body
- Inline Markdown image links (URL only)

### Example:

```markdown
---
source: https://example.com/article
date: 2025-03-19
---

# Article Title

[![Image 1](https://image-url)](https://image-url)

Paragraph text…
```

---

## Practical Implementation Plan

### Architecture Overview

```
URL
 ↓
Fetch HTML
 ↓
Pre-Readability DOM pass (optional)
 ↓
Readability extraction
 ↓
Post-Readability DOM rule engine
 ↓
Metadata extraction
 ↓
Markdown conversion
 ↓
YAML frontmatter assembly
```

---

### 1. Fetch and normalise HTML

- Use server-side HTTP client
- Follow redirects
- Preserve original URL
- Set a realistic user agent

**Optional**:
- Lightweight JS rendering only if strictly necessary (avoid by default)

---

### 2. Baseline extraction (Readability)

**Recommended options**:
- Python: `readability-lxml`
- JS: `@mozilla/readability` (via Node service if needed)

**Input**: raw HTML
**Output**: simplified article HTML

---

### 3. Rule engine design (critical)

#### Rule structure (proposed)

```yaml
id: swiper-carousel
trigger:
  dom:
    any:
      - ".swiper-slide-duplicate"
apply:
  remove:
    - ".swiper-slide-duplicate"
```

or:

```yaml
id: guardian
trigger:
  host:
    equals: theguardian.com
apply:
  remove:
    - ".related-links"
  transform:
    - selector: "figure img"
      wrap: "figure"
```

#### Trigger types

- `host.equals`
- `host.ends_with`
- `dom.exists`
- `dom.any`
- `dom.all`

Rules should be composable and ordered.

---

### 4. Apply rules deterministically

- Parse Readability HTML into DOM
- Iterate rules in priority order
- If trigger matches, apply mutations
- Never mutate raw HTML directly

**Important**: Rules should be idempotent and safe to apply once.

---

### 5. Metadata extraction

#### Sources (in priority order):

1. Rule overrides (`m`)
2. Readability metadata
3. HTML meta tags
4. Fallback heuristics

#### Target fields:

- Title
- Published time (ISO 8601)
- Author (optional)
- Source URL

---

### 6. Markdown conversion

- Convert DOM → Markdown
- Preserve:
  - Paragraphs
  - Headings
  - Blockquotes
  - Emphasis
  - Images as Markdown image links
- Do not inline styles or scripts

#### Recommended libraries:

- Python: `markdownify` with custom rules
- Or custom DOM walker for full control

---

### 7. YAML frontmatter assembly

#### Example:

```yaml
---
source: <canonical_url>
date: <published_iso>
---
```

Keep frontmatter minimal and stable.

---

### 8. Extensibility strategy

- Store rules as external YAML/JSON
- Hot-reload rules without code changes
- Log which rules fired per page
- Make it easy to add:
  - New host rules
  - New platform rules
  - Temporary experimental rules

This mirrors GoodLinks' approach exactly.

---

## Conclusion

GoodLinks' parsing quality is not accidental. It is the result of disciplined, minimalist engineering:
- Strong baseline extraction
- Declarative post-processing
- Platform awareness via DOM signatures
- Explicit, inspectable rules

By reproducing this architecture server-side and emitting Markdown instead of HTML, you can build a cleaner, more controllable, AI-native equivalent optimised for single-page ingestion.
