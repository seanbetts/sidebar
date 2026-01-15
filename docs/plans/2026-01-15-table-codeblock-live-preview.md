# Table + Code Block Live Preview Implementation

## Goal
Render tables and code blocks when the caret is outside, and show raw markdown when the caret is inside.

## Steps
1. Move block-level replacement decorations into a StateField so block widgets are allowed.
2. Implement a table block widget (HTML table) driven by Lezer table nodes; hide markdown lines when inactive.
3. Implement a code block wrapper widget (styled block) driven by FencedCode/CodeBlock nodes; hide markdown lines when inactive.
4. Preserve selection behavior and avoid the scroll/layout bug with minimal DOM churn.
5. Rebuild CodeMirror bundle and validate on iOS.

## Exit Criteria
- Tables render as HTML in read-only and when caret is outside the table.
- Code blocks render with the styled wrapper in read-only and when caret is outside the block.
- Raw markdown shows only when caret is inside the table/code block.
- No scroll-induced decoration drop or CM exceptions.
