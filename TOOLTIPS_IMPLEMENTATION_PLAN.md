# Tooltip Implementation Plan

## Executive Summary

**Goal**: Add helpful tooltips throughout the sideBar UI to improve discoverability and user experience for new and existing users.

**Current Status**: Tooltip components are already built (shadcn-svelte) but not implemented anywhere in the application. All icon-only buttons currently use browser-default `title` attributes with inconsistent styling and poor UX.

**Impact**: 35+ icon-only buttons across the UI that would benefit from professional tooltips with consistent design, faster appearance, and better accessibility.

**Implementation Time**: ~6 hours (3 phases)

---

## Goals & Benefits

### User Experience Benefits
- **Improved Discoverability**: New users can understand icon-only buttons without trial and error
- **Reduced Cognitive Load**: Tooltips provide context without cluttering the UI
- **Faster Learning Curve**: Users understand complex features (pin, archive, move) immediately
- **Better Accessibility**: Keyboard users get visual feedback, not just screen reader text
- **Professional Polish**: Consistent tooltip design vs. inconsistent browser defaults

### Technical Benefits
- **Leverage Existing Infrastructure**: shadcn tooltip components already built and styled
- **Design System Consistency**: All tooltips follow the same visual pattern
- **Accessibility Compliance**: Built on bits-ui (headless, fully accessible)
- **Smooth Animations**: Fade-in and zoom animations already configured
- **Zero New Dependencies**: bits-ui already installed and used

---

## Baseline Rules

- **Remove `title` attributes** on icon-only buttons to avoid double tooltips.
- **Keep `aria-label`** on icon-only buttons for accessibility.
- **Always use state-aware tooltips** for toggles (pin/unpin, archive/restore).
- **Do not show tooltips on touch/mobile** (disable via pointer type or breakpoint).
- **Default placements**:
  - Left sidebar rail: `right`
  - Top headers/toolbars: `bottom`
  - Bottom inputs (chat): `top`

---

## Shared Copy Strategy

Create a centralized tooltip copy map for reused actions so Notes/Websites/Files stay consistent.

**Suggested location**: `frontend/src/lib/constants/tooltips.ts`

Example shape:
```ts
export const TOOLTIP_COPY = {
  pin: { on: 'Pin to top of list', off: 'Unpin from top' },
  archive: { on: 'Archive', off: 'Restore from archive' },
  copy: { default: 'Copy content', success: 'Copied!' },
  delete: 'Delete',
  rename: 'Rename',
  move: 'Move to folder…',
  download: 'Download as markdown'
};
```

---

## Tooltip Infrastructure Assessment

### ✅ Ready to Use

**Location**: `/frontend/src/lib/components/ui/tooltip/`

**Components Available**:
1. `Tooltip.svelte` - Root wrapper (bits-ui Tooltip.Root)
2. `TooltipTrigger.svelte` - Trigger element (bits-ui Tooltip.Trigger)
3. `TooltipContent.svelte` - Content display with animation and arrow
4. `TooltipProvider.svelte` - Provider component
5. `TooltipPortal.svelte` - Portal handling

**Export Pattern**:
```typescript
// /frontend/src/lib/components/ui/tooltip/index.js
export { default as Tooltip } from './tooltip.svelte';
export { default as TooltipContent } from './tooltip-content.svelte';
export { default as TooltipTrigger } from './tooltip-trigger.svelte';
export { default as TooltipProvider } from './tooltip-provider.svelte';
export { default as TooltipPortal } from './tooltip-portal.svelte';
```

**Current Usage**: ❌ NOT USED ANYWHERE (huge opportunity!)

**Current Pattern**: All buttons use browser-default `title` attributes
```svelte
<Button title="Action description">
  <Icon size={16} />
</Button>
```

**Proposed Pattern**: Replace with tooltip components
```svelte
<Tooltip>
  <TooltipTrigger asChild>
    <Button>
      <Icon size={16} />
    </Button>
  </TooltipTrigger>
  <TooltipContent>Action description</TooltipContent>
</Tooltip>
```

---

## Component Inventory & Priorities

### Phase 1: Critical Navigation & Primary Actions (2 hours)
**Impact**: Highest - These are the most-used elements in the entire app

#### 1. SidebarRail.svelte (PRIMARY TARGET)
**File**: `/frontend/src/lib/components/left-sidebar/SidebarRail.svelte`
**Icon-Only Buttons**: 6 critical navigation buttons

