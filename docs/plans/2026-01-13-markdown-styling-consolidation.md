# Markdown Styling Consolidation Plan

**Date:** 2026-01-13
**Status:** Planning
**Effort Estimate:** 2-3 hours
**Priority:** Medium

---

## Executive Summary

Consolidate duplicate markdown styles across 6 components into shared stylesheets while preserving all custom design work and intentional component-specific variations. **Not** migrating to GitHub CSS - our custom styling is more sophisticated and purpose-built.

---

## Problem Statement

### Current State
- Markdown rendered via TipTap in 6 components with extensive custom styling
- **Heavy duplication:** Table styles repeated identically across 5 components (~25 lines each = 125 lines of duplicated CSS)
- Task list styles duplicated across 2 components
- Mix of custom styles and Tailwind Typography prose classes
- No central documentation of design decisions

### What Works Well (Keep This)
✅ **OKLAB color mixing** - Modern, perceptually uniform color blending
✅ **Component-specific variations** - Purposeful design for different contexts
✅ **Custom TipTap extensions** - ImageGallery, ImageWithCaption, VimeoEmbed
✅ **YouTube transcript button** - Complex multi-state custom feature
✅ **Advanced image handling** - Horizontal scroll with scroll-snap
✅ **Theme integration** - CSS custom properties throughout
✅ **Carefully tuned typography** - Line heights, spacing, font sizes

---

## Why Not GitHub CSS?

### What We'd Lose
- ❌ OKLAB color mixing (GitHub CSS uses different approach)
- ❌ Component-specific variations (would need separate overrides anyway)
- ❌ All custom extensions styling (would need custom CSS regardless)
- ❌ YouTube transcript button system (completely custom)
- ❌ Advanced image scroll/snap behavior (not in GitHub CSS)
- ❌ Specific task list refinements
- ❌ Our table striping method (different in GitHub CSS)

### What We'd Gain
- ✅ Familiar styling (but we already have that)
- ✅ Maintained package (but introduces dependency)
- ✅ Light/dark theme support (but we already have this)

### Verdict
**Cost > Benefit.** Our styling is more sophisticated and purpose-built. The real problem is duplication, not the style system itself.

---

## Solution: Consolidate Existing Styles

### Approach
1. Extract duplicate styles to shared stylesheet
2. Keep intentional component variations in place
3. Document design decisions
4. Minor cleanup of inconsistencies

### Design Principles to Preserve
- OKLAB color mixing for subtle transparency/blending
- Component-specific spacing for different contexts (editor vs scratchpad vs website viewer)
- Consistent table and task list styling where identical
- Custom extensions with specialized layouts
- Theme-aware colors via CSS custom properties

---

## Implementation Plan

### Phase 1: Extract Shared Styles (1 hour)

**File to Create:** `/Users/sean/Coding/sideBar/frontend/src/lib/styles/markdown-shared.css`

