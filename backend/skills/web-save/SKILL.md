---
name: web-save
description: Database-backed website operations - add, read, list, rename, pin, archive, delete, and export websites.
metadata:
  capabilities:
    reads: true
    writes: true
    network: true
    external_apis: true
---

# Web Save Operations

Database-backed operations for saved websites.

## Scripts

- `save_url.py` - Add/save a website URL into the database
- `read_website.py` - Fetch a website by ID
- `list_websites.py` - List websites with optional filters
- `rename_website.py` - Rename a website title
- `pin_website.py` - Pin or unpin a website
- `archive_website.py` - Archive or unarchive a website
- `delete_website.py` - Soft-delete a website
- `download_website.py` - Export website markdown content + filename metadata

All scripts support `--json` output.

## save_url.py

`save_url.py` fetches and parses a URL, then stores a normalized markdown snapshot plus metadata in the websites table.

```bash
python save_url.py URL --database --user-id USER_ID [--json]
```

### Notes

- `WEB_SAVE_MODE` controls parser behavior (`local`, `jina`, `compare`; default `local`).
- `JINA_API_KEY` is optional unless `WEB_SAVE_MODE` requires Jina fetches.
- URLs are normalized before save to avoid duplicate records.