| Button | Icon | Current Label | Proposed Tooltip | Priority |
|--------|------|---------------|------------------|----------|
| Toggle Sidebar | Menu | title: "Collapse/Expand sidebar" | "Collapse sidebar" / "Expand sidebar" | Critical |
| Notes | FileText | title: "Notes" | "Notes" | Critical |
| Websites | Globe | title: "Websites" | "Websites" | Critical |
| Files | FolderOpen | title: "Files" | "Files" | Critical |
| Chat | MessageSquare | title: "Chat" | "Chat" | Critical |
| Settings | Avatar | title: "Settings" | "Settings" | Critical |

**Tooltip Content Strategy**:
- Keep simple for navigation (single word is fine)
- Add keyboard shortcuts if applicable (future enhancement)
- Consider state-aware text (e.g., "Collapse" vs "Expand")

**Implementation Notes**:
- Wrap each navigation button in tooltip component
- Maintain existing `aria-label` for accessibility
- Tooltip side: `right` (buttons are on left edge)
- Consider adding keyboard shortcuts like `Cmd+1` for Notes, etc.

---

#### 2. EditorToolbar.svelte
**File**: `/frontend/src/lib/components/editor/EditorToolbar.svelte`
**Icon-Only Buttons**: 8 action buttons

| Button | Icon | Current Label | Proposed Tooltip | Priority |
|--------|------|---------------|------------------|----------|
| Pin Note | Pin/PinOff | aria-label: "Pin/Unpin note" | "Pin to top of list" / "Unpin from top" | Critical |
| Rename | Pencil | aria-label: "Rename note" | "Rename note" | High |
| Move | FolderInput | aria-label: "Move note to folder" | "Move to folder..." | High |
| Copy | Copy | aria-label: "Copy note" | "Copy note content" → "Copied!" (on click) | High |
| Download | Download | aria-label: "Download note" | "Download as markdown" | Medium |
| Archive | Archive/ArchiveRestore | aria-label: "Archive/Unarchive note" | "Archive note" / "Restore from archive" | Critical |
| Delete | Trash2 | aria-label: "Delete note" | "Delete note" | Critical |
| Close | X | aria-label: "Close note" | "Close note" | Medium |

**Tooltip Content Strategy**:
- **Pin**: Explain what pinning does ("Pin to top of list" is clearer than just "Pin")
- **Archive**: Distinguish from delete ("Archive removes from view but keeps data")
- **Copy**: Show state change (normal → "Copied!" for 2 seconds)
- **Move**: Indicate it opens a submenu ("Move to folder...")

**Implementation Notes**:
- Tooltip side: `bottom` (toolbar at top of editor)
- Archive tooltip should clarify it's not permanent deletion
- Copy button should temporarily change tooltip text on click
- Consider adding "(⌘⌫)" for keyboard shortcuts in future

---

#### 3. WebsiteHeader.svelte
**File**: `/frontend/src/lib/components/websites/WebsiteHeader.svelte`
**Icon-Only Buttons**: 7 action buttons (same pattern as EditorToolbar)

| Button | Icon | Current Label | Proposed Tooltip | Priority |
|--------|------|---------------|------------------|----------|
| Pin Website | Pin/PinOff | aria-label: "Pin/Unpin website" | "Pin to top of list" / "Unpin from top" | Critical |
| Rename | Pencil | aria-label: "Rename website" | "Rename website" | High |
| Copy | Copy | aria-label: "Copy website" | "Copy website content" → "Copied!" | High |
| Download | Download | aria-label: "Download website" | "Download as markdown" | Medium |
| Archive | Archive/ArchiveRestore | aria-label: "Archive/Unarchive website" | "Archive website" / "Restore from archive" | Critical |
| Delete | Trash2 | aria-label: "Delete website" | "Delete website" | Critical |
| Close | X | aria-label: "Close website" | "Close website" | Medium |

**Tooltip Content Strategy**:
- Mirror EditorToolbar tooltips for consistency
- Users should see the same patterns across Notes and Websites

**Implementation Notes**:
- Tooltip side: `bottom` (header at top)
- Same copy-state-change pattern as EditorToolbar
- Consider shared tooltip text constants for consistency

---