**Content:**
```css
/* ============================================
   SHARED MARKDOWN STYLES
   Used across all TipTap markdown instances
   ============================================ */

/* TABLES - Identical across 5 components
   Components: MarkdownEditor, ChatMarkdown, FileMarkdown, WebsitesViewer, scratchpad-popover
   Design: OKLAB color mixing for striped rows, muted header, zero vertical padding
*/
.tiptap table,
.tiptap-editor table,
.chat-markdown table,
.file-markdown table,
.website-viewer table,
.memory-markdown table,
.scratchpad-editor table {
  width: 100%;
  border-collapse: collapse;
  margin: 1em 0;
  font-size: 0.95em;
}

.tiptap th,
.tiptap-editor th,
.chat-markdown th,
.file-markdown th,
.website-viewer th,
.memory-markdown th,
.scratchpad-editor th,
.tiptap td,
.tiptap-editor td,
.chat-markdown td,
.file-markdown td,
.website-viewer td,
.memory-markdown td,
.scratchpad-editor td {
  border: 1px solid var(--color-border);
  padding: 0em 0.75em;
  text-align: left;
  vertical-align: top;
}

.tiptap thead th,
.tiptap-editor thead th,
.chat-markdown thead th,
.file-markdown thead th,
.website-viewer thead th,
.memory-markdown thead th,
.scratchpad-editor thead th {
  background-color: var(--color-muted);
  color: var(--color-foreground);
  font-weight: 600;
}

.tiptap tbody tr:nth-child(even),
.tiptap-editor tbody tr:nth-child(even),
.chat-markdown tbody tr:nth-child(even),
.file-markdown tbody tr:nth-child(even),
.website-viewer tbody tr:nth-child(even),
.memory-markdown tbody tr:nth-child(even),
.scratchpad-editor tbody tr:nth-child(even) {
  background-color: color-mix(in oklab, var(--color-muted) 40%, transparent);
}

/* TASK LISTS - Identical across 2 components
   Components: MarkdownEditor, scratchpad-popover
   Design: Flexbox layout, strikethrough for completed, custom checkbox accent
*/
.tiptap ul[data-type='taskList'],
.scratchpad-editor ul[data-type='taskList'] {
  list-style: none;
  padding-left: 0;
}

.tiptap ul[data-type='taskList'] ul[data-type='taskList'],
.scratchpad-editor ul[data-type='taskList'] ul[data-type='taskList'] {
  margin-top: 0;
  margin-bottom: 0;
}

.tiptap ul[data-type='taskList'] > li,
.scratchpad-editor ul[data-type='taskList'] > li {
  display: flex;
  align-items: flex-start;
  gap: 0.5em;
}

.tiptap ul[data-type='taskList'] > li > label,
.scratchpad-editor ul[data-type='taskList'] > li > label {
  margin-top: 0.2em;
}

.tiptap ul[data-type='taskList'] > li > div,
.scratchpad-editor ul[data-type='taskList'] > li > div {
  flex: 1;
}

.tiptap ul[data-type='taskList'] > li > div > p,
.scratchpad-editor ul[data-type='taskList'] > li > div > p {
  margin: 0;
}

.tiptap ul[data-type='taskList'] > li > div > p:empty,
.scratchpad-editor ul[data-type='taskList'] > li > div > p:empty {
  display: none;
}

.tiptap ul[data-type='taskList'] > li[data-checked='true'] > div,
.scratchpad-editor ul[data-type='taskList'] > li[data-checked='true'] > div {
  color: var(--color-muted-foreground);
  text-decoration: line-through;
}

.tiptap ul[data-type='taskList'] input[type='checkbox'],
.scratchpad-editor ul[data-type='taskList'] input[type='checkbox'] {
  accent-color: var(--color-foreground); /* Updated from hardcoded #000 */
}
```

**Import in:** `/Users/sean/Coding/sideBar/frontend/src/app.css`
```css
/* Add near top of file */
@import './lib/styles/markdown-shared.css';
```

**Files to Modify - Remove Duplicate Styles:**

1. **ChatMarkdown.svelte** - Remove lines 54-77 (table styles)
2. **FileMarkdown.svelte** - Remove lines 54-77 (table styles)
3. **WebsitesViewer.svelte** - Remove lines 496-519 (table styles)
4. **scratchpad-popover.svelte** - Remove lines 353-376 (table styles) and 320-351 (task list styles)
5. **MarkdownEditor.svelte** - Remove lines 575-599 (table styles) and 519-558 (task list styles)

---

### Phase 2: Document Component Variations (30 min)

**File to Create:** `/Users/sean/Coding/sideBar/docs/MARKDOWN_STYLES.md`

