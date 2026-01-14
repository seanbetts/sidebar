# Markdown Styling Guide

This document explains the markdown styling system used across sideBar's TipTap-based components.

## Overview

All markdown components in sideBar share a common foundation (`markdown-shared.css`) while allowing component-specific customizations for different contexts. This approach maintains consistency where needed while preserving the flexibility to optimize each component for its specific use case.

## Design Principles

### OKLAB Color Mixing
We use modern OKLAB color space for perceptually uniform color blending:
```css
color-mix(in oklab, var(--color-muted) 40%, transparent)
```

This provides smoother, more natural color transitions compared to RGB mixing, especially important for:
- Table row striping
- Hover states on interactive elements
- Loading overlays

### Component-Specific Variations
Different contexts require different optimizations:
- **Editor**: Optimized for long-form writing
- **Website Viewer**: Displays external content with larger visuals
- **Scratchpad**: Compact spacing for quick notes in a popover
- **Chat/File Viewer**: Simple read-only display

## Shared Styles

All markdown components use shared styles defined in:
```
/frontend/src/lib/styles/markdown-shared.css
```

### What's Shared

**Headings** (all 5 components):
- **H1**: 2em, bold (700), margin-top: 0, margin-bottom: 0.3rem
- **H2**: 1.5em, semibold (600), margin-top: 1rem, margin-bottom: 0.3rem
- **H3**: 1.25em, semibold (600), margin-top: 1rem, margin-bottom: 0.3rem
- **H4**: 1.125em, semibold (600), margin-top: 1rem, margin-bottom: 0.3rem
- **H5**: 1.0625em, semibold (600), margin-top: 1rem, margin-bottom: 0.3rem
- **H6**: 1em, semibold (600), margin-top: 1rem, margin-bottom: 0.3rem
- All headers use `line-height: 1.3` and `rem` units for consistent absolute spacing
- H2-H6 use uniform 1rem top margin for predictable hierarchy

**Paragraphs** (all 5 components):
- Margins: 0.5rem top and bottom (rem units for consistency)
- Line height: 1.7 (comfortable reading)

**Lists** (all 5 components):
- ul/ol margins: 0.5rem top/bottom, 1.5em padding-left
- Nested lists: No extra margin (margin: 0)
- List items: margin: 0, line-height: 1.4 (tighter than paragraphs)
- Paragraphs within list items: margin: 0
- List style types: disc for ul, decimal for ol

**Code Blocks** (all 5 components):
- Inline code: muted background, 0.2em/0.4em padding, 0.875em font-size, monospace font
- Strong text: font-weight: 700
- Pre blocks: muted background, 1em padding, rounded corners, overflow-x auto, 1em margins
- Pre code: transparent background, no padding, line-height: 1.5

**Blockquotes** (all 5 components):
- 3px left border, 1em padding-left, 1em top/bottom margins
- Muted foreground color for subtle appearance

**Tables** (all 5 components):
- Consistent borders (1px solid) with `!important` to ensure visibility
- Body cell padding: `0.5em` vertical, `0.75em` horizontal
- Header cells: Enhanced visual distinction with:
  - Darker background using OKLAB color mixing (8% foreground blended in)
  - Increased padding: `0.65em` vertical (vs `0.5em` for body cells)
  - Thicker bottom border: `2px` (vs `1px` for other borders)
  - Bold font weight (600)
- Even-row striping using OKLAB color mixing (40% muted, 60% transparent)
- Smaller font size: `0.95em`

**Task Lists** (editor and scratchpad only):
- Flexbox layout for checkbox alignment with `!important` flags
- `list-style: none !important` to remove bullet points
- `display: flex !important` for inline checkbox and text
- Strikethrough + muted color for completed items
- Completed items fade with `opacity: 0.6` for visual de-emphasis
- Theme-aware checkbox accent color (uses `var(--color-foreground)`)
- Nested task list support with proper indentation

## Component Variations

### MarkdownEditor.svelte
**Purpose**: Main note editor for long-form writing

**Key Characteristics**:
- Max width: `85ch` (optimal line length for readability)
- Full editing capabilities including task lists
- Component-specific: italic (`em`) and horizontal rule (`hr`) styling only

**Location**: `/frontend/src/lib/components/editor/MarkdownEditor.svelte`

### WebsitesViewer.svelte
**Purpose**: Display external website content

**Key Characteristics**:
- Max width: `856px` (wider than editor for large visuals)
- Images: Larger max dimensions (`720px` width, `500px` height)
- Galleries: Fixed 2-column layout (`49%` width each)
- YouTube transcript button system (5 states with animations)
- Link configuration: Opens in new tab with security attributes