#### 4. Site Header Buttons
**File**: `/frontend/src/lib/components/site-header.svelte`
**Icon-Only Buttons**: 3 buttons

| Button | Icon | Current Label | Proposed Tooltip | Priority |
|--------|------|---------------|------------------|----------|
| Layout Swap | ArrowLeftRight | title: "Swap chat and workspace positions" | "Swap chat and workspace positions" | High |
| Scratchpad | Pencil | (no label) | "Quick scratchpad" | Medium |
| Theme Toggle | Sun/Moon | aria-label: "Toggle theme" | "Toggle dark/light mode" | Medium |

**Tooltip Content Strategy**:
- **Layout Swap**: Keep descriptive (complex action)
- **Scratchpad**: Brief but clear
- **Theme Toggle**: Be explicit about what's being toggled

**Implementation Notes**:
- Tooltip side: `bottom` (header at top)
- Theme toggle in mode-toggle.svelte component

---

### Phase 2: Secondary Actions & Context (2 hours)
**Impact**: Medium - Important features but less frequently used

#### 5. ChatInput.svelte
**File**: `/frontend/src/lib/components/chat/ChatInput.svelte`
**Icon-Only Buttons**: 2 buttons

| Button | Icon | Current Label | Proposed Tooltip | Priority |
|--------|------|---------------|------------------|----------|
| Attach File | Paperclip | title: "Attach file" | "Attach file (PDF, image, document)" | High |
| Send Message | Send | aria-label: "Send message" | "Send message (⏎)" | Medium |

**Tooltip Content Strategy**:
- **Attach**: Hint at supported file types
- **Send**: Show keyboard shortcut

**Implementation Notes**:
- Tooltip side: `top` (input at bottom of chat)
- Attach tooltip could be enhanced with file type list

---

#### 6. ChatWindow.svelte
**File**: `/frontend/src/lib/components/chat/ChatWindow.svelte`
**Icon-Only Buttons**: 4 buttons

| Button | Icon | Current Label | Proposed Tooltip | Priority |
|--------|------|---------------|------------------|----------|
| New Chat | Plus | aria-label: "Start new chat" | "Start new chat" | High |
| Close Chat | X | aria-label: "Close chat" | "Close chat" | Medium |
| Retry Attachment | RotateCw | aria-label: "Retry" | "Retry failed upload" | Medium |
| Delete Attachment | X | aria-label: "Remove" | "Remove attachment" | Medium |

**Implementation Notes**:
- Tooltip side: Varies by button location
- New Chat: `bottom` (button at top)
- Attachment actions: `top` (buttons in attachment preview)

---

#### 7. FileTreeContextMenu.svelte
**File**: `/frontend/src/lib/components/files/FileTreeContextMenu.svelte`
**Icon-Only Buttons**: 1 button

| Button | Icon | Current Label | Proposed Tooltip | Priority |
|--------|------|---------------|------------------|----------|
| More Options | MoreVertical | (no label) | "More options..." | Medium |

**Implementation Notes**:
- Tooltip side: `left` (button on right edge of file row)
- Only shows on hover - tooltip reinforces affordance

---

#### 8. Memory Toolbar
**File**: `/frontend/src/lib/components/settings/memory/MemoryToolbar.svelte`
**Buttons**: Mostly text-based, but could enhance

| Element | Type | Current Label | Proposed Tooltip | Priority |
|---------|------|---------------|------------------|----------|
| Search Input | Input | placeholder: "Search memories..." | (No tooltip needed) | Low |
| Add Memory | Button | Text: "Add Memory" | "Create new memory" (hover enhancement) | Low |

**Implementation Notes**:
- Lower priority - text labels already present
- Could add explanatory tooltips for what "memories" are

---

### Phase 3: Settings & Complex Features (2 hours)
**Impact**: Lower frequency but high educational value

#### 9. SettingsSkillsSection.svelte
**File**: `/frontend/src/lib/components/left-sidebar/panels/settings/SettingsSkillsSection.svelte`
**Elements**: Skill toggle switches

**Tooltip Strategy**:
- Add tooltips to skill names explaining what each skill does
- Example: "web-save: Save websites with content extraction"
- Help users understand permissions they're granting

**Implementation Notes**:
- Tooltip side: `right` (labels on left)
- Each skill toggle could have explanatory tooltip
- Educational value for understanding the skills system

---

