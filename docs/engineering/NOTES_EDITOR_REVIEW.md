# Notes Rich-Text Editor: Code Review Assessment

**Date:** 2026-03-15
**Scope:** Caret movement, empty trailing blocks, typing attribute inheritance, block ownership at document boundaries, structural soundness for lists and future block editing.

## Architecture Summary

The editor is a two-layer bridge:

1. **Semantic document model** (`NotesSemanticDocument`) — blocks with typed content and inline segments
2. **NativeNoteEditorViewModel** — `AttributedString`-based live editor state (`@Published attributedContent`, `@Published selection`)
3. **UIKitNoteTextEditorSurface** — `UIViewRepresentable` hosting a `UITextView`, synced to the view model via `updateUIView` and delegate callbacks

The coordinator guards the sync loop with `isApplyingProgrammaticText` / `isApplyingProgrammaticSelection` flags and a `RenderSignature` comparison to skip redundant `attributedText` assignments.

The architecture is coherent for simple paragraph/heading documents but has structural issues in the bridge layer that produce the reported bugs and will compound as list/table support is added.

---

## Findings by Severity

### Critical

---

#### C1. Inter-block `"\n"` carries no attributes — root cause of tall caret, typing attribute leakage, and decode ambiguity

**File:** `NotesAttributedDocumentCodec.swift:18-29`

The encoder emits a bare `AttributedString("\n")` between blocks:

```swift
if index > 0 {
    attributed.append(AttributedString("\n"))
}
```

This separator carries no `noteBlock` marker, no `NSParagraphStyle`, and no font. Three direct consequences:

1. **Tall caret on trailing empty line.** UIKit inherits the preceding run's paragraph style for a separator with no `NSParagraphStyle`. An empty paragraph after a heading displays at heading line height with a heading-sized caret.
2. **Typing attribute leakage into the next block.** When the caret sits just after the last character of a heading block, `typingAttributes` reads the attributes at (or just before) the insertion point. The bare `"\n"` creates no clean run boundary, so UIKit reads back the heading's bold, oversized font. The first character typed in the new paragraph inherits heading formatting.
3. **Decode scan ambiguity.** The `noteBlock` attribute on the separator is the sole block boundary signal available to the decoder. Any UIKit-internal mutation of that separator run (autocorrect, input composition, spell check) can silently corrupt block structure.

This is the root cause of the entire class of tall-caret and bold-leakage bugs.

---

#### C2. `applyTypingAttributes(for:)` is a no-op on attributed string storage at empty insertion points

**File:** `NativeNoteEditorViewModel+BlockEditing.swift:8-37`
**File:** `NativeNoteEditorViewModel+Formatting.swift:395-409`

`applyDocumentMutation` calls `applyTypingAttributes(for: typingBlockType)` after placing the insertion point in a new empty paragraph. This calls `transformSelectionAttributes`, which calls `attributedContent.transformAttributes(in: &updatedSelection, body: update)`. When the selection is an empty insertion point, `transformAttributes` on an empty range modifies nothing in the attributed string's character storage. The typing attributes go only into the `AttributedTextSelection` object's embedded typing attribute container.

The `shouldChangeTextIn` path explicitly sets `textView.typingAttributes` (line 329), which does land correctly. However, any path that reads typing attributes from the attributed string (rather than from the selection object) observes stale heading attributes at that position. Specifically:

- `updateUIView` calls `bridgedTypingAttributes(from: viewModel.attributedContent)`, which samples the attributed string at the insertion position
- Between the return key and the first typed character, if `updateUIView` fires, it can overwrite the correct typing attributes with stale heading attributes read from the string

This is the immediate cause of "first typed character after Return is bold."

---

### High

---

#### H1. Unguarded window in `shouldChangeTextIn` between `handleReturnKey` and the `isApplyingProgrammaticText` flag

**File:** `UIKitNoteTextEditorSurface.swift:291-331`

In `shouldChangeTextIn` for a return key, the sequence is:

1. Update `viewModel.selection`, call `handleSelectionChange()` (line 299-301)
2. Call `handleReturnKey()` — synchronously mutates `viewModel.attributedContent` and `viewModel.selection`
3. Set `isApplyingProgrammaticText = true`
4. Assign `textView.attributedText = bridgedText`
5. Set `isApplyingProgrammaticText = false`
6. Assign `textView.selectedRange`