**Content:**
```markdown
# Markdown Styling Guide

## Overview

All markdown content in sideBar is rendered via TipTap with the `tiptap-markdown` extension. We use custom styling across 6 components with intentional variations for different contexts.

## Design Principles

1. **OKLAB Color Mixing** - Modern color blending for subtle transparency and color variations
2. **Theme Integration** - All colors use CSS custom properties (var(--color-*))
3. **Context-Specific Spacing** - Different spacing for different use cases
4. **Consistent Tables** - Identical styling across all components
5. **Custom Extensions** - Purpose-built image galleries, video embeds, captions

## Component Matrix

### MarkdownEditor.svelte
**Purpose:** Long-form note editing and writing
**Max Width:** 85ch (optimal for reading)
**Line Height:** 1.7
**Paragraph Margins:** 0.75em
**Extensions:** StarterKit, ImageGallery, ImageWithCaption, TaskList, TaskItem, TableKit, Markdown
**Special Features:** Empty state, spin animation for save indicator

**Why These Settings:**
- 85ch matches optimal line length for reading (45-75 characters)
- 1.7 line height for comfortable paragraph reading
- Standard spacing for long-form content

---

### WebsitesViewer.svelte
**Purpose:** Display saved website content (external)
**Max Width:** 856px
**Image Max:** 720px × 500px (vs 350px in other components)
**Gallery Layout:** Fixed 2-column (49% width each)
**Extensions:** + Youtube, Link, VimeoEmbed (in addition to standard set)
**Special Features:** YouTube transcript button, video embeds, different heading margins

**Why These Settings:**
- Larger max width for images/videos from external sources
- Fixed 2-column gallery for predictable layout of web images
- Symmetric heading margins with !important (external content may have conflicting styles)
- YouTube transcript button for fetching and displaying video transcripts

**Unique Styles:**
- Empty paragraph hiding: `p:has(> br.ProseMirror-trailingBreak:only-child) { display: none }`
- Gap cursor hiding in galleries: `.image-gallery-grid .ProseMirror-gapcursor { display: none }`
- Different monospace font stack: SF Mono first

---

### scratchpad-popover.svelte
**Purpose:** Quick note capture in compact popover
**Max Height:** 720px (constrained by popover)
**Line Height:** 1.6 (vs 1.7)
**Paragraph Margins:** 0.5em (vs 0.75em)
**HR Margins:** 1.25rem (vs 2em)
**Extensions:** Standard set
**Special Features:** Loading overlay with semi-transparent background

**Why These Settings:**
- Tighter spacing for compact popover UI
- Smaller margins to fit more content in limited space
- Still readable but optimized for density

---

### ChatMarkdown.svelte
**Purpose:** Display AI assistant responses in chat
**Max Width:** None (full width)
**Prose Classes:** `prose prose-sm max-w-none`
**Extensions:** Standard set
**Editable:** No (read-only)

**Why These Settings:**
- Read-only display of streaming content
- Full width to use available chat panel space
- Smaller prose size for chat context

---

### FileMarkdown.svelte
**Purpose:** Preview markdown files in file viewer
**Max Width:** None (full width)
**Prose Classes:** `prose prose-sm max-w-none`
**Extensions:** Standard set
**Editable:** No (read-only)

**Why These Settings:**
- Similar to ChatMarkdown, optimized for preview context
- Read-only display of file contents

---

### MemorySettings.svelte
**Purpose:** Edit memory items in settings dialog
**Max Width:** 720px (modal constraint)
**Prose Classes:** `prose prose-sm max-w-none`
**Extensions:** Standard set
**Editable:** Yes
**Special Features:** Bordered editor with rounded corners

**Why These Settings:**
- Compact editing in modal dialog
- Border provides visual container

## Shared Styles

### Tables
**Design:** Striped rows with OKLAB color mixing, muted header background
**Striping:** `color-mix(in oklab, var(--color-muted) 40%, transparent)`
**Font Size:** 0.95em (slightly smaller for dense information)
**Cell Padding:** 0em vertical, 0.75em horizontal (only horizontal padding)
**Used In:** All 6 components identically

### Task Lists
**Design:** Flexbox layout with checkbox + text, strikethrough for completed
**Checkbox Accent:** Uses `var(--color-foreground)` for theme awareness
**Completed State:** Muted color + line-through
**Used In:** MarkdownEditor, scratchpad-popover

### Images
**Global Default:** max-height 350px, max-width 80%
**Website Viewer:** max-height 500px, max-width 720px (larger for external content)
**Horizontal Scroll:** Flexbox with scroll-snap for multiple images in paragraph
**Used In:** All components via global styles in app.css

### Image Galleries
**Global:** Flexible grid (flex: 1 1 200px, max-width: 240px)
**Website Viewer:** Fixed 2-column (width: 49% each) - intentionally different
**Caption:** 0.85rem, muted color, centered
**Used In:** All components

### Video Embeds
**Aspect Ratio:** 16:9 (critical for responsive video)
**Max Width:** 80% of container
**Border Radius:** 0.5rem (global), 0.85rem (website viewer YouTube)
**Used In:** WebsitesViewer only (YouTube + Vimeo)

## Custom Features

### YouTube Transcript Button (WebsitesViewer only)
**Trigger:** Links with `sidebarTranscript=1` in href
**States:**
- Default: Button-like with muted background
- Hover: OKLAB color mixing for subtle highlight
- Busy: 60% opacity, pointer-events disabled
- Disabled: No hover effect
- Queued: Orange pulsing dot animation

**Animation:** Pulsing orange dot (scale 1-1.2, opacity 0.6-1)
**Width:** min(100%, 650px)
**Styling:** Uppercase text, rounded corners (0.7rem)

**Code Location:** WebsitesViewer.svelte lines 631-729

### Image Galleries
**Extension:** Custom TipTap node (ImageGallery.ts)
**Structure:** `<figure class="image-gallery">` with `<div class="image-gallery-grid">`
**Optional Caption:** Via `data-caption` attribute
**Layout:** Flexbox wrap with gap, responsive sizing

### Image With Caption
**Extension:** Custom TipTap node (ImageWithCaption.ts)
**Structure:** `<figure class="image-block">` with `<img>` + `<figcaption>`
**Caption Source:** Image `title` attribute
**Fallback:** Plain `<img>` if no caption

### Vimeo Embeds
**Extension:** Custom TipTap node (VimeoEmbed.ts)
**Structure:** `<iframe class="video-embed">`
**Attributes:** frameborder="0", allowfullscreen
**Styling:** Same as YouTube embeds (16:9 aspect ratio)

## Color System

### CSS Custom Properties Used
- `--color-background` - Main background
- `--color-foreground` - Main text
- `--color-muted` - Muted/secondary background
- `--color-muted-foreground` - Muted/secondary text
- `--color-primary` - Primary accent (links)
- `--color-border` - Borders and dividers
- `--color-sidebar-border` - Sidebar-specific borders

### OKLAB Color Mixing
**Why OKLAB:** Perceptually uniform color space for natural-looking blends

**Usage Examples:**
- Table striping: `color-mix(in oklab, var(--color-muted) 40%, transparent)`
- Transcript button hover: `color-mix(in oklab, var(--color-muted) 80%, var(--color-foreground) 8%)`
- Scratchpad loading overlay: `color-mix(in oklab, var(--color-background) 85%, transparent)`

**Browser Support:** Modern browsers (Chrome 111+, Firefox 113+, Safari 16.4+)

## Typography

### Font Stacks
**Monospace:**
- Standard: `ui-monospace, 'Cascadia Code', 'Source Code Pro', Menlo, Consolas, 'DejaVu Sans Mono', monospace`
- Website Viewer: `'SF Mono', Monaco, 'Cascadia Code', 'Courier New', monospace` (different for external content)

### Font Sizes
- Body: Default (~16px)
- Inline Code: 0.875em (editor), 0.9em (website viewer)
- Tables: 0.95em
- Image Captions: 0.85rem
- H1: 2em
- H2: 1.5em
- H3: 1.25em (editor), 1.17em (website viewer)

### Line Heights
- Paragraphs: 1.7 (editor), 1.6 (scratchpad)
- List Items: 1.4
- Code Blocks: 1.5

### Font Weights
- H1: 700 (bold)
- H2, H3: 600 (semi-bold)
- Strong: 700
- Table Headers: 600

## Spacing System

### Vertical Rhythm
**Standard (Editor):**
- Paragraphs: 0.75em
- Lists: 0.75em
- HR: 2em
- Blockquote: 1em
- Tables: 1em
- Code Blocks: 1em

**Compact (Scratchpad):**
- Paragraphs: 0.5em
- Lists: 0.5em
- HR: 1.25rem

### Horizontal Spacing
- Inline Code Padding: 0.2em × 0.4em
- Code Block Padding: 1em
- Table Cell Padding: 0em × 0.75em (horizontal only)
- Blockquote Padding-Left: 1em
- List Padding-Left: 1.5em

### Gaps
- Task List Items: 0.5em
- Image Gallery Grid: 0.75rem (global), 0.5rem (website viewer)
- YouTube Video Container: 0.9rem

## Border Radius
- Inline Code: 0.25em
- Code Blocks: 0.5em/0.5rem
- Video Embeds: 0.5rem (global), 0.85rem (website YouTube)
- Transcript Button: 0.7rem
- Memory Editor: 0.75rem

## Maintenance Guidelines

### Adding New Markdown Component
1. Import `/lib/styles/markdown-shared.css` (automatically via app.css)
2. Apply TipTap classes: `tiptap` or component-specific like `chat-markdown`
3. Use standard extensions: StarterKit, ImageGallery, ImageWithCaption, TaskList, TaskItem, TableKit, Markdown
4. Add component-specific styles only if context requires different spacing/sizing
5. Document any variations in this file

### Modifying Table Styles
**Location:** `/lib/styles/markdown-shared.css`
**Impact:** All 6 components
**Test:** Check ChatMarkdown, FileMarkdown, MarkdownEditor, WebsitesViewer, scratchpad-popover, MemorySettings

### Modifying Task List Styles
**Location:** `/lib/styles/markdown-shared.css`
**Impact:** MarkdownEditor, scratchpad-popover
**Test:** Both components with various task list states

### Adding New Custom Extension
1. Create extension file in `/lib/components/editor/`
2. Add global styles to `app.css` if needed across all components
3. Add component-specific styles if needed
4. Update this documentation
5. Test in all relevant components

## Known Issues / Considerations

### Browser Compatibility
- **OKLAB color mixing:** Requires modern browsers (2023+)
- **Scroll-snap:** Requires modern browsers (2020+)
- **Aspect-ratio:** Requires modern browsers (2021+)

### Dark Mode
All colors use CSS custom properties and automatically adapt to dark mode via the theme system.

### Performance
- TipTap instances are lightweight and performant
- Images are lazy-loaded by browser
- Video embeds only load when visible (native iframe behavior)

## File Locations

### Style Files
- `/Users/sean/Coding/sideBar/frontend/src/lib/styles/markdown-shared.css` - Shared table and task list styles
- `/Users/sean/Coding/sideBar/frontend/src/app.css` - Global image, gallery, and video styles
- Component `<style>` blocks - Component-specific variations

### Extension Files
- `/Users/sean/Coding/sideBar/frontend/src/lib/components/editor/ImageGallery.ts`
- `/Users/sean/Coding/sideBar/frontend/src/lib/components/editor/ImageWithCaption.ts`
- `/Users/sean/Coding/sideBar/frontend/src/lib/components/editor/VimeoEmbed.ts`

### Component Files
- `/Users/sean/Coding/sideBar/frontend/src/lib/components/editor/MarkdownEditor.svelte`
- `/Users/sean/Coding/sideBar/frontend/src/lib/components/chat/ChatMarkdown.svelte`
- `/Users/sean/Coding/sideBar/frontend/src/lib/components/files/FileMarkdown.svelte`
- `/Users/sean/Coding/sideBar/frontend/src/lib/components/websites/WebsitesViewer.svelte`
- `/Users/sean/Coding/sideBar/frontend/src/lib/components/settings/MemorySettings.svelte`
- `/Users/sean/Coding/sideBar/frontend/src/lib/components/scratchpad-popover.svelte`

## Change Log

### 2026-01-13 - Consolidation
- Extracted duplicate table styles to markdown-shared.css
- Extracted duplicate task list styles to markdown-shared.css
- Updated task list checkbox accent color from hardcoded #000 to var(--color-foreground)
- Documented all component variations and design decisions
- Removed 125+ lines of duplicate CSS
```

