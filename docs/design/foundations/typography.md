---
title: Typography
description: The type system for sideBar — AppFontStyle scale, text size preferences, semantic role aliases, and usage rules across native and web.
---

## Purpose

Define the typography system for sideBar: the font scale, how sizes adapt to user preferences, semantic role aliases, and the rules for using type in views. This covers native (iOS/macOS) and web.

---

## How the system works

The native typography system has two layers:

| Layer | What it does | Key files |
|---|---|---|
| **AppFontStyle** | Named scale of font styles. Each style has a base size, weight, and optional Dynamic Type anchor. | `Design/AppFontStyle.swift` |
| **AppTextSizeOption** | In-app text size preference (Small/Medium/System/Large). Applies a scale multiplier on top of the base size. | `Models/AppTextSizeOption.swift` |

The `.appFont()` view modifier combines both layers: it reads the current `AppTextSizeOption` from `@AppStorage` and applies the correct scaled font. **This is the only interface views should use.**

For styles that have a `Font.TextStyle` anchor (e.g. `.body`, `.headline`), the base size is read from the system's Dynamic Type metrics — so it responds to both the system Large Text accessibility setting and the in-app preference. For styles without a `Font.TextStyle` anchor, only the in-app preference applies.

---

## Text size preference

sideBar exposes its own text size control in Settings, independent of the system Dynamic Type setting.

| Option | Scale multiplier | Notes |
|---|---|---|
| Small | 0.80× | |
| Medium | 0.90× | |
| System | 1.00× | Default. Uses system Dynamic Type base sizes where anchored. |
| Large | 1.05× | Slight upscale — not a full accessibility size |

**Note**: This is an app-level preference, not a replacement for system accessibility. Users with system-level Large Text enabled will see both their system preference (via Dynamic Type base sizes) and this multiplier applied. The combination is intentional.

---

## Type scale

### Specimen