**Custom Features**:
1. **YouTube Transcript Buttons**:
   - Default state: Solid button with hover effect
   - Queued state: Animated orange pulsing dot
   - Busy/disabled states with reduced opacity
   - OKLAB color mixing for hover effects

2. **Image Galleries**:
   - Forces exactly 2 images per row (unlike flexible grid in editor)
   - Centered flexbox layout with consistent gap

**Location**: `/frontend/src/lib/components/websites/WebsitesViewer.svelte`

### scratchpad-popover.svelte
**Purpose**: Quick notes in compact popover

**Key Characteristics**:
- Max height: `min(85vh, 720px)` (constrained by popover)
- Component-specific: horizontal rule (`hr`) styling only
- Uses all shared styles for consistent markdown rendering

**Location**: `/frontend/src/lib/components/scratchpad-popover.svelte`

### ChatMarkdown.svelte
**Purpose**: Render markdown in chat messages

**Key Characteristics**:
- Read-only display
- Prose styling classes
- Uses all shared styles with no component-specific overrides
- Task lists supported

**Location**: `/frontend/src/lib/components/chat/ChatMarkdown.svelte`

### FileMarkdown.svelte
**Purpose**: Display uploaded markdown files

**Key Characteristics**:
- Read-only display
- Prose styling classes
- Uses all shared styles with no component-specific overrides
- Supports image galleries and captions
- Task lists supported

**Location**: `/frontend/src/lib/components/files/FileMarkdown.svelte`

## Custom TipTap Extensions

### ImageGallery
Flexible grid layout for multiple images with optional captions.

**Usage**:
```markdown
![Caption 1](image1.jpg)
![Caption 2](image2.jpg)
![Caption 3](image3.jpg)
```

**Styling Notes**:
- Website viewer forces 2-column layout
- Editor uses flexible grid (auto-fills based on image sizes)

### ImageWithCaption
Single image with figure/figcaption structure from title attribute.

**Configuration**:
- `inline: false` - Block-level display
- `allowBase64: true` - Supports base64-encoded images

### VimeoEmbed
Custom Vimeo iframe rendering with 16:9 aspect ratio.

**Usage**:
```markdown
[Vimeo](https://vimeo.com/123456)
```

### TaskList & TaskItem
Interactive checkboxes for task management (editor and scratchpad only).

**Configuration**:
- `nested: true` - Supports nested task lists
- Theme-aware checkbox color: `var(--color-foreground)`

## Maintenance Guidelines

### Adding New Markdown Components

1. **Import shared styles**:
   ```css
   @import '$lib/styles/markdown-shared.css';
   ```

2. **Choose appropriate class name**:
   - Use semantic names: `.{component}-markdown` or `.{component}-editor`
   - Follow existing patterns: `.chat-markdown`, `.file-markdown`, etc.

3. **Add component-specific overrides**:
   - Document why the variation exists
   - Use OKLAB for color mixing
   - Maintain consistency with design principles

### Updating Shared Styles

When updating styles in `markdown-shared.css`:

1. **Consider impact**: Changes affect all 5 components
2. **Test thoroughly**: Check editor, viewer, scratchpad, chat, and file viewer
3. **Document changes**: Update this file and inline comments
4. **Maintain backward compatibility**: Avoid breaking existing layouts

### Theme Integration

All markdown styles use CSS custom properties for theme support:
- `--color-foreground` - Primary text
- `--color-background` - Background
- `--color-muted` - Secondary backgrounds
- `--color-muted-foreground` - Secondary text
- `--color-border` - Borders and dividers
- `--color-primary` - Links and accents

## Common Patterns

### Centering Images
```css
:global(.component-name img) {
  display: block;
  margin-left: auto;
  margin-right: auto;
}
```

### Responsive Max Widths
```css
.content {
  max-width: 85ch;  /* Editor: optimal line length */
  max-width: 856px; /* Viewer: accommodate large visuals */
}
```

### Horizontal Scroll for Multiple Images
```css
.images-container {
  display: flex;
  overflow-x: auto;
  scroll-snap-type: x mandatory;
}

.images-container img {
  scroll-snap-align: center;
}
```

## File Structure

```
frontend/src/lib/
├── styles/
│   └── markdown-shared.css          # Shared table + task list styles
├── components/
│   ├── editor/
│   │   └── MarkdownEditor.svelte    # Main note editor
│   ├── chat/
│   │   └── ChatMarkdown.svelte      # Chat message display
│   ├── files/
│   │   └── FileMarkdown.svelte      # File viewer display
│   ├── websites/
│   │   └── WebsitesViewer.svelte    # Website content display
│   └── scratchpad-popover.svelte    # Quick notes popover
```

