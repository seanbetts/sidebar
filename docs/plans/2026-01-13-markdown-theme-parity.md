# Markdown Theme Parity (Web -> SwiftUI)

## Goal
Match the SwiftUI markdown editor appearance to the existing web TipTap styling, using our own theme (not GitHub defaults).

## Web Styling Sources
- Editor block styles: `frontend/src/lib/components/editor/MarkdownEditor.svelte`
- Shared media styles: `frontend/src/app.css`
- Color tokens: `frontend/src/app.css` (`--color-*` values)

## Core Typography + Spacing
Web rules (TipTap):
- Body text: `line-height: 1.7` with `p` margins `0.75em 0`.
- Headings:
  - H1: `font-size: 2em`, `font-weight: 700`, `margin-bottom: 0.5em`.
  - H2: `font-size: 1.5em`, `font-weight: 600`, `margin: 0.5em 0`.
  - H3: `font-size: 1.25em`, `font-weight: 600`, `margin: 0.5em 0`.
- Lists: `padding-left: 1.5em`, list item `line-height: 1.4`, list margins `0.75em 0`.
- Blockquote: left border `3px solid --color-border`, `padding-left: 1em`, `margin: 1em 0`, muted text color.
- Horizontal rule: `border-top: 1px solid --color-border`, `margin: 2em 0`.

## Inline Code + Code Blocks
- Inline code: background `--color-muted`, `padding: 0.2em 0.4em`, `radius: 0.25em`, `font-size: 0.875em`.
- Code blocks:
  - Background `--color-muted`
  - Padding `1em`
  - Radius `0.5em`
  - Margin `1em 0`
  - Monospace font, `font-size: 0.875em`.

## Tables
- Table width 100%, `border-collapse: collapse`, `margin: 1em 0`, `font-size: 0.95em`.
- Cell borders `1px solid --color-border`, padding `0 0.75em`.
- Thead background `--color-muted`, `font-weight: 600`.
- Zebra rows: `color-mix(--color-muted 40%, transparent)`.

## Links
- Color: `--color-primary`.
- Underlined.

## Media (Images/Galleries)
From `frontend/src/app.css`:
- Images in paragraphs are centered with horizontal scrolling and padding.
- Images max-height `350px`, max-width `80%`, padding `0.5rem`.
- Image captions: `font-size: 0.85rem`, muted text color, centered.
- Image gallery: flex grid with `gap: 0.75rem`, image width `240px`.

## SwiftUI Token Mapping
Use existing `DesignTokens`:
- `--color-foreground` -> `DesignTokens.Colors.textPrimary`
- `--color-muted-foreground` -> `DesignTokens.Colors.textSecondary`
- `--color-muted` -> `DesignTokens.Colors.muted`
- `--color-border` -> `DesignTokens.Colors.border`
- `--color-primary` -> `Color.accentColor`
- Spacing scale: `DesignTokens.Spacing` (map `0.75em` ~ `12-16` px depending on font size)
- Radii: `DesignTokens.Radius.xs = 6` (~0.375rem), `Radius.sm = 10` (~0.625rem)

## Implementation Notes
- Build a `MarkdownTheme` struct in Swift with typography + spacing constants.
- Apply theme via `NSAttributedString` attributes (font, paragraph style, background, etc.) when rendering in `MarkdownFormatting`.
- For list and quote indentation, use `NSMutableParagraphStyle` with `headIndent` and `firstLineHeadIndent`.
- Preserve `maxWidth: 85ch` for the editor content container (already applied in SwiftUI).

## Open Questions
- Should inline code use a slightly smaller font or same size as body?
- Should H1/H2/H3 use custom fonts or system styles with size overrides?
- Do we mirror link hover behavior on macOS (underline remains)?