<div style={{fontFamily:"-apple-system,BlinkMacSystemFont,sans-serif",border:"1px solid #e0e0e0",borderRadius:"10px",overflow:"hidden",marginBottom:"24px"}}>
  <div style={{padding:"16px 20px",borderBottom:"1px solid #f0f0f0",display:"flex",alignItems:"baseline",justifyContent:"space-between"}}>
    <span style={{fontSize:"22px",fontWeight:"400"}}>The quick brown fox</span>
    <span style={{fontSize:"11px",color:"#aaa",fontFamily:"monospace",flexShrink:"0",marginLeft:"16px"}}>title2 · 22pt regular</span>
  </div>
  <div style={{padding:"16px 20px",borderBottom:"1px solid #f0f0f0",display:"flex",alignItems:"baseline",justifyContent:"space-between"}}>
    <span style={{fontSize:"22px",fontWeight:"600"}}>The quick brown fox</span>
    <span style={{fontSize:"11px",color:"#aaa",fontFamily:"monospace",flexShrink:"0",marginLeft:"16px"}}>title2Semibold · 22pt semibold</span>
  </div>
  <div style={{padding:"16px 20px",borderBottom:"1px solid #f0f0f0",display:"flex",alignItems:"baseline",justifyContent:"space-between"}}>
    <span style={{fontSize:"20px",fontWeight:"600"}}>The quick brown fox</span>
    <span style={{fontSize:"11px",color:"#aaa",fontFamily:"monospace",flexShrink:"0",marginLeft:"16px"}}>title3Semibold · 20pt semibold</span>
  </div>
  <div style={{padding:"16px 20px",borderBottom:"1px solid #f0f0f0",display:"flex",alignItems:"baseline",justifyContent:"space-between"}}>
    <span style={{fontSize:"17px",fontWeight:"400"}}>The quick brown fox</span>
    <span style={{fontSize:"11px",color:"#aaa",fontFamily:"monospace",flexShrink:"0",marginLeft:"16px"}}>headline · 17pt regular</span>
  </div>
  <div style={{padding:"16px 20px",borderBottom:"1px solid #f0f0f0",display:"flex",alignItems:"baseline",justifyContent:"space-between"}}>
    <span style={{fontSize:"16px",fontWeight:"400"}}>The quick brown fox</span>
    <span style={{fontSize:"11px",color:"#aaa",fontFamily:"monospace",flexShrink:"0",marginLeft:"16px"}}>body · 16pt regular</span>
  </div>
  <div style={{padding:"16px 20px",borderBottom:"1px solid #f0f0f0",display:"flex",alignItems:"baseline",justifyContent:"space-between"}}>
    <span style={{fontSize:"16px",fontWeight:"600"}}>The quick brown fox</span>
    <span style={{fontSize:"11px",color:"#aaa",fontFamily:"monospace",flexShrink:"0",marginLeft:"16px"}}>bodySemibold · 16pt semibold</span>
  </div>
  <div style={{padding:"16px 20px",borderBottom:"1px solid #f0f0f0",display:"flex",alignItems:"baseline",justifyContent:"space-between"}}>
    <span style={{fontSize:"15px",fontWeight:"400"}}>The quick brown fox</span>
    <span style={{fontSize:"11px",color:"#aaa",fontFamily:"monospace",flexShrink:"0",marginLeft:"16px"}}>subheadline · 15pt regular</span>
  </div>
  <div style={{padding:"16px 20px",borderBottom:"1px solid #f0f0f0",display:"flex",alignItems:"baseline",justifyContent:"space-between"}}>
    <span style={{fontSize:"14px",fontWeight:"600"}}>The quick brown fox</span>
    <span style={{fontSize:"11px",color:"#aaa",fontFamily:"monospace",flexShrink:"0",marginLeft:"16px"}}>labelMd · 14pt semibold</span>
  </div>
  <div style={{padding:"16px 20px",borderBottom:"1px solid #f0f0f0",display:"flex",alignItems:"baseline",justifyContent:"space-between"}}>
    <span style={{fontSize:"13px",fontWeight:"400"}}>The quick brown fox</span>
    <span style={{fontSize:"11px",color:"#aaa",fontFamily:"monospace",flexShrink:"0",marginLeft:"16px"}}>footnote · 13pt regular</span>
  </div>
  <div style={{padding:"16px 20px",borderBottom:"1px solid #f0f0f0",display:"flex",alignItems:"baseline",justifyContent:"space-between"}}>
    <span style={{fontSize:"12px",fontWeight:"400"}}>The quick brown fox</span>
    <span style={{fontSize:"11px",color:"#aaa",fontFamily:"monospace",flexShrink:"0",marginLeft:"16px"}}>caption · 12pt regular</span>
  </div>
  <div style={{padding:"16px 20px",display:"flex",alignItems:"baseline",justifyContent:"space-between"}}>
    <span style={{fontSize:"11px",fontWeight:"400"}}>The quick brown fox</span>
    <span style={{fontSize:"11px",color:"#aaa",fontFamily:"monospace",flexShrink:"0",marginLeft:"16px"}}>caption2 · 11pt regular</span>
  </div>
</div>

### Full scale reference

