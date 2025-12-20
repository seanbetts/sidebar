---
name: web-save
description: Save web pages as clean markdown files using Jina.ai Reader API. Use when you need to archive articles, blog posts, documentation, or any web content for later reading or building a local knowledge base.
---

# web-save

Save web pages as markdown files using Jina.ai Reader API.

## Description

Fetches web page content, converts it to markdown using Jina.ai's Reader API, and saves it to the Websites folder with metadata (source URL and date). Automatically extracts and uses the page title as the filename.

## When to Use

- Save interesting articles or web pages for later reading
- Archive web content as markdown for note-taking
- Capture blog posts, documentation, or any web content
- Build a local knowledge base from web sources

## Requirements

- **JINA_API_KEY** environment variable must be set (stored in Doppler secrets)
- Internet connection to fetch web content

## Scripts

### save_url.py
Fetches a URL and saves it as a markdown file in the Websites folder.

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
- **Base folder**: `~/Documents/Agent Smith/Websites/`
- **API**: Jina.ai Reader API (https://r.jina.ai/)
- **API Key**: From `JINA_API_KEY` environment variable

## Future Enhancements

Potential future features:
- Batch URL processing
- Tag/category support
- Integration with folder-config for custom save locations
- Content filtering/summarization options
- Support for other markdown conversion services