#### 10. Settings Account Section
**File**: `/frontend/src/lib/components/left-sidebar/panels/settings/SettingsAccountSection.svelte`
**Elements**: Profile image upload, email display

**Tooltip Strategy**:
- Profile image upload: "Upload profile picture (JPG, PNG)"
- Lower priority - mostly self-explanatory

---

## Tooltip Content Guidelines

### Writing Principles
1. **Be Concise**: 1-5 words ideal, max 10 words
2. **Action-Oriented**: Use verbs ("Pin to top" not "Pins the note")
3. **Contextual**: Explain non-obvious actions ("Archive removes from view but keeps data")
4. **State-Aware**: Different text for different states (Pin/Unpin)
5. **Include Shortcuts**: When keyboard shortcuts exist (future enhancement)

### Examples of Good Tooltips
- ✅ "Pin to top of list" (explains outcome)
- ✅ "Archive note" (simple, clear)
- ✅ "Download as markdown" (clarifies format)
- ✅ "Swap chat and workspace positions" (complex action needs detail)
- ✅ "Copied!" (feedback for completed action)

### Examples to Avoid
- ❌ "Pin" (too vague - pin to what? why?)
- ❌ "This button archives the note" (too wordy, passive voice)
- ❌ "Click here to download" (redundant - button already implies click)
- ❌ "Delete" when "Archive" is meant (confusing similar actions)

---

## Technical Implementation

### Pattern 1: Basic Tooltip (Single State)
```svelte
<script>
  import { Tooltip, TooltipContent, TooltipTrigger } from '$lib/components/ui/tooltip';
  import { Button } from '$lib/components/ui/button';
  import { Download } from 'lucide-svelte';
</script>

<Tooltip>
  <TooltipTrigger asChild let:builder>
    <Button
      builders={[builder]}
      size="icon"
      variant="ghost"
      onclick={handleDownload}
      aria-label="Download note"
    >
      <Download size={16} />
    </Button>
  </TooltipTrigger>
  <TooltipContent side="bottom">
    <p>Download as markdown</p>
  </TooltipContent>
</Tooltip>
```

### Pattern 2: State-Aware Tooltip (Pin/Unpin)
```svelte
<script>
  import { Tooltip, TooltipContent, TooltipTrigger } from '$lib/components/ui/tooltip';
  import { Button } from '$lib/components/ui/button';
  import { Pin, PinOff } from 'lucide-svelte';

  let { isPinned = $bindable(false) } = $props();
</script>

<Tooltip>
  <TooltipTrigger asChild let:builder>
    <Button
      builders={[builder]}
      size="icon"
      variant="ghost"
      onclick={handleTogglePin}
      aria-label={isPinned ? 'Unpin note' : 'Pin note'}
    >
      {#if isPinned}
        <PinOff size={16} />
      {:else}
        <Pin size={16} />
      {/if}
    </Button>
  </TooltipTrigger>
  <TooltipContent side="bottom">
    <p>{isPinned ? 'Unpin from top' : 'Pin to top of list'}</p>
  </TooltipContent>
</Tooltip>
```

### Pattern 3: Temporary Feedback Tooltip (Copy)
```svelte
<script>
  import { Tooltip, TooltipContent, TooltipTrigger } from '$lib/components/ui/tooltip';
  import { Button } from '$lib/components/ui/button';
  import { Copy, Check } from 'lucide-svelte';

  let copied = $state(false);

  async function handleCopy() {
    // Copy logic here
    copied = true;
    setTimeout(() => copied = false, 2000);
  }
</script>

<Tooltip>
  <TooltipTrigger asChild let:builder>
    <Button
      builders={[builder]}
      size="icon"
      variant="ghost"
      onclick={handleCopy}
      aria-label={copied ? 'Copied' : 'Copy note content'}
    >
      {#if copied}
        <Check size={16} />
      {:else}
        <Copy size={16} />
      {/if}
    </Button>
  </TooltipTrigger>
  <TooltipContent side="bottom">
    <p>{copied ? 'Copied!' : 'Copy note content'}</p>
  </TooltipContent>
</Tooltip>
```

### Pattern 4: Tooltip Provider (App-Wide)
Add `TooltipProvider` to root layout for app-wide tooltip configuration:

```svelte
<!-- /frontend/src/routes/(authenticated)/+layout.svelte -->
<script>
  import { TooltipProvider } from '$lib/components/ui/tooltip';
</script>

<TooltipProvider delayDuration={200}>
  <slot />
</TooltipProvider>
```

**Configuration Options**:
- `delayDuration`: Delay before tooltip appears (default: 200ms)
- `skipDelayDuration`: Duration to skip delay when moving between tooltips (default: 300ms)
- `disableHoverableContent`: Disable hovering over tooltip content (default: false)

---

## Shared Constants Strategy

Create a shared tooltip text constants file to ensure consistency:

```typescript
// /frontend/src/lib/constants/tooltips.ts

export const TOOLTIP_TEXT = {
  // Navigation
  COLLAPSE_SIDEBAR: 'Collapse sidebar',
  EXPAND_SIDEBAR: 'Expand sidebar',
  NOTES: 'Notes',
  WEBSITES: 'Websites',
  FILES: 'Files',
  CHAT: 'Chat',
  SETTINGS: 'Settings',

  // Actions
  PIN: 'Pin to top of list',
  UNPIN: 'Unpin from top',
  RENAME: 'Rename',
  ARCHIVE: 'Archive (keeps data, removes from view)',
  RESTORE: 'Restore from archive',
  DELETE: 'Delete permanently',
  CLOSE: 'Close',
  DOWNLOAD: 'Download as markdown',
  COPY: 'Copy content',
  COPIED: 'Copied!',
  MOVE: 'Move to folder...',

  // Chat
  NEW_CHAT: 'Start new chat',
  SEND_MESSAGE: 'Send message (⏎)',
  ATTACH_FILE: 'Attach file (PDF, image, document)',

  // Layout
  SWAP_LAYOUT: 'Swap chat and workspace positions',
  SCRATCHPAD: 'Quick scratchpad',
  THEME_TOGGLE: 'Toggle dark/light mode',
} as const;
```

**Usage**:
```svelte
<script>
  import { TOOLTIP_TEXT } from '$lib/constants/tooltips';
</script>

<TooltipContent>
  <p>{TOOLTIP_TEXT.PIN}</p>
</TooltipContent>
```

**Benefits**:
- Single source of truth for tooltip text
- Easy to update all tooltips at once
- Type-safe with TypeScript
- Consistent wording across similar actions

---

## Accessibility Considerations

### Best Practices
1. **Always Keep aria-label**: Tooltips are visual enhancement, not replacement for accessibility
```svelte
<Button
  aria-label="Download note"  <!-- KEEP THIS -->
  builders={[builder]}
>
  <Download size={16} />
</Button>
```

2. **Keyboard Navigation**: bits-ui tooltips support keyboard focus automatically
- Tooltips appear on focus (not just hover)
- ESC key dismisses tooltip
- Tab moves to next element

3. **Screen Reader Support**:
- `aria-label` provides text for screen readers
- Tooltip is purely visual enhancement
- Don't rely on tooltip for critical information

4. **Focus Management**:
- Tooltips don't trap focus
- `asChild` prop ensures proper focus delegation
- Button remains focusable and clickable

---

## Testing Strategy

### Manual Testing Checklist
- [ ] **Hover**: Tooltip appears on mouse hover
- [ ] **Focus**: Tooltip appears on keyboard focus (Tab)
- [ ] **Timing**: Tooltip appears after 200ms delay
- [ ] **Positioning**: Tooltip doesn't overflow viewport edges
- [ ] **Animation**: Smooth fade-in and zoom animation
- [ ] **Arrow**: Arrow points to trigger element
- [ ] **Dismiss**: Tooltip dismisses on mouse leave or ESC
- [ ] **Multiple Tooltips**: Moving between tooltips skips delay
- [ ] **Mobile**: Tooltips work on touch devices (tap to show)
- [ ] **State Changes**: State-aware tooltips update text correctly (Pin/Unpin)
- [ ] **Temporary Feedback**: Copy tooltip changes to "Copied!" and resets

### Automated Testing (Future)
```typescript
// Example test with @testing-library/svelte
import { render, screen } from '@testing-library/svelte';
import userEvent from '@testing-library/user-event';
import EditorToolbar from '$lib/components/editor/EditorToolbar.svelte';

test('shows pin tooltip on hover', async () => {
  render(EditorToolbar, { props: { isPinned: false } });

  const pinButton = screen.getByRole('button', { name: /pin note/i });
  await userEvent.hover(pinButton);

  expect(await screen.findByText('Pin to top of list')).toBeInTheDocument();
});

test('shows unpin tooltip when pinned', async () => {
  render(EditorToolbar, { props: { isPinned: true } });

  const unpinButton = screen.getByRole('button', { name: /unpin note/i });
  await userEvent.hover(unpinButton);

  expect(await screen.findByText('Unpin from top')).toBeInTheDocument();
});
```