| Style | Base size | Weight | Dynamic Type anchor | Notes |
|---|---|---|---|---|
| `title2` | 22pt | Regular | `.title2` | |
| `title2Semibold` | 22pt | Semibold | `.title2` | |
| `title3Semibold` | 20pt | Semibold | `.title3` | |
| `titleLg` | 18pt | Semibold | None | No Dynamic Type anchor |
| `size18Semibold` | 18pt | Semibold | None | Prefer `titleLg` — same values, better name |
| `size16Semibold` | 16pt | Semibold | None | |
| `labelMd` | 14pt | Semibold | None | Standard label weight for list rows, section headers |
| `body` | 16pt | Regular | `.body` | Default prose text |
| `bodySemibold` | 16pt | Semibold | `.body` | |
| `headline` | 17pt | Regular | `.headline` | |
| `subheadline` | 15pt | Regular | `.subheadline` | |
| `subheadlineSemibold` | 15pt | Semibold | `.subheadline` | |
| `callout` | 16pt | Regular | `.callout` | |
| `footnote` | 13pt | Regular | `.footnote` | |
| `footnoteSemibold` | 13pt | Semibold | `.footnote` | |
| `caption` | 12pt | Regular | `.caption` | |
| `captionSemibold` | 12pt | Semibold | `.caption` | |
| `caption2` | 11pt | Regular | `.caption2` | |
| `caption2Semibold` | 11pt | Semibold | `.caption2` | |
| `size10Bold` | 10pt | Bold | None | Badge labels, very small UI only |
| `size24Semibold` | 24pt | Semibold | None | Large display use |
| `size32Regular` | 32pt | Regular | None | Large display use |
| `size32Semibold` | 32pt | Semibold | None | Large display use |
| `monoLabel` | 14pt | Semibold | None | Monospaced. Code labels, tokens |
| `monoBody` | 16pt | Regular | `.body` | Monospaced. Code blocks, inline code |

**Note on size-named styles**: `titleLg`, `size10Bold`, `size16Semibold`, `size18Semibold`, `size24Semibold`, `size32Regular`, and `size32Semibold` use size-based names rather than semantic names. This is a naming gap — these styles describe implementation rather than intent. They should be renamed as the type scale matures. For now, use the closest semantically named style where one exists; fall back to size-named styles only when there is no semantic match.

---

## Semantic role aliases

`SidebarTypography` provides intent-named aliases for the sidebar panel list row context:

| Alias | Resolves to | Use |
|---|---|---|
| `SidebarTypography.primary` | `.body` | Primary row label |
| `SidebarTypography.secondary` | `.caption` | Secondary detail text |
| `SidebarTypography.tertiary` | `.caption2` | Tertiary / de-emphasised text |
| `SidebarTypography.sectionHeader` | `.label` | Section group headers |

This pattern is correct and should be extended to other repeated contexts. Candidates:

| Context | Suggested alias set |
|---|---|
| Chat messages | `ChatTypography.message`, `.timestamp`, `.senderName` |
| Settings rows | `SettingsTypography.label`, `.value`, `.footnote` |
| Notes list | Already covered by `SidebarTypography` |

Creating these aliases means a future decision to change, say, the chat message size requires one line changed in one file rather than a search through views.

---

## Escape hatch

`.appScaledFont(size:weight:design:)` is available for cases where no `AppFontStyle` exists. It applies the `AppTextSizeOption` multiplier to an arbitrary size. Use it sparingly and only when a new `AppFontStyle` case is genuinely not the right answer. In most cases the correct fix is to add a new named style.

---

## Notes document typography

The notes editor uses a separate typography system — `NoteTextStyleTypography` — that is intentionally independent from `AppFontStyle`. Rather than fixed point sizes, it uses scale factors relative to a base body size. This means the entire document hierarchy scales proportionally as the user changes text size, which is the correct approach for document content.

The four block-level styles are defined in `NoteTextStyle`:

<div style={{fontFamily:"-apple-system,BlinkMacSystemFont,sans-serif",border:"1px solid #e0e0e0",borderRadius:"10px",overflow:"hidden",marginBottom:"24px"}}>
  <div style={{padding:"16px 20px",borderBottom:"1px solid #f0f0f0",display:"flex",alignItems:"baseline",justifyContent:"space-between"}}>
    <span style={{fontSize:"30px",fontWeight:"700"}}>Note Title</span>
    <span style={{fontSize:"11px",color:"#aaa",fontFamily:"monospace",flexShrink:"0",marginLeft:"16px"}}>title · 1.75× body · bold</span>
  </div>
  <div style={{padding:"16px 20px",borderBottom:"1px solid #f0f0f0",display:"flex",alignItems:"baseline",justifyContent:"space-between"}}>
    <span style={{fontSize:"24px",fontWeight:"700"}}>Heading</span>
    <span style={{fontSize:"11px",color:"#aaa",fontFamily:"monospace",flexShrink:"0",marginLeft:"16px"}}>heading · 1.40× body · bold</span>
  </div>
  <div style={{padding:"16px 20px",borderBottom:"1px solid #f0f0f0",display:"flex",alignItems:"baseline",justifyContent:"space-between"}}>
    <span style={{fontSize:"20px",fontWeight:"700"}}>Subheading</span>
    <span style={{fontSize:"11px",color:"#aaa",fontFamily:"monospace",flexShrink:"0",marginLeft:"16px"}}>subheading · 1.15× body · bold</span>
  </div>
  <div style={{padding:"16px 20px",display:"flex",alignItems:"baseline",justifyContent:"space-between"}}>
    <span style={{fontSize:"17px",fontWeight:"400"}}>Body text at default system size</span>
    <span style={{fontSize:"11px",color:"#aaa",fontFamily:"monospace",flexShrink:"0",marginLeft:"16px"}}>body · 1.00× · regular</span>
  </div>
</div>

| Style | Scale | Weight | Approx. size at default body |
|---|---|---|---|
| `title` | 1.75× | Bold | approx. 30pt |
| `heading` | 1.40× | Bold | approx. 24pt |
| `subheading` | 1.15× | Bold | approx. 20pt |
| `body` | 1.00× | Regular | approx. 17pt |

The base body size is `MarkdownTypography.defaultBodyFontSize` — the system Dynamic Type body size multiplied by the current `AppTextSizeOption` scale. Both inputs affect all four styles equally, preserving the proportional hierarchy at any size.

Source: `Utilities/NoteTextStyleTypography.swift`, `ViewModels/NoteTextStyle.swift`

---

## Markdown and rich text

Markdown rendering uses `MarkdownTypography`, which derives its base body size from the system Dynamic Type body size and applies the `AppTextSizeOption` multiplier:

- `MarkdownTypography.defaultBodyFontSize` — body text size, platform-aware
- `MarkdownTypography.inlineCodeScale` — 0.875× of body size
- `MarkdownTypography.footnoteScale` — ratio of system footnote to body sizes

Rich text note editing on iOS uses `AppKitNoteTextEditorSurface` / `AttributedNoteEditorContainer`, which receive the current size from `AppTextSizeOption` via `NoteTextDependencies`.

---

## Web typography

The web app uses the system font stack via Tailwind CSS defaults:

```
-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif
```

No custom font is imported. On macOS and iOS browsers this resolves to the system font, aligning visually with native. On other platforms it uses the platform-appropriate system font.

**Rule**: Do not import a web font for general UI text. The system font stack is correct.

Prose and markdown content uses `@tailwindcss/typography`. Rich text editing uses Tiptap 3. Web font sizes are not formally mapped to the native `AppFontStyle` scale — they use Tailwind's default size scale. Formal alignment between web type sizes and the native scale is out of scope for now.

---

## Rules summary

1. **Always use `.appFont()`**. Never use `.font(.system(size:weight:))` directly in views.
2. **Prefer semantically named styles** (`body`, `footnote`, `labelMd`) over size-named ones (`size16Semibold`). If no semantic style fits, use the escape hatch or add a new named case.
3. **Use `SidebarTypography` aliases** in sidebar list row contexts. Do not reference `AppFontStyle` directly in list row views.
4. **Do not use `DesignTokens.Typography`**. It is a dead parallel system — it will be removed. Use `AppFontStyle` via `.appFont()`.
5. **`AppTextSizeOption` scaling is automatic** via the `.appFont()` modifier. Do not read or apply the scale manually.
6. **Monospaced styles** (`monoLabel`, `monoBody`) are for code, tokens, and technical content only. Do not use them for general UI labels.

---

## Scale rationalisation