Between steps 1 and 3, UIKit may fire `textViewDidChangeSelection` as a side effect of step 2 or internal processing. During that window the flag is not set. If `textViewDidChangeSelection` fires, it calls `handleSelectionChange()` on the view model's state from step 2, which is inconsistent with the UITextView's current state.

---

#### H2. `replaceAttributedContent` loses all block-level semantics on UIKit-injected plain text runs

**File:** `NativeNoteEditorViewModel+Loading.swift:47-65`

Autocorrect, dictation, and paste of plain text produce `NSAttributedString` runs with no `noteBlock` attribute. `replaceAttributedContent` converts via `AttributedString(text, including: \.noteTextEditor)`. Those runs arrive with no `noteBlock` marker. `constrainEditorDocument` then infers block type from positional heuristics (presence of prior newline, first paragraph = title). Any autocorrect replacement inside the first paragraph will be silently retyped as `.title`, regardless of what was there before.

---

#### H3. UIKit-appended trailing newline creates phantom paragraph that grows on each save cycle

**File:** `NotesAttributedDocumentCodec+Decoding.swift:87-92`

The encoder places `"\n"` between blocks but never after the last block. The decoder creates an empty paragraph when `endedWithStructuralNewline` is true. For a clean encode/decode round trip this is correct.

However, UIKit can internally append a trailing newline to `UITextView.attributedText`. When that happens, `replaceAttributedContent` stores the trailing newline, and the decoder creates a phantom empty paragraph on the next save/load cycle. This is a latent data corruption bug that can grow with each edit-save cycle.

---

#### H4. Redundant `attributedText` re-application after user typing causes caret jump

**File:** `UIKitNoteTextEditorSurface.swift:152-169`

In `textViewDidChange`, the coordinator calls `viewModel.replaceAttributedContent()`, which updates `@Published attributedContent`. This triggers SwiftUI's `updateUIView`, which computes a new `RenderSignature` via `currentCanonicalContent()`. Since the content just changed, the signature mismatches `lastAppliedRenderSignature`, so `textView.attributedText` is set again, even though the text view already has the correct content.

UIKit's `attributedText` setter internally moves the insertion point to the end of the document. The `isApplyingProgrammaticSelection` guard restores it on the next pass, but there can be a visible frame where the caret snaps to end-of-document and back.

The deeper issue: `constrainedEditorDocument` is not guaranteed to be idempotent when applied to live `attributedContent`. If it normalizes anything (e.g., a font that UIKit mutated), it produces a different canonical representation than what was just applied, forcing a re-apply. **There is no test asserting that `currentCanonicalContent()` called twice on unmodified content returns the same value.**

---

#### H5. `currentPersistenceSnapshot` runs full constraint normalization on every `updateUIView` call

**File:** `NativeNoteEditorViewModel+Persistence.swift:31-41`
**File:** `UIKitNoteTextEditorSurface.swift:153`

`updateUIView` calls `viewModel.currentCanonicalContent()` to build the `RenderSignature`. This calls `currentPersistenceSnapshot()` which runs `constrainedEditorDocument(from:)`, the full constraint pass over the entire attributed string. This runs on every SwiftUI update pass (every keystroke, every selection change). The equality check guards the expensive `attributedText` re-apply but not the cost of computing what to compare against.

---

#### H6. `selectionLineSpan` is O(n) in document character count and fires on every keystroke

**File:** `NativeNoteEditorViewModel+Selection.swift:173-212`

`selectionLineSpan` iterates character by character from `text.startIndex` to the selection index. It is called from `handleContentChange`, `handleSelectionChange`, `applyFormatting`, `applyTextStyle`, `applyDocumentMutation`, and `finalizeNativeEditorMutation`. This is a performance regression waiting to become visible on medium-length notes.

---

### Medium

---

#### M1. `applyInlineFormattingState` does not write `noteBlock` — attributes at an unmarked insertion point lose block identity

**File:** `NativeNoteEditorViewModel+Styling.swift:42-64`

