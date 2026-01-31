---
title: "Favicon Capture Implementation Plan"
description: "Plan for capturing and processing site favicons."
---

# Favicon Capture Implementation Plan

**Created:** 2026-01-20
**Status:** Ready for implementation
**Estimated effort:** 7-10 hours total (phased)

## Overview

Capture and store website favicons to display alongside saved articles in the iOS UI instead of the current generic globe icon.

## Current State

- **Website model** (`backend/api/models/website.py`): No favicon field
- **Metadata extraction** (`backend/api/services/web_save_parser.py:175-210`): Extracts title, author, published, canonical, og:image - no favicon
- **iOS display** (`ios/sideBar/sideBar/Views/SidebarPanels/WebsiteRows.swift:91`): Hard-coded `Image(systemName: "globe")`
- **Storage**: R2 (Cloudflare) available via `backend/api/services/storage/r2.py`

## Recommended Approach: Hybrid Strategy

### Extraction (Multi-tier Fallback)

1. Parse `<link rel="icon">` from HTML head (already using BeautifulSoup)
2. Parse `<link rel="apple-touch-icon">` (optimized for iOS)
3. Try standard `/favicon.ico` with HEAD request
4. Fallback to generic icon (~5% of sites)

**Expected coverage:** ~95% of websites

### Storage

Store in existing `metadata_` JSONB field:

```json
{
  "favicon_url": "https://example.com/favicon.png",
  "favicon_r2_key": "favicons/{user_id}/{domain_hash}.png",
  "favicon_extracted_at": "2026-01-20T10:00:00Z"
}
```

### Why Not External Services?

Google (`google.com/s2/favicons`) and DuckDuckGo (`icons.duckduckgo.com`) favicon services were considered but rejected:
- External dependency outside our control
- Privacy implications
- Rate limiting potential
- R2 infrastructure already available

---

## Implementation Phases

### Phase 1: MVP (Backend) - ~1.5 hours

**Goal:** Extract favicon URL and store in metadata

**Files to modify:**
- `backend/api/services/web_save_parser.py`

**Tasks:**

1. Extend `extract_metadata()` function to parse favicon from HTML:
   ```python
   def extract_metadata(html: str, url: str) -> dict:
       # ... existing code ...

       # Favicon extraction (add after existing meta parsing)
       favicon = None
       for rel in ("icon", "shortcut icon", "apple-touch-icon"):
           link = soup.find("link", rel=rel)
           if link and link.get("href"):
               favicon = urljoin(url, link["href"])
               break

       return {
           # ... existing fields ...
           "favicon": favicon,
       }
   ```

2. Favicon URL flows through existing pipeline into `metadata_` JSONB

3. Add unit test for favicon extraction in `backend/tests/skills/web_save/test_web_save_parser.py`

**Outcome:** Favicon URLs stored for new saves, iOS can load directly from source

---

### Phase 2: Background R2 Upload (Backend) - ~3-4 hours

**Goal:** Download favicons and cache in R2 for reliable CDN delivery

**Files to modify/create:**
- `backend/api/services/favicon_service.py` (new)
- `backend/api/routers/websites_helpers.py`

**Tasks:**

1. Create `favicon_service.py`:
   ```python
   async def fetch_and_store_favicon(
       user_id: str,
       domain: str,
       favicon_url: str,
   ) -> str | None:
       """Download favicon and upload to R2, return R2 key."""
       # 1. Download from favicon_url (with timeout, size limit)
       # 2. Validate it's an image (PNG, ICO, SVG)
       # 3. Optionally resize if >256x256
       # 4. Upload to R2: favicons/{user_id}/{domain_hash}.png
       # 5. Return R2 key
   ```

2. Call from `run_quick_save()` background task after page save completes

3. Update website metadata with `favicon_r2_key` after upload

4. Add R2 bucket path constant: `FAVICON_BUCKET_PREFIX = "favicons/"`

**Edge cases to handle:**
- Favicon behind authentication (accept failure, keep source URL)
- Very large files (>1MB) - resize/compress
- Animated GIFs - convert to static or accept
- Redirects - follow and store final URL
- CORS - not an issue since backend fetches

**Outcome:** Favicons cached in R2 with CDN delivery, ~50-100ms load time

---

### Phase 3: iOS Display - ~3-4 hours

**Goal:** Display favicons in website list UI

**Files to modify/create:**
- `ios/sideBar/sideBar/Models/WebsiteModels.swift`
- `ios/sideBar/sideBar/Views/SidebarPanels/WebsiteRows.swift`
- `ios/sideBar/sideBar/Views/Components/FaviconImageView.swift` (new)

**Tasks:**

1. Update `WebsiteItem` model:
   ```swift
   struct WebsiteItem: Identifiable, Codable {
       // ... existing fields ...
       let faviconUrl: String?
       let faviconR2Key: String?
   }
   ```

2. Create `FaviconImageView` component:
   ```swift
   struct FaviconImageView: View {
       let faviconUrl: String?
       let faviconR2Key: String?
       let size: CGFloat

       var body: some View {
           // 1. If faviconR2Key exists, load from R2 CDN URL
           // 2. Else if faviconUrl exists, load from source
           // 3. Else show Image(systemName: "globe")
           // Use AsyncImage with placeholder and caching
       }
   }
   ```

3. Update `WebsiteRow` to use `FaviconImageView`:
   ```swift
   // Replace: Image(systemName: "globe")
   // With: FaviconImageView(faviconUrl: item.faviconUrl, faviconR2Key: item.faviconR2Key, size: 20)
   ```

4. Add image caching layer (URLCache or third-party like Kingfisher/SDWebImage)

**Outcome:** Website list shows actual favicons with fast cached loading

---

## API Changes

### Website Response

Add to website list/detail responses:

```json
{
  "id": "...",
  "domain": "wired.com",
  "title": "Article Title",
  "metadata": {
    "favicon_url": "https://wired.com/favicon.ico",
    "favicon_r2_key": "favicons/user123/abc123.png"
  }
}
```

### R2 CDN URL Construction

iOS constructs CDN URL from R2 key:
```
https://{R2_PUBLIC_DOMAIN}/favicons/{user_id}/{domain_hash}.png
```

---

## Storage Costs

- Average favicon size: ~5-20KB
- Per user (100 saved sites): ~1-2MB
- R2 cost: ~$0.015/GB/month
- **Estimated cost: <$0.01/user/month**

---

## Success Criteria

- [ ] 85%+ of newly saved websites have favicon extracted
- [ ] iOS loads favicon within 100ms (from R2 cache)
- [ ] Page save latency unchanged (<5ms impact)
- [ ] Graceful fallback to globe icon when unavailable

---

## Future Enhancements

- Periodic re-fetch for stale favicons (>30 days old)
- Batch backfill for existing saved websites
- Support for SVG favicons with rasterization
- Dark mode favicon variants (if site provides)