The current `AppFontStyle` scale has 25 cases. The rationalisation has three goals: remove redundant size-named styles, remove semibold entirely (structural styles use bold; content styles use regular), and remove the redundant caption size. The result is a two-weight system — regular for content, bold for structure.

### Remove

| Style | Reason |
|---|---|
| `title2Semibold` | Semibold weight variant being removed; callers use `titleLg` (regular). |
| `size18Semibold` | Identical to `titleLg` — exact duplicate. |
| `size16Semibold` | Semibold weight variant; callers move to `body`. |
| `bodySemibold` | Semibold weight variant; use size or color for hierarchy instead. |
| `headline` | 17pt regular — absorbed by `subheading` (17pt bold), which takes this size slot with a proper structural role. |
| `subheadline` | 15pt regular — too close to `body` (16pt) to justify. Replaced by `subheading` at 17pt bold. |
| `subheadlineSemibold` | Semibold weight variant; also replaced by `subheading`. |
| `callout` | Same rendered size as `body` (16pt regular). Dynamic Type anchor difference is not meaningful enough to justify a separate style. |
| `footnoteSemibold` | Semibold weight variant; callers use `footnote`. |
| `captionSemibold` | Semibold weight variant; callers use `caption`. |
| `caption2` | 11pt vs 12pt is a negligible distinction; callers use `caption`. |
| `caption2Semibold` | Semibold weight variant; removed with `caption2`. |

### Rename and restructure

| Current name | New name | Change |
|---|---|---|
| `title2` | `titleLg` | Semantic name consistent with title group |
| `title3Semibold` | `titleMd` | Semantic name; semibold becomes bold |
| `titleLg` | `titleSm` | Consistent naming within title group; semibold becomes bold |
| `headline` + `subheadline` | `subheading` | Merged into one 17pt bold style sitting above `body` |
| `labelMd` | `label` | Removes false implication of a size scale; semibold becomes bold |
| `size10Bold` | `badge` | Describes intent |
| `size24Semibold` | `displayMd` | Describes role; semibold becomes bold |
| `size32Regular` | `displayLg` | Describes role; `size32Semibold` collapses into this |
| `size32Semibold` | Remove | Collapses into `displayLg` |
| `monoLabel` | `monoLabel` | Semibold becomes bold |

### Target scale

13 styles, two weights:

| Style | Size | Weight | DT anchor | Role |
|---|---|---|---|---|
| `displayLg` | 32pt | Regular | None | Large display / hero |
| `displayMd` | 24pt | Bold | None | Display / prominent headings |
| `titleLg` | 22pt | Regular | `.title2` | Page/view title |
| `titleMd` | 20pt | Bold | `.title3` | Section heading |
| `titleSm` | 18pt | Bold | None | Sub-section heading |
| `subheading` | 17pt | Bold | None | Content block subheading |
| `body` | 16pt | Regular | `.body` | Default prose and content |
| `label` | 14pt | Bold | None | UI labels, list section headers |
| `footnote` | 13pt | Regular | `.footnote` | Supporting text, metadata |
| `caption` | 12pt | Regular | `.caption` | Small secondary labels |
| `badge` | 10pt | Bold | None | Badge and pip labels only |
| `monoBody` | 16pt | Regular | `.body` | Code blocks, inline code |
| `monoLabel` | 14pt | Bold | None | Code labels, tokens |

---

## Other gaps

| Gap | Notes |
|---|---|
| `DesignTokens.Typography` should be removed | Dead parallel system. Tracked in [implementation-gaps](../implementation-gaps). |
| `SidebarTypography` pattern not extended to other contexts | Chat and Settings rows are the highest-priority candidates. |
| Web type sizes not mapped to native scale | Out of scope for now. |

---

## Related docs

- [Token Model](./token-model)
- [Token Audit](../audits/token-audit)
- [System Inheritance](../system-inheritance)
- [Implementation Gaps](../implementation-gaps)
- [Iconography](./iconography)