---

## Implementation Phases

### Phase 1: Critical Navigation & Primary Actions (2 hours)
**Goal**: Add tooltips to most-used elements with highest impact

**Files to Modify**:
1. `/frontend/src/routes/(authenticated)/+layout.svelte` - Add TooltipProvider
2. `/frontend/src/lib/components/left-sidebar/SidebarRail.svelte` - 6 navigation buttons
3. `/frontend/src/lib/components/editor/EditorToolbar.svelte` - 8 action buttons
4. `/frontend/src/lib/components/websites/WebsiteHeader.svelte` - 7 action buttons
5. `/frontend/src/lib/components/site-header.svelte` - 3 header buttons

**Tasks**:
- [ ] Create `/frontend/src/lib/constants/tooltips.ts` with shared text constants (15 min)
- [ ] Add `TooltipProvider` to root layout (10 min)
- [ ] SidebarRail: Wrap 6 navigation buttons with tooltips (30 min)
- [ ] EditorToolbar: Wrap 8 action buttons with state-aware tooltips (45 min)
- [ ] WebsiteHeader: Wrap 7 action buttons with state-aware tooltips (30 min)
- [ ] Site Header: Wrap 3 header buttons with tooltips (20 min)
- [ ] Manual testing of all Phase 1 tooltips (30 min)

**Success Criteria**:
- All navigation buttons show tooltips on hover/focus
- All toolbar actions have clear, descriptive tooltips
- State-aware tooltips (Pin/Archive) update correctly
- Copy tooltips show temporary "Copied!" feedback
- No accessibility regressions (aria-label preserved)

---

### Phase 2: Secondary Actions & Context (2 hours)
**Goal**: Add tooltips to less-frequent but important features

**Files to Modify**:
1. `/frontend/src/lib/components/chat/ChatInput.svelte` - 2 buttons
2. `/frontend/src/lib/components/chat/ChatWindow.svelte` - 4 buttons
3. `/frontend/src/lib/components/files/FileTreeContextMenu.svelte` - 1 button
4. `/frontend/src/lib/components/mode-toggle.svelte` - Theme toggle

**Tasks**:
- [ ] ChatInput: Add tooltips to attach/send buttons (20 min)
- [ ] ChatWindow: Add tooltips to new chat and attachment actions (30 min)
- [ ] FileTreeContextMenu: Add tooltip to more options button (15 min)
- [ ] Theme Toggle: Add tooltip with explanation (15 min)
- [ ] Update tooltip constants with new text (10 min)
- [ ] Manual testing of all Phase 2 tooltips (30 min)

**Success Criteria**:
- Chat interface buttons have helpful tooltips
- File tree context menu hints are clear
- Theme toggle explains what it does
- All tooltips positioned correctly (no viewport overflow)

---

### Phase 3: Settings & Educational Tooltips (2 hours)
**Goal**: Add explanatory tooltips for complex features

**Files to Modify**:
1. `/frontend/src/lib/components/left-sidebar/panels/settings/SettingsSkillsSection.svelte`
2. `/frontend/src/lib/components/settings/memory/MemoryToolbar.svelte`
3. `/frontend/src/lib/components/scratchpad/ScratchpadPopover.svelte`

**Tasks**:
- [ ] Skills Section: Add explanatory tooltips to each skill toggle (45 min)
- [ ] Memory Toolbar: Add tooltips explaining memory system (30 min)
- [ ] Scratchpad Popover: Add tooltips to toolbar buttons (20 min)
- [ ] Update tooltip constants with educational text (15 min)
- [ ] Manual testing of all Phase 3 tooltips (30 min)

**Success Criteria**:
- Users understand what each skill does before enabling
- Memory management tooltips clarify the feature
- Scratchpad toolbar actions are clear
- Educational tooltips help users learn the system

---

## Total Implementation Time