---

### Phase 3: Minor Cleanup (30-60 min)

**Optional improvements for consistency:**

#### 3.1 Task List Checkbox Color (Already in Phase 1)
Update from hardcoded `#000` to `var(--color-foreground)` for theme awareness.

#### 3.2 Standardize Border Radius (Optional)
Currently mix of `em` and `rem` units:
- Inline code: `0.25em` → Consider `0.25rem`
- Code blocks: `0.5em` → Consider `0.5rem`

**Decision:** Keep as-is. `em` units scale with font size which may be intentional.

#### 3.3 Font Stack Consistency (Optional)
Two different monospace stacks:
- Editor: `ui-monospace, 'Cascadia Code', ...`
- Website Viewer: `'SF Mono', Monaco, 'Cascadia Code', ...`

**Decision:** Keep different. Website viewer displays external content that may prefer SF Mono.

#### 3.4 Add Comments to Component Styles
Add explanatory comments to remaining component-specific styles:

**Example for MarkdownEditor.svelte:**
```css
/* EDITOR-SPECIFIC STYLES
   Context: Long-form writing and editing
   Max width: 85ch for optimal readability
   Line height: 1.7 for comfortable reading
*/

/* Typography - Standard spacing for long-form content */
:global(.tiptap p) {
  margin-top: 0.75em;
  margin-bottom: 0.75em;
  line-height: 1.7;
}

/* ... etc ... */
```

