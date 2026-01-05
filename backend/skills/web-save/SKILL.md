---
name: web-save
description: Save web pages as clean markdown files using a local parser with optional Jina.ai fallback. Use when you need to archive articles, blog posts, documentation, or any web content for later reading or building a local knowledge base.
---

# web-save

Save web pages as markdown files using a local parser with optional Jina.ai fallback.

## Description

Fetches web page content, converts it to markdown using a local parser, and saves it to the database with metadata. Falls back to Jina.ai when configured.

## When to Use

- Save interesting articles or web pages for later reading
- Archive web content as markdown for note-taking
- Capture blog posts, documentation, or any web content
- Build a local knowledge base from web sources

## Requirements

- Internet connection to fetch web content
- **JINA_API_KEY** (optional) environment variable for fallback (stored in Doppler secrets)

## Scripts

### save_url.py
Fetches a URL and saves it as a markdown entry in the database using the local parser (with Jina.ai fallback when configured).

```bash
python save_url.py URL [--folder FOLDER] [--filename FILENAME] [--json]
```

**Arguments**:
- `URL`: Web page URL to save (required)

**Options**:
- `--folder`: Subfolder within Websites/ to save to (default: root)
- `--filename`: Custom filename (default: auto-generated from page title)
- `--json`: Output results in JSON format

**Features**:
- Automatic title extraction from page content
- Metadata header with source URL and date
- Sanitized filenames (replaces invalid characters)
- Optional subfolder organization
- Validates URLs and handles redirects

**Examples**:
```bash
# Save article to Websites/
python save_url.py "https://example.com/article"

# Save to subfolder
python save_url.py "https://example.com/article" --folder "Tech Articles"

# Custom filename
python save_url.py "https://example.com/article" --filename "my-saved-article"

# JSON output
python save_url.py "https://example.com/article" --json
```

**Output**:
Creates a markdown file with:
```markdown
---
source: https://example.com/article
date: 2025-12-20
---

[Page content in markdown format]
```

## Configuration

The skill uses:
- **Storage**: Database (websites table)
- **API**: Local parsing pipeline
- **Fallback API**: Jina.ai Reader API (https://r.jina.ai/) when `JINA_API_KEY` is set

## Future Enhancements

Potential future features:
- Batch URL processing
- Tag/category support
- Integration with folder-config for custom save locations
- Content filtering/summarization options
- Support for other markdown conversion services