`applyInlineFormattingState` writes font, underline, and strikethrough but not `noteBlock`. When a user toggles bold at an empty insertion point whose typing attributes came from an unmarked separator run (C1), the result is a bold body-size font with no `noteBlock` marker. Any subsequently typed character carries that state, and the round-trip decoder will infer its block type from the positional heuristic.

---

#### M2. `inheritedFormattingStateAtInsertionPoint` is accidentally correct and fragile

**File:** `NativeNoteEditorViewModel+Formatting.swift:256-274`

When the caret is at the start of a paragraph block (immediately after the inter-block `"\n"`), `previousIndex` points to the bare newline. Because the newline carries no attributes, `formattingRunSnapshots` returns plain state, which is correct by coincidence.

**This method is coupled to C1's bug.** If the separator is fixed to carry the preceding block's attributes (the correct fix for C1), `inheritedFormattingStateAtInsertionPoint` would then return the preceding block's formatting state, causing `isFormattingActive(.bold)` to return true on the new paragraph. C1 and M2 must be fixed together.

---

#### M3. Return-key block transition not triggered on paste of newline-containing text

**File:** `UIKitNoteTextEditorSurface.swift:296`

`shouldChangeTextIn` intercepts `text == "\n"` only. Paste of multi-line text bypasses `handleReturnKey`. `replaceAttributedContent` does not perform block type transitions; it round-trips through UIKit's `NSAttributedString` which carries the heading's font on the pasted newline runs. `constrainEditorDocument` normalizes fonts but not block types (for runs missing `noteBlock`). Pasting a newline into a heading block can produce a new paragraph that the decoder assigns as `.title`.

---

#### M4. Return key with ranged selection bypasses semantic model entirely

**File:** `NativeNoteEditorViewModel+Formatting.swift:152`

`handleReturnKey()` returns `false` for non-empty selections. `shouldChangeTextIn` then returns `true`, letting UIKit insert the newline via default behavior. The subsequent `textViewDidChange` feeds the result through `replaceAttributedContent`, which round-trips through the codec. If the codec doesn't correctly reconstruct block boundaries from UIKit's ad-hoc newline insertion, block structure could be corrupted. This is especially risky with list blocks where visible prefixes (`- `, `1. `) would be treated as content.

---

#### M5. Block range projection in `documentBlockInfos` may diverge for list/blockquote prefix characters

**File:** `NativeNoteEditorViewModel+Formatting.swift:316-340`

`documentBlockInfos` projects each block to plain text via `NotesSemanticDocumentProjection.plainText` and advances a character cursor. Meanwhile, `selectionStartCharacterOffset` reads from `attributedContent.characters`. These are consistent only if there is a perfect 1:1 mapping between projected plain text and attributed string characters. For blocks with a visible prefix (`"- "`, `"> "`), the prefix appears in both, so the cursor should stay aligned, but this is unverified in tests. An off-by-one in prefix handling would cause `splitTextStyleBlock` to cut at the wrong position.

---

#### M6. `constrainDocument` iterates sequentially on collected snapshots — safe only while replacements are equal-length

**File:** `NoteTextFormattingDefinition.swift:42-54`

Snapshots store character offsets, then `replaceSubrange` is called per snapshot on the live string. Equal-length replacement preserves downstream offsets, so this is currently safe. Any future constraint operation that changes character count (e.g., collapsing ligatures, normalizing whitespace) would silently corrupt downstream offsets.

---

#### M7. First-block type resolution uses three different strategies

Three places resolve block type for a nil `noteBlock` marker, each differently:

| Location | Strategy |
|---|---|
| `NormalizeInlineFonts` (line ~112) | Always `.paragraph` |
| `constrainDocument` (line ~223) | Positional: before first `\n` = `.title`, else `.paragraph` |
| `resolvedDecodedBlockType` (line ~183) | First block = `.title`, else `.paragraph` |

If `noteBlock` attributes are stripped (e.g., by paste), these three strategies produce different block types and thus different font sizes for the same content, depending on which codepath runs first.

---

### Low

---

#### L1. `DispatchQueue.main.async` forwarding introduces one-frame lag

**File:** `NotesEditorViewModel.swift:455`

