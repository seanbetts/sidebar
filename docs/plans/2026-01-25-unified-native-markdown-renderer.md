# Unified Native Markdown Renderer

**Created:** 2026-01-25
**Platform:** iOS 26+ / macOS 26+
**Status:** Complete (core implementation)

---

## Overview

Migrate from a dual-renderer architecture (MarkdownUI for read mode, native `TextEditor` for edit mode) to a single native `AttributedString`-based renderer for both modes. This eliminates visual inconsistencies between read and edit modes while preserving all custom features.

## Current Architecture

```
Read Mode:  markdown → MarkdownUI → styled SwiftUI views
Edit Mode:  markdown → MarkdownImporter → AttributedString → TextEditor
```

**Problems:**
- Visual inconsistencies between modes (fonts, spacing, colors)
- Two separate styling systems to maintain
- Round-trip through markdown can lose formatting nuances

## Target Architecture

```
Both Modes: markdown → MarkdownImporter → AttributedString → TextEditor (editable or read-only)
```

**Benefits:**
- Perfect visual consistency
- Single styling system
- Simpler codebase
- Native text selection and accessibility

---

## Feature Audit

### Already Supported by Native Editor

| Feature | Status | Notes |
|---------|--------|-------|
| Headings (H1-H6) | ✅ Complete | Font sizes match MarkdownUI theme |
| Bold | ✅ Complete | `.stronglyEmphasized` intent |
| Italic | ✅ Complete | `.emphasized` intent |
| Strikethrough | ✅ Complete | With secondary color |
| Inline code | ✅ Complete | Monospace font, muted background |
| Code blocks | ✅ Complete | No syntax highlighting (matches current) |
| Links | ✅ Complete | Accent color, underlined |
| Bullet lists | ✅ Complete | With presentation intent |
| Ordered lists | ✅ Complete | With presentation intent |
| Task lists | ✅ Complete | Checkbox markers |
| Blockquotes | ✅ Complete | Secondary color, needs border |
| Tables | ✅ Complete | Basic support via presentation intent |
| Horizontal rules | ✅ Complete | Thematic break intent |
| Blank lines | ✅ Complete | Preserved via `.blankLine` block kind |

### Features Requiring Rebuild

| Feature | Priority | Complexity | Notes |
|---------|----------|------------|-------|
| Image galleries | High | Medium | Custom HTML block rendering, grid layout |
| Inline images | High | Low | Use `AdaptiveImageGlyph` with remote URLs |
| Image captions | Medium | Low | Already parsed, needs styling |
| Blockquote border | ✅ Done | - | Handled by `PresentationIntent` natively |
| Code block border/radius | Low | Low | Visual polish |
| Table alternating rows | Low | Medium | Visual polish |

---

## Implementation Plan

### Phase 1: Hybrid Block Renderer

Create a hybrid view that renders text blocks with `TextEditor`/`Text` and special blocks (galleries, images) as native SwiftUI views.

#### 1.1 Define Block Segment Model

```swift
enum MarkdownSegment {
    case text(AttributedString, Range<String.Index>)
    case gallery(MarkdownRendering.MarkdownGallery)
    case image(url: URL, alt: String, caption: String?)
}
```

#### 1.2 Create Segment Splitter

Extend `MarkdownImporter` to identify segments that need special rendering:

```swift
struct MarkdownImportResult {
    let segments: [MarkdownSegment]
    let frontmatter: String?
}
```

**Implementation:**
- Parse markdown normally
- Scan for gallery HTML blocks and standalone images
- Split `AttributedString` at these boundaries
- Return ordered list of segments

#### 1.3 Create Hybrid Container View

```swift
struct HybridMarkdownView: View {
    let segments: [MarkdownSegment]
    let isEditing: Bool
    @Binding var attributedContent: AttributedString
    @Binding var selection: AttributedTextSelection

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(segments.indices, id: \.self) { index in
                    switch segments[index] {
                    case .text(let attributed, _):
                        if isEditing {
                            // Editable text segment
                            TextEditor(text: segmentBinding(index), selection: $selection)
                        } else {
                            // Read-only text segment
                            Text(attributed)
                        }
                    case .gallery(let gallery):
                        MarkdownGalleryView(gallery: gallery)
                            .disabled(isEditing) // Prevent editing gallery
                    case .image(let url, let alt, let caption):
                        MarkdownImageView(url: url, alt: alt, caption: caption)
                    }
                }
            }
        }
    }
}
```

**Challenge:** Managing selection and editing across multiple `TextEditor` instances.

**Alternative approach:** Use a single `TextEditor` and render images/galleries as attachments or overlays positioned relative to placeholder text.

---

### Phase 2: Inline Image Support

iOS 26's `AdaptiveImageGlyph` supports remote URLs, making inline images straightforward.