| Phase | Focus | Time |
|-------|-------|------|
| Phase 1 | Critical Navigation & Primary Actions | 2 hours |
| Phase 2 | Secondary Actions & Context | 2 hours |
| Phase 3 | Settings & Educational Tooltips | 2 hours |
| **Total** | **All Tooltips** | **6 hours** |

---

## Success Metrics

### User Experience Improvements
- **Discoverability**: New users understand icon-only buttons without experimentation
- **Efficiency**: Users can quickly identify actions without reading docs
- **Confidence**: Clear tooltips reduce fear of making mistakes
- **Professionalism**: Consistent tooltip design elevates overall UI quality

### Technical Quality
- **Accessibility**: All tooltips support keyboard navigation and screen readers
- **Performance**: Tooltips appear quickly (200ms delay) without janking
- **Consistency**: All tooltips follow the same design pattern
- **Maintainability**: Shared constants make updates easy

---

## Future Enhancements

### Keyboard Shortcuts in Tooltips
```svelte
<TooltipContent>
  <p>Send message <kbd>⏎</kbd></p>
</TooltipContent>
```

### Rich Tooltips with Icons
```svelte
<TooltipContent>
  <div class="flex items-center gap-2">
    <Info size={14} />
    <p>Archive removes from view but keeps data</p>
  </div>
</TooltipContent>
```

### Contextual Help Links
```svelte
<TooltipContent>
  <p>Skills control AI capabilities</p>
  <a href="/docs/skills" class="text-xs underline">Learn more</a>
</TooltipContent>
```

### Progressive Disclosure
- Show basic tooltips by default
- Add "Show detailed tooltips" toggle in settings
- Advanced users can disable tooltips they've learned

### Tooltip Analytics (Optional)
Track which tooltips users hover most frequently to identify:
- Most confusing features (high tooltip hover rate)
- Features that might need UI redesign
- Opportunities for onboarding improvements

---

## Migration Strategy

### Removing Old `title` Attributes
As tooltips are implemented, remove corresponding `title` attributes to avoid double tooltips:

**Before**:
```svelte
<Button
  title="Download note"
  aria-label="Download note"
>
  <Download size={16} />
</Button>
```

**After**:
```svelte
<Tooltip>
  <TooltipTrigger asChild let:builder>
    <Button
      builders={[builder]}
      aria-label="Download note"
    >
      <Download size={16} />
    </Button>
  </TooltipTrigger>
  <TooltipContent>
    <p>Download as markdown</p>
  </TooltipContent>
</Tooltip>
```

**Keep**:
- `aria-label` (accessibility requirement)

**Remove**:
- `title` attribute (replaced by tooltip component)

---

## Checklist Summary

### Infrastructure Setup
- [x] Create `/frontend/src/lib/constants/tooltips.ts`
- [x] Add `TooltipProvider` to root layout

### Phase 1: Critical (2 hours)
- [x] SidebarRail (6 tooltips)
- [x] EditorToolbar (8 tooltips)
- [x] WebsiteHeader (7 tooltips)
- [x] Site Header (3 tooltips)

### Phase 2: Secondary (2 hours)
- [x] ChatInput (2 tooltips)
- [x] ChatWindow (4 tooltips)
- [x] FileTreeContextMenu (1 tooltip)
- [x] Theme Toggle (1 tooltip)

### Phase 3: Educational (2 hours)
- [x] Settings Skills (8+ tooltips)
- [x] Memory Toolbar (3 tooltips)
- [x] Scratchpad Popover (4 tooltips)

### Testing & Polish
- [ ] Manual testing across all phases
- [ ] Keyboard navigation verification
- [ ] Mobile/touch device testing
- [ ] Accessibility audit
- [ ] Remove old `title` attributes

---

## Conclusion

This plan leverages existing tooltip infrastructure (shadcn-svelte) to add professional, accessible tooltips across 35+ icon-only buttons in the sideBar UI. The phased approach prioritizes high-impact navigation and primary actions first, followed by secondary features and educational tooltips.

**Key Benefits**:
- ✅ Zero new dependencies (bits-ui already installed)
- ✅ Consistent design system (shadcn components)
- ✅ Improved discoverability for new users
- ✅ Better accessibility with keyboard support
- ✅ Professional polish with smooth animations
- ✅ Maintainable with shared constants

**Total Implementation Time**: ~6 hours across 3 phases

Ready to start with Phase 1! 🚀