`observeNativeEditor` wraps `objectWillChange` forwarding in `DispatchQueue.main.async`. Both VMs are `@MainActor`, so this is unnecessary and introduces a one-frame delay. Any SwiftUI view reading the outer VM's state will see stale data for one frame after the native VM changes.

---

#### L2. `selectionLineSpan` computed unnecessarily at load time

**File:** `NativeNoteEditorViewModel+Persistence.swift:28`

---

#### L3. Dual SwiftUI/platform font writes have fragile ordering dependency

**File:** `NativeNoteEditorViewModel+BlockEditing.swift:7-37`

`applyTypingAttributes` writes a block-level font then a platform font. `applyInlineFormattingState` writes a body font and a body platform font. Both are called in `applyDocumentMutation` (lines 405-406) in an order where `applyTypingAttributes` is the last writer, which is currently correct. Reversing the call order at any call site produces wrong fonts with no compiler error.

---

#### L4. First-block coercion to `.title` is a silent data mutation on load

**File:** `NotesAttributedDocumentCodec+Decoding.swift:179-192`

A note externally saved with `.heading` as block 0 is silently re-typed as `.title` on first load, and persisted on the next save. `NativeNoteEditorPersistenceTests.swift:testCurrentPersistenceSnapshotNormalizesBlockZeroToTitle` confirms this is intentional, but the behavior is undocumented at the API boundary.

---

#### L5. `index(forUTF16Offset:in:)` creates a full `String` from characters on every call

**File:** `NativeNoteEditorViewModel+Selection.swift:86-95`

This is O(n) and is called during selection sync. Not a problem for short notes, but compounds with H5/H6 for longer documents.

---

## Answers to Specific Questions

### What are the most likely remaining root causes of the caret jumping to end and back?

**Primary cause (H4):** `updateUIView` re-applies `textView.attributedText` after user edits because `constrainedEditorDocument` is not idempotent on live content. The `RenderSignature` comparison sees a different canonical form and triggers a full `attributedText` assignment. UIKit's setter moves the insertion point to end-of-document internally; the programmatic selection restore puts it back, but there's a visible frame in between.

**Contributing cause (H1):** During Return key handling, `textViewDidChangeSelection` can fire in an unguarded window between `handleReturnKey` and the `isApplyingProgrammaticText` flag, causing a stale selection to be applied.

### What causes empty trailing lines inheriting bold/tall caret from prior styled blocks?

**C1.** The inter-block separator carries no `NSParagraphStyle`. UIKit inherits the heading's paragraph style for the separator glyph, which governs the next empty paragraph's line height and caret height.

### What causes typing at the end of a note to unexpectedly become bold?

Two overlapping causes:

1. **C2:** `applyTypingAttributes` at an empty insertion point writes nothing to the attributed string's storage. When `updateUIView` fires between the Return key and the first typed character, `bridgedTypingAttributes` reads heading attributes from the string position, not from the selection's typing container.
2. **C1:** The bare separator means the heading's attributes extend through the separator in the attributed string's run structure. `inheritedFormattingStateAtInsertionPoint` reading at `insertionPoint - 1` sees heading bold.

### Is the current representation of empty trailing blocks structurally flawed?

**Yes**, in two specific ways:

1. **Unowned separator.** The inter-block `"\n"` belongs to no block in the attributed string. This creates an attribute vacuum that UIKit fills with predecessor attributes, producing the entire class of caret and typing attribute bugs.
2. **Empty blocks lose type through codec round-trip.** Empty blocks have zero characters, so they carry zero attributes. On decode, their type defaults to `.paragraph`. An empty trailing heading or list item cannot survive a round-trip. This is fatal for list editing, where empty trailing list items are a normal user state.

### Should we keep patching the current attributed bridge, or redesign?

The bridge is patchable for the immediate bugs, but two structural problems will keep generating new edge cases:

- **Unowned separator:** Every fix to one leakage path leaves others open. The tall-caret fix does not fix typing attribute leakage. The typing attribute fix in `shouldChangeTextIn` does not fix the `updateUIView` path.
- **Non-idempotent canonical content:** `constrainedEditorDocument` applied to `attributedContent` does not always produce the same result as `attributedContent` itself. This forces unnecessary `attributedText` re-applies and the caret jump that follows.