## Accessibility Notes

- **Task Lists**: Use semantic `<input type="checkbox">` with proper labels
- **Tables**: Include `<thead>` with `<th>` elements for screen readers
- **Links**: External links include `rel="noopener noreferrer"` for security
- **Focus States**: Editable areas have clear focus indicators

## Performance Considerations

- **OKLAB**: Modern browsers only (graceful degradation for older browsers)
- **Scroll Snap**: Progressive enhancement (works without for older browsers)
- **Image Loading**: Consider lazy loading for galleries with many images
- **Editor Instances**: TipTap instances are properly destroyed on unmount

## Implementation Notes

### CSS Import Method
**Important**: Shared styles are imported via `app.css`, NOT within component `<style>` blocks.

Svelte's component `<style>` blocks don't properly process `@import` statements, which would prevent shared styles from loading. The correct approach:

```css
/* ✅ Correct: app.css */
@import "./lib/styles/markdown-shared.css";

/* ❌ Wrong: Component <style> blocks */
<style>
  @import '$lib/styles/markdown-shared.css'; /* This doesn't work! */
</style>
```

### Use of `!important`
Several styles use `!important` to override TipTap's default styles and ensure consistent rendering:

- **Table borders**: Ensures borders are always visible across all themes
- **Table padding**: Prevents default padding from being overridden
- **Task list styling**: Removes default bullet points and ensures flexbox layout
- **Completed task color**: Ensures proper muted color on checked items
- **Header background**: Ensures darker background isn't overridden

This is intentional and necessary for reliable cross-component styling.

### Styling Strategy
1. **Global import**: Shared styles loaded once in `app.css`
2. **Specificity**: Use class selectors (`.tiptap`, `.chat-markdown`, etc.)
3. **Override protection**: `!important` on critical properties
4. **OKLAB mixing**: For perceptually uniform color blending
5. **Theme variables**: All colors use CSS custom properties

## Future Considerations

### Potential Optimizations
1. **Code Block Syntax Highlighting**: Consider adding Prism or Highlight.js
2. **Math Rendering**: Add KaTeX for mathematical expressions
3. **Mermaid Diagrams**: Support diagram rendering
4. **Table Editing**: Enhance table manipulation in editor

### Consolidation Status
- ✅ **Complete**: All core markdown styles fully consolidated as of 2026-01-14
- Remaining component-specific styles are intentional (images, galleries, YouTube features, hr)
- Monitor for new patterns that could be extracted to shared styles
- Consider component-level CSS modules if specificity conflicts arise

---

**Last Updated**: 2026-01-14
**Maintained By**: Frontend Team

## Change Log

### 2026-01-14
- Added complete H1-H6 heading hierarchy to shared styles
  - H4: 1.125em, H5: 1.0625em, H6: 1em (all headers now styled)
  - All headers use semibold (600) except H1 (bold 700)
  - Consistent line-height: 1.3 across all heading levels
- Normalized header spacing with rem units
  - Switched from em to rem for predictable absolute spacing
  - H2-H6 top margin: 1rem (was 1.5em, which varied by header size)
  - All header bottom margins: 0.3rem (was 0.5rem)
- Standardized paragraph margins and line-height
  - Added 0.5rem top/bottom margins to shared styles (rem units)
  - Added line-height: 1.7 to shared styles
  - Removed duplicates from MarkdownEditor (was 0.75em) and scratchpad (was 0.5em)
- Standardized all list styles across components
  - ul/ol margins: 0.5rem, padding: 1.5em
  - List items: line-height 1.4 (tighter than paragraphs)
  - Nested lists: margin 0
  - Paragraphs in lists: margin 0
- Standardized code block styles
  - Inline code: muted background, 0.2em/0.4em padding, monospace font
  - Pre blocks: muted background, 1em padding, rounded corners
  - Pre code: line-height 1.5
- Standardized blockquote styles
  - 3px left border, 1em padding/margins, muted color
- Complete consolidation: All components now use shared styles for paragraphs, lists, code, and blockquotes
- Updated documentation to reflect comprehensive standardization

### 2026-01-13
- Initial consolidation of duplicate markdown styles into shared file
- Fixed table border visibility and padding issues
- Enhanced table header visual distinction (darker bg, thicker border, more padding)
- Fixed task list rendering (removed bullet points, inline layout)
- Added opacity fade to completed tasks (0.6)
- Fixed CSS import method (moved to app.css from component blocks)
- Updated documentation with implementation notes and styling strategy