#### 2.1 Update MarkdownImporter

When encountering `![alt](url)` syntax, create an `AdaptiveImageGlyph`:

```swift
case let image as Markdown.Image:
    if let source = image.source, let url = URL(string: source) {
        let glyph = AdaptiveImageGlyph(url: url)
        var imageString = AttributedString(glyph)
        // Apply any needed attributes (alt text as accessibility label, etc.)
        return imageString
    }
    // Fallback to text representation
    return AttributedString("![\(image.plainText)](\(image.source ?? ""))")
```

#### 2.2 Image Size Constraints

Apply size constraints to prevent images from being too large:
- Use `MarkdownFormattingDefinition` constraints if available
- Or apply max size during import

#### 2.3 Gallery Images

For gallery blocks, each image in the gallery can use `AdaptiveImageGlyph`:
- Parse gallery HTML block
- Create attributed string with multiple glyphs
- Apply gallery-specific layout (may still need hybrid approach for grid layout)

---

### Phase 3: Visual Polish

Bring native editor styling to parity with MarkdownUI theme.

#### 3.1 Blockquote Border

✅ **Already handled** - `PresentationIntent.blockQuote` renders borders natively. No custom work needed.

#### 3.2 Code Block Styling

✅ **Basic styling complete** - Monospace font and muted background color applied via importer.

**Deferred:** Rounded corners and borders would require custom view rendering outside of TextEditor, which adds complexity. The native styling is acceptable for now.

#### 3.3 Table Styling

✅ **Basic styling complete** - Tables rendered via `PresentationIntent.table`.

**Deferred:** Alternating row colors, header backgrounds, and borders would require custom rendering. Native styling is acceptable for now.

---

### Phase 4: Edit Mode Refinements

#### 4.1 Focus Management

✅ **Complete** - Tapping the TextEditor naturally focuses it and enters edit mode. Focus state is tracked via `@FocusState`.

#### 4.2 Read-Only Mode Behavior

✅ **Complete** - Using single TextEditor that gains focus on tap to enter edit mode. Escape key exits edit mode and removes focus.

#### 4.3 Seamless Mode Transitions

✅ **Complete** - No view switching means scroll position is naturally preserved. Same TextEditor is used throughout.

---

### Phase 5: Migration and Cleanup

#### 5.1 Feature Flag

✅ **Already exists** - `useNativeMarkdownEditor` flag controls whether native editor is used.

#### 5.2 Update NativeMarkdownEditorContainer

✅ **Complete** - Container uses single TextEditor for both read and edit modes. Focus triggers edit mode, escape exits.

#### 5.3 Remove MarkdownUI from Notes

✅ **Complete** - Notes on iOS 26+ use `NativeMarkdownEditorContainer` which doesn't use MarkdownUI. The `SideBarMarkdownContainer` fallback remains for older iOS versions.

**Note:** `SideBarMarkdown` is kept for other features (chat, websites, file viewer, memories) which still use MarkdownUI.

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Gallery grid layout in TextEditor | Medium | Medium | May need hybrid approach for complex layouts |
| Performance with large documents | Low | Medium | Use `LazyVStack`, measure and optimize |
| Performance with many images | Low | Medium | Lazy loading, image caching |
| Visual regression | Low | Low | Side-by-side comparison during development |

---

## Success Criteria

1. **Visual consistency:** Read and edit modes are visually identical
2. **Feature parity:** All current MarkdownUI features work in native renderer
3. **Performance:** No perceptible lag when switching modes or scrolling
4. **Edit experience:** Cursor, selection, and keyboard work correctly
5. **Round-trip fidelity:** Markdown survives import/export without data loss

---

## Confirmed Capabilities

- **AdaptiveImageGlyph** supports remote image URLs - can use for inline images
- **TextEditor** allows text selection in read-only mode - no custom work needed
- **PresentationIntent.blockQuote** renders borders natively - no custom styling needed

## Open Questions

1. Should we migrate chat markdown rendering too, or keep MarkdownUI there?

---

## Timeline Estimate

| Phase | Effort |
|-------|--------|
| Phase 1: Hybrid Block Renderer | Medium |
| Phase 2: Inline Image Support | Low (AdaptiveImageGlyph works) |
| Phase 3: Visual Polish | Low |
| Phase 4: Edit Mode Refinements | Low |
| Phase 5: Migration and Cleanup | Low |

---

## References

- [WWDC25 Session 280: Building Rich SwiftUI Text Experiences](https://developer.apple.com/wwdc25/280/)
- [Apple Sample Code: SampleRecipeEditor](https://developer.apple.com/documentation/swiftui/building-rich-swiftui-text-experiences)
- Current implementation: `docs/plans/2026-01-24-native-attributedstring-rich-text-editor.md`