**Example for WebsitesViewer.svelte:**
```css
/* WEBSITE VIEWER SPECIFIC STYLES
   Context: External content display
   Intentionally different from editor for external content needs
*/

/* Headings - Symmetric margins with !important to override external styles */
:global(.tiptap.website-viewer h2) {
  font-size: 1.5em;
  font-weight: 600;
  margin: 0.75em 0 !important;
}

/* Images - Larger dimensions for external content */
:global(.tiptap.website-viewer img) {
  display: block !important;
  margin-left: auto;
  margin-right: auto;
  max-width: 720px;  /* vs 350px default */
  max-height: 500px; /* vs 350px default */
}

/* Image Galleries - Force 2-column layout (vs flexible grid) */
:global(.tiptap.website-viewer .image-gallery-grid img) {
  display: block;
  margin: 0;
  width: 49% !important;
  flex: 0 0 49% !important;
  max-width: none !important;
  max-height: 500px !important;
}
```

**Example for scratchpad-popover.svelte:**
```css
/* SCRATCHPAD SPECIFIC STYLES
   Context: Quick notes in compact popover
   Intentionally tighter spacing for compact UI
*/

/* Paragraphs - Tighter spacing than editor (0.5em vs 0.75em) */
:global(.scratchpad-editor p) {
  margin: 0.5em 0;
  line-height: 1.6; /* vs 1.7 in editor */
}

/* HR - Tighter spacing for compact context */
:global(.scratchpad-editor hr) {
  border: none;
  border-top: 1px solid var(--color-border);
  margin: 1.25rem 0; /* vs 2em in editor */
}
```