**If the editor will remain paragraph/heading-only:** A targeted separator fix (stamp the preceding block's attributes onto the `"\n"`) plus companion fixes for M2 and C2 can stop the active bleeding. This is ~3 lines in the encoder but requires coordinated changes in at least 3 other locations.

**If lists, tables, or other structured blocks are on the roadmap:** The fundamental issue is that the attributed string is the source of truth, but attributed strings are character-level, not block-level. Patches will keep accumulating. A structural change is warranted.

### If redesign is recommended, what is the smallest viable structural redesign?

**Option A: Targeted separator fix (smaller, tactical)**

In `NotesAttributedDocumentCodec.attributedString(from:baseFontSize:)`, instead of appending bare `AttributedString("\n")`:

1. Copy the preceding block's `noteBlock` marker and `NSParagraphStyle` onto the separator `"\n"`.
2. In UIKit's paragraph style model, the paragraph style on a separator governs the paragraph that *ends* at that separator, which is exactly the preceding block. The next paragraph starts from a clean baseline.
3. The decoder already flushes the current block when it encounters a newline, so a separator with the preceding block's marker round-trips correctly.

Required companion fixes:
- **M2:** `inheritedFormattingStateAtInsertionPoint` must stop reading across block boundaries. It should only read from the current block's content, not from a separator with a different block marker.
- **C2:** After `applyDocumentMutation` places the insertion point in a new empty paragraph, ensure `bridgedTypingAttributes` reads from the selection's typing attribute container rather than from the attributed string at the insertion position.
- **M1:** `applyInlineFormattingState` must write `noteBlock` alongside font attributes.

**Option B: Semantic document as live model (larger, structural)**

1. **Make `NotesSemanticDocument` the live editing model.** All mutations (typing, formatting, Return key) operate on the document's block/segment arrays directly, not on `AttributedString`.
2. **`AttributedString` becomes a derived render artifact.** Computed from the document for display, never parsed back. Remove the decode path from the live editing loop (keep it only for initial load from persistence).
3. **Each block owns its type, content, and cursor affinity.** Empty trailing blocks are just `Block(type: .unorderedList, segments: [])` with no character-level representation needed.
4. **Selection is expressed as `(blockIndex, characterOffset)` pairs** rather than flat character offsets. This eliminates block-ownership ambiguity at boundaries.

**Boundary:** This changes `NativeNoteEditorViewModel` and the `UIKitNoteTextEditorSurface` coordinator. It does NOT require changing the persistence format, the server API, or the SwiftUI view hierarchy. The codec's encode path is kept for persistence; the decode path is kept for hydration. `NoteTextFormattingDefinition` becomes simpler since it only needs to enforce font normalization on the render output, not reconstruct block semantics.

**Recommendation:** If lists are planned, go with Option B. The empty-block-loses-type problem (Finding 2 in this review) is not solvable within the current architecture without increasingly complex workarounds. Option A buys time but does not resolve the fundamental "attributed string as source of truth" limitation.

---

## Test Coverage Gaps

Ordered by risk to the reported bugs:

### Missing tests — caret position after mutations

1. No test verifies where the caret lands *after* `handleReturnKey()`. Block structure is checked but not `selection` in the new block.
2. No test verifies caret position after `applyTextStyle()` changes a block type.
3. No test for caret stability during rapid content changes or concurrent selection updates.
4. No test for caret behavior when deleting across block boundaries.

### Missing tests — typing attributes

5. No test for *inherited* typing attributes when the user places the caret at end-of-document after a heading (the exact scenario from C1/C2).
6. No test verifies typing attributes after a block transition (e.g., after Return exits a heading into a new paragraph, are typing attributes reset to body style?).
7. No test for `bridgedTypingAttributes` correctness at post-return insertion point. Should reflect paragraph-plain, not heading-bold, when called in `updateUIView` after a heading-to-paragraph transition.
8. No test for typing attributes when the caret is placed at the end of an empty document after `loadText("")`.

### Missing tests — empty trailing blocks

9. The one trailing-paragraph test (`testHandleReturnKeyOnEmptyTrailingParagraphAddsAnotherBlankParagraph`) verifies block creation but does NOT verify typing attributes in the new empty block.
10. No test for what happens when the document ends with an empty heading or subheading block (only paragraph is tested).
11. No test for rendering/formatting of empty trailing blocks in the UIKit surface layer.

### Missing tests — data integrity

12. No test asserting that `currentCanonicalContent()` called twice on unmodified `attributedContent` returns the same value (idempotency).
13. No test that `updateUIView` does not re-apply `attributedText` after a heading-to-paragraph return. The existing `testPureSelectionChangesDoNotRewriteUIKitAttributedText` only covers plain-text documents.
14. No test for paste of newline-containing text into a heading block asserting block structure is preserved.
15. No test for autocorrect replacement preserving `noteBlock` attribute on the corrected run.

### Missing tests — block operations

16. No test for mid-block Return key (splitting a paragraph at an interior position).
17. No test for Return key with ranged selection.
18. No test for block merging on backspace/delete across block boundaries.
19. No test for list block transitions (bullet/numbered list entry/exit).

---

## Summary Table

| ID | Severity | File | Description |
|----|----------|------|-------------|
| C1 | Critical | `NotesAttributedDocumentCodec.swift:18-29` | Inter-block `"\n"` carries no attributes; root cause of tall caret and typing leakage |
| C2 | Critical | `NativeNoteEditorViewModel+BlockEditing.swift:8-37` | `applyTypingAttributes` on empty insertion point is no-op on attributed string storage |
| H1 | High | `UIKitNoteTextEditorSurface.swift:291-331` | Unguarded window between `handleReturnKey` and `isApplyingProgrammaticText` flag |
| H2 | High | `NativeNoteEditorViewModel+Loading.swift:47-65` | `replaceAttributedContent` loses `noteBlock` on UIKit-injected plain text |
| H3 | High | `NotesAttributedDocumentCodec+Decoding.swift:87-92` | UIKit trailing newline creates phantom paragraph that grows on save cycles |
| H4 | High | `UIKitNoteTextEditorSurface.swift:152-169` | Non-idempotent `constrainedEditorDocument` causes redundant `attributedText` set and caret jump |
| H5 | High | `NativeNoteEditorViewModel+Persistence.swift:31-41` | `currentPersistenceSnapshot` runs full constraint pass on every `updateUIView` |
| H6 | High | `NativeNoteEditorViewModel+Selection.swift:173-212` | `selectionLineSpan` is O(n) on every keystroke |
| M1 | Medium | `NativeNoteEditorViewModel+Styling.swift:42-64` | `applyInlineFormattingState` does not preserve `noteBlock` marker |
| M2 | Medium | `NativeNoteEditorViewModel+Formatting.swift:256-274` | `inheritedFormattingStateAtInsertionPoint` is accidentally correct; coupled to C1 |
| M3 | Medium | `UIKitNoteTextEditorSurface.swift:296` | Paste of newline-containing text bypasses block transition |
| M4 | Medium | `NativeNoteEditorViewModel+Formatting.swift:152` | Return key with ranged selection bypasses semantic model |
| M5 | Medium | `NativeNoteEditorViewModel+Formatting.swift:316-340` | Block range projection may diverge for list/blockquote prefixes |
| M6 | Medium | `NoteTextFormattingDefinition.swift:42-54` | Sequential `replaceSubrange` safe only while replacements are equal-length |
| M7 | Medium | Multiple files | First-block type resolution uses three inconsistent strategies |
| L1 | Low | `NotesEditorViewModel.swift:455` | `DispatchQueue.main.async` forwarding introduces one-frame lag |
| L2 | Low | `NativeNoteEditorViewModel+Persistence.swift:28` | `selectionLineSpan` computed unnecessarily at load time |
| L3 | Low | `NativeNoteEditorViewModel+BlockEditing.swift:7-37` | Dual font writes have fragile ordering dependency |
| L4 | Low | `NotesAttributedDocumentCodec+Decoding.swift:179-192` | First-block coercion to `.title` is silent data mutation |
| L5 | Low | `NativeNoteEditorViewModel+Selection.swift:86-95` | `index(forUTF16Offset:)` allocates full String copy on every call |
