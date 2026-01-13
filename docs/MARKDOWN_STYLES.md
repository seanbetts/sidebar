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
- Line height: `1.7` (comfortable reading)
- Paragraph margins: `0.75em` (standard spacing)
- Full editing capabilities including task lists

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
- Line height: `1.6` (tighter than editor's 1.7)
- Paragraph margins: `0.5em` (tighter than editor's 0.75em)
- List margins: `0.5em` (tighter spacing)
- Optimized for density in small space

**Location**: `/frontend/src/lib/components/scratchpad-popover.svelte`

### ChatMarkdown.svelte
**Purpose**: Render markdown in chat messages

**Key Characteristics**:
- Read-only display
- Prose styling classes
- Minimal component-specific overrides
- No task lists or custom extensions

**Location**: `/frontend/src/lib/components/chat/ChatMarkdown.svelte`

### FileMarkdown.svelte
**Purpose**: Display uploaded markdown files

**Key Characteristics**:
- Read-only display
- Prose styling classes
- Supports image galleries and captions
- No task lists

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

### Consolidation Opportunities
- Minimal duplication remains (by design for component-specific needs)
- Monitor for new patterns that could be extracted to shared styles
- Consider component-level CSS modules if specificity conflicts arise

---

**Last Updated**: 2026-01-13 (22:30 UTC)
**Maintained By**: Frontend Team

## Change Log

### 2026-01-13
- Initial consolidation of duplicate markdown styles into shared file
- Fixed table border visibility and padding issues
- Enhanced table header visual distinction (darker bg, thicker border, more padding)
- Fixed task list rendering (removed bullet points, inline layout)
- Added opacity fade to completed tasks (0.6)
- Fixed CSS import method (moved to app.css from component blocks)
- Updated documentation with implementation notes and styling strategy