---

### Phase 4: Testing (30 min)

**Test Matrix:**

| Component | Test Cases |
|-----------|------------|
| MarkdownEditor | Tables with striping, task lists (checked/unchecked), all heading levels, images, code blocks |
| ChatMarkdown | Tables in AI responses, inline code, links |
| FileMarkdown | Tables in file preview, code blocks |
| WebsitesViewer | Tables, images (larger), galleries (2-column), YouTube embeds, transcript button |
| MemorySettings | Tables in memory editor, task lists |
| scratchpad-popover | Tables, task lists, tighter spacing |

**Visual Regression Checks:**
- [ ] Table striping still uses OKLAB (40% muted transparency)
- [ ] Task list checkboxes now use foreground color (not hardcoded black)
- [ ] Completed tasks show strikethrough + muted color
- [ ] Website viewer images still larger than other components
- [ ] Website viewer galleries still 2-column
- [ ] Scratchpad spacing still tighter than editor
- [ ] YouTube transcript button still works with all states
- [ ] Dark mode works correctly

**Browser Testing:**
- Chrome (OKLAB support)
- Firefox (OKLAB support)
- Safari (OKLAB support)

---

## Success Criteria

- [ ] Duplicate table styles removed from 5 components (~125 lines removed)
- [ ] Duplicate task list styles removed from 2 components (~40 lines removed)
- [ ] Shared stylesheet created and imported
- [ ] All components still render identically (no visual regression)
- [ ] Documentation file created explaining all design decisions
- [ ] Task list checkbox color now theme-aware
- [ ] Comments added to component-specific styles
- [ ] All test cases pass

**Total Lines Removed:** ~165 lines of duplicate CSS
**Documentation Added:** ~500 lines of comprehensive style guide

---

## Rollback Plan

If issues arise:

1. **Revert CSS imports:**
   - Remove `@import './lib/styles/markdown-shared.css';` from app.css
   - Delete `/lib/styles/markdown-shared.css`

2. **Restore component styles:**
   - Git revert changes to each component
   - Tables and task lists will work from existing styles

3. **No data loss risk:** This is purely CSS changes, no data or functionality affected

---

## Future Considerations

### Potential Follow-Up Work (Not in This Plan)

1. **Tailwind Typography Removal:**
   - Currently using `@tailwindcss/typography` but heavily overriding it
   - Could remove prose classes entirely and use custom styles only
   - Effort: 1-2 hours
   - Benefit: Smaller bundle, clearer styling source

2. **Design Token System:**
   - Extract spacing values (0.5em, 0.75em, 1em) to CSS custom properties
   - Create semantic spacing scale (--spacing-sm, --spacing-md, --spacing-lg)
   - Effort: 2-3 hours
   - Benefit: Easier to adjust spacing globally

3. **Component Style Library:**
   - Create reusable style utilities for common patterns
   - Extract heading styles, list styles as mixins/utilities
   - Effort: 3-4 hours
   - Benefit: Easier to maintain consistency

**Decision:** Out of scope for this plan. Current consolidation is sufficient.

---

## Appendix: Style Inventory

### Components Rendering Markdown
1. MarkdownEditor.svelte - Full editor with 200+ lines custom CSS
2. ChatMarkdown.svelte - Read-only, tables only
3. FileMarkdown.svelte - Read-only, tables only
4. WebsitesViewer.svelte - Full custom styles + video embeds + transcript button
5. MemorySettings.svelte - Minimal custom styles
6. scratchpad-popover.svelte - Compact variant with tighter spacing

### Custom TipTap Extensions
1. ImageGallery.ts - Grid layout for multiple images
2. ImageWithCaption.ts - Figure/figcaption structure
3. VimeoEmbed.ts - Vimeo iframe rendering

### Intentional Component Variations (Keep These)
- **MarkdownEditor:** 85ch max-width, 1.7 line-height, 0.75em margins
- **WebsitesViewer:** 856px max-width, larger images (500px), 2-column galleries, symmetric heading margins, YouTube transcripts
- **scratchpad-popover:** Tighter spacing (1.6 line-height, 0.5em margins, 1.25rem HR)

### Global Styles (Keep in app.css)
- Image handling (horizontal scroll, scroll-snap)
- Image galleries (flexbox grid)
- Image captions (muted color, small font)
- Video embeds (16:9 aspect ratio)

### Duplicate Styles (Extract to Shared)
- Tables (identical across 5 components)
- Task lists (identical across 2 components)

---

## Questions & Answers

**Q: Why not use GitHub's markdown CSS?**
A: Our styling is more sophisticated (OKLAB color mixing, custom extensions, component-specific variations) and purpose-built for our use cases. GitHub CSS would require extensive overrides, negating any benefit.

**Q: Will this affect existing content?**
A: No. This is purely CSS consolidation. All markdown content will render identically.

**Q: What about browser compatibility?**
A: OKLAB color mixing requires modern browsers (Chrome 111+, Firefox 113+, Safari 16.4+). Already in use, no change.

**Q: Can we add more shared styles later?**
A: Yes. The markdown-shared.css file can be extended with any other common patterns found.

**Q: What if a component needs different table styles?**
A: Add component-specific overrides after the shared styles. The shared styles provide a consistent baseline.

---

## References

- TipTap Documentation: https://tiptap.dev/
- OKLAB Color Space: https://bottosson.github.io/posts/oklab/
- CSS color-mix(): https://developer.mozilla.org/en-US/docs/Web/CSS/color_value/color-mix
- Tailwind Typography: https://tailwindcss.com/docs/typography-plugin

---

**Plan Status:** Ready for Implementation
**Next Steps:** Begin Phase 1 - Extract shared styles to new CSS file
