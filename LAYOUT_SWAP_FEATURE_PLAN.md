# Layout Swap Feature - Implementation Plan

## Overview

Add a layout swap feature that allows users to toggle between two modes:
- **Default Mode**: Notes/websites in main area (flexible width), chat in right sidebar (resizable)
- **Chat-Focused Mode**: Chat in main area (flexible width), notes/websites in right sidebar (resizable)

This provides flexibility for users who want to prioritize either workspace or chat as their primary interface.

## Current Architecture

```
┌─────────────────────────────────────────────────────────┐
│  SiteHeader (64px height)                               │
│  [Logo] [Brand] ... [Weather] [Date/Time] [Scratchpad] [Mode] │
├──────────┬──────────────────────────┬──────────────────┤
│ Sidebar  │   Main Workspace         │  ChatSidebar     │
│ (280px)  │   (flex: 1)              │  (480px fixed)   │
│          │                          │                  │
│ Notes/   │ MarkdownEditor           │  ChatWindow      │
│ Websites │ or                       │  - MessageList   │
│ Tree     │ WebsitesViewer           │  - ChatInput     │
│          │                          │                  │
└──────────┴──────────────────────────┴──────────────────┘
```

### Key Files
- **Layout**: `/routes/+layout.svelte` - Root app layout with Sidebar + main-content
- **Page**: `/routes/+page.svelte` - Contains workspace + ChatSidebar
- **Header**: `/lib/components/site-header.svelte` - Top header with branding and controls
- **Chat**: `/lib/components/chat/ChatSidebar.svelte` - Fixed 480px width wrapper
- **Chat**: `/lib/components/chat/ChatWindow.svelte` - Chat interface with max-w-6xl
- **Editor**: `/lib/components/editor/MarkdownEditor.svelte` - Markdown editor
- **Websites**: `/lib/components/websites/WebsitesViewer.svelte` - Website viewer

## Proposed Solution

### Visual Mockup

**Default Mode:**
```
┌────────────────────────────────────────────────┐
│  SiteHeader  [Swap] [Scratchpad] [Mode]       │
├────────┬───────────────────────────┬───────────┤
│ Left   │   Workspace (flex)        │┃  Chat   │
│ Side   │                           │┃ (550px) │
│ bar    │   Notes/Websites          │┃         │
└────────┴───────────────────────────┴───────────┘
         ┃ = Resize Handle
```

**Chat-Focused Mode:**
```
┌────────────────────────────────────────────────┐
│  SiteHeader  [Swap] [Scratchpad] [Mode]       │
├────────┬───────────────────────────┬───────────┤
│ Left   │   Chat (flex)             │┃Workspace│
│ Side   │                           │┃ (650px) │
│ bar    │   Full width chat         │┃Notes/Web│
└────────┴───────────────────────────┴───────────┘
         ┃ = Resize Handle
```

### Technical Approach

**Core Strategy: CSS Flexbox Order + Resizable Panels**

1. **Flexbox order property** to swap positions (no component remounting)
2. **Custom resize handles** for each mode (minimal code, full control)
3. **Layout store** to manage state and persist preferences
4. **Independent widths** for each mode (chat sidebar vs workspace sidebar)

**Why not a library?**
- Custom implementation: ~150 lines total
- Full control over behavior and UX
- No extra dependencies
- Easier to customize and maintain

## Implementation Phases

### Phase 1: Layout State Management

Create a centralized store to manage layout mode and sidebar widths.

**Plan Updates (Pre-Implementation Adjustments)**
- **Swap actual panel content, not only flex order**: In chat-focused mode, render the chat UI inside the main area and render the workspace (notes/websites) in the sidebar. This avoids keeping ChatSidebar permanently in the sidebar container and matches the intended UX.
- **Use pointer events for resize**: Prefer `pointerdown/move/up` for resize handles to work across mouse, trackpad, and touch.
- **Guard localStorage parsing**: Wrap stored JSON parsing in `try/catch` to avoid crashes on corrupt entries.
- **Responsive safety**: Optionally disable or hide the swap toggle on small screens (e.g., < 900px) to avoid cramped layouts.
- **Dynamic borders**: Adjust border placement based on which panel sits on the right to keep separators consistent.

#### Files to Create

**`/lib/stores/layout.ts`**

```typescript
import { writable } from 'svelte/store';
import { browser } from '$app/environment';

type LayoutMode = 'default' | 'chat-focused';

interface LayoutState {
  mode: LayoutMode;
  chatSidebarWidth: number;      // Width when chat is in sidebar (default mode)
  workspaceSidebarWidth: number;  // Width when workspace is in sidebar (chat-focused)
}

const DEFAULT_STATE: LayoutState = {
  mode: 'default',
  chatSidebarWidth: 550,      // Wider than current 480px for better UX
  workspaceSidebarWidth: 650  // Wide enough for comfortable editing
};

const stored = browser ? localStorage.getItem('sideBar.layout') : null;
let initial: LayoutState = DEFAULT_STATE;
if (stored) {
  try {
    initial = JSON.parse(stored) as LayoutState;
  } catch {
    initial = DEFAULT_STATE;
  }
}

function createLayoutStore() {
  const { subscribe, update } = writable<LayoutState>(initial);

  return {
    subscribe,
    toggleMode: () => update(state => ({
      ...state,
      mode: state.mode === 'default' ? 'chat-focused' : 'default'
    })),
    setChatSidebarWidth: (width: number) => update(state => ({
      ...state,
      chatSidebarWidth: Math.min(Math.max(width, 320), 900) // Bounds: 320-900px
    })),
    setWorkspaceSidebarWidth: (width: number) => update(state => ({
      ...state,
      workspaceSidebarWidth: Math.min(Math.max(width, 480), 900)
    }))
  };
}

export const layoutStore = createLayoutStore();

// Persist to localStorage
layoutStore.subscribe(value => {
  if (browser) {
    localStorage.setItem('sideBar.layout', JSON.stringify(value));
  }
});
```

**Key features:**
- Separate width tracking for each mode
- Bounds checking (320px - 900px)
- localStorage persistence
- Clean API (`toggleMode()`, `setChatSidebarWidth()`, etc.)

### Phase 2: Resize Handle Component

Create a reusable resize handle that users can drag to adjust panel widths.

#### Files to Create

**`/lib/components/layout/ResizeHandle.svelte`**

```svelte
<script lang="ts">
  import { onDestroy } from 'svelte';

  export let onResize: (width: number) => void;
  export let containerRef: HTMLElement;
  export let side: 'left' | 'right' = 'right'; // Which side is being resized

  let isDragging = false;
  let startX = 0;
  let startWidth = 0;

  function handlePointerDown(e: PointerEvent) {
    isDragging = true;
    startX = e.clientX;

    const rect = containerRef.getBoundingClientRect();
    startWidth = rect.width;

    document.body.style.cursor = 'col-resize';
    document.body.style.userSelect = 'none';

    window.addEventListener('pointermove', handlePointerMove);
    window.addEventListener('pointerup', handlePointerUp);
  }

  function handlePointerMove(e: PointerEvent) {
    if (!isDragging) return;

    const delta = side === 'right'
      ? startX - e.clientX  // Right sidebar: drag left to increase
      : e.clientX - startX; // Left sidebar: drag right to increase

    const newWidth = startWidth + delta;
    onResize(newWidth);
  }

  function handlePointerUp() {
    isDragging = false;
    document.body.style.cursor = '';
    document.body.style.userSelect = '';

    window.removeEventListener('pointermove', handlePointerMove);
    window.removeEventListener('pointerup', handlePointerUp);
  }

  onDestroy(() => {
    window.removeEventListener('pointermove', handlePointerMove);
    window.removeEventListener('pointerup', handlePointerUp);
  });
</script>

<div
  class="resize-handle"
  class:dragging={isDragging}
  on:pointerdown={handlePointerDown}
  role="separator"
  aria-orientation="vertical"
  aria-label="Resize sidebar"
>
  <div class="handle-bar"></div>
</div>

<style>
  .resize-handle {
    position: relative;
    width: 8px;
    cursor: col-resize;
    flex-shrink: 0;
    display: flex;
    align-items: center;
    justify-content: center;
    background: transparent;
    transition: background-color 0.15s ease;
  }

  .resize-handle:hover {
    background-color: var(--color-accent);
  }

  .resize-handle.dragging {
    background-color: var(--color-primary);
  }

  .handle-bar {
    width: 2px;
    height: 40px;
    background-color: var(--color-border);
    border-radius: 1px;
    transition: background-color 0.15s ease;
  }

  .resize-handle:hover .handle-bar,
  .resize-handle.dragging .handle-bar {
    background-color: var(--color-primary);
  }
</style>
```

**Key features:**
- Drag to resize functionality
- Visual feedback (hover, dragging states)
- Proper cleanup on destroy
- Configurable side (`left` or `right`)
- Accessibility attributes (role, aria-label)

### Phase 3: Update Page Layout

Modify the main page layout to support swapping and resizing.

#### Files to Modify

**`/routes/+page.svelte`**

```svelte
<script lang="ts">
  import MarkdownEditor from '$lib/components/editor/MarkdownEditor.svelte';
  import ChatSidebar from '$lib/components/chat/ChatSidebar.svelte';
  import WebsitesViewer from '$lib/components/websites/WebsitesViewer.svelte';
  import ResizeHandle from '$lib/components/layout/ResizeHandle.svelte';
  import { websitesStore } from '$lib/stores/websites';
  import { layoutStore } from '$lib/stores/layout';

  let chatSidebarRef: HTMLElement;
  let workspaceSidebarRef: HTMLElement;

  $: currentChatWidth = $layoutStore.chatSidebarWidth;
  $: currentWorkspaceWidth = $layoutStore.workspaceSidebarWidth;
  $: isChatFocused = $layoutStore.mode === 'chat-focused';
</script>

<div class="page-container" class:chat-focused={isChatFocused}>
  <div
    class="main-area"
    bind:this={isChatFocused ? chatSidebarRef : workspaceSidebarRef}
  >
    {#if $websitesStore.active}
      <WebsitesViewer />
    {:else}
      <MarkdownEditor />
    {/if}
  </div>

  {#if !isChatFocused}
    <ResizeHandle
      containerRef={chatSidebarRef}
      side="right"
      onResize={(width) => layoutStore.setChatSidebarWidth(width)}
    />
  {/if}

  <div
    class="sidebar-area"
    bind:this={isChatFocused ? workspaceSidebarRef : chatSidebarRef}
    style:width={isChatFocused
      ? `${currentWorkspaceWidth}px`
      : `${currentChatWidth}px`}
  >
    <ChatSidebar />
  </div>

  {#if isChatFocused}
    <ResizeHandle
      containerRef={workspaceSidebarRef}
      side="right"
      onResize={(width) => layoutStore.setWorkspaceSidebarWidth(width)}
    />
  {/if}
</div>

<style>
  .page-container {
    display: flex;
    height: 100%;
    width: 100%;
    overflow: hidden;
    min-height: 0;
  }

  .main-area {
    flex: 1;
    overflow: hidden;
    min-height: 0;
    order: 1;
    transition: order 0.3s ease;
  }

  .sidebar-area {
    overflow: hidden;
    min-height: 0;
    order: 2;
    transition: width 0.15s ease, order 0.3s ease;
    flex-shrink: 0;
  }

  .page-container.chat-focused .main-area {
    order: 2;
  }

  .page-container.chat-focused .sidebar-area {
    order: 1;
  }
</style>
```

**Key changes:**
- Flexbox order swapping via `.chat-focused` class
- Conditional resize handles (only show in correct mode)
- Bind refs to appropriate elements based on mode
- Dynamic width styling based on current mode

**`/lib/components/chat/ChatSidebar.svelte`**

Remove fixed width, let parent control sizing:

```svelte
<script lang="ts">
  import ChatWindow from './ChatWindow.svelte';
</script>

<div class="chat-sidebar">
  <ChatWindow />
</div>

<style>
  .chat-sidebar {
    /* REMOVE: width: 480px; */
    width: 100%; /* Let parent control width */
    height: 100%;
    border-left: 1px solid var(--color-border);
    background-color: var(--color-background);
    overflow: hidden;
    min-height: 0;
  }
</style>
```

### Phase 4: Add Swap Button to Header

Add a button to toggle between layout modes.

#### Files to Modify

**`/lib/components/site-header.svelte`**

Add import and handler:
```svelte
<script lang="ts">
  import { useSiteHeaderData } from "$lib/hooks/useSiteHeaderData";
  import ModeToggle from "$lib/components/mode-toggle.svelte";
  import ScratchpadPopover from "$lib/components/scratchpad-popover.svelte";
  import { resolveWeatherIcon } from "$lib/utils/weatherIcons";
  import { ArrowLeftRight } from 'lucide-svelte';  // ADD
  import { layoutStore } from '$lib/stores/layout';   // ADD
  import { Button } from '$lib/components/ui/button'; // ADD

  const siteHeaderData = useSiteHeaderData();
  let currentDate = "";
  let currentTime = "";
  let liveLocation = "";
  let weatherTemp = "";
  let weatherCode: number | null = null;
  let weatherIsDay: number | null = null;

  $: ({ currentDate, currentTime, liveLocation, weatherTemp, weatherCode, weatherIsDay } = $siteHeaderData);

  // ADD: Toggle handler
  function handleLayoutSwap() {
    layoutStore.toggleMode();
  }
</script>
```

Update template (add button before ScratchpadPopover):
```svelte
<div class="actions">
  <div class="datetime-group">
    <!-- ... existing datetime/weather code ... -->
  </div>

  <!-- ADD: Layout swap button -->
  <Button
    size="icon"
    variant="ghost"
    onclick={handleLayoutSwap}
    aria-label="Swap layout"
    title="Swap chat and workspace positions"
    class="swap-button"
  >
    <ArrowLeftRight size={20} />
  </Button>

  <ScratchpadPopover />
  <ModeToggle />
</div>
```

Optional: Add subtle styling for the swap button:
```css
:global(.swap-button) {
  color: var(--color-muted-foreground);
  transition: color 0.2s ease;
}

:global(.swap-button:hover) {
  color: var(--color-foreground);
}
```

### Phase 5: Responsive ChatWindow

Update ChatWindow to work in both main and sidebar contexts.

#### Files to Modify

**`/lib/components/chat/ChatWindow.svelte`**

The main change is removing or adjusting the `max-w-6xl` constraint:

```svelte
<!-- Line 278: Update container classes -->
<div class="flex flex-col h-full min-h-0 w-full mx-auto bg-background">
  <!-- Remove max-w-6xl, add w-full -->
  <!-- Rest remains the same -->
</div>
```

Or add conditional max-width:
```svelte
<script>
  import { layoutStore } from '$lib/stores/layout';
  $: isChatInSidebar = $layoutStore.mode === 'default';
</script>

<div
  class="flex flex-col h-full min-h-0 mx-auto bg-background"
  class:max-w-6xl={!isChatInSidebar}
  class:w-full={isChatInSidebar}
>
  <!-- ... -->
</div>
```

## Technical Details

### State Management

**Layout Store** (`layoutStore`)
- `mode`: 'default' | 'chat-focused'
- `chatSidebarWidth`: number (default: 550px)
- `workspaceSidebarWidth`: number (default: 650px)
- Methods: `toggleMode()`, `setChatSidebarWidth()`, `setWorkspaceSidebarWidth()`

**Persistence**: All state saved to `localStorage` as `sideBar.layout`

### Width Constraints

| Mode | Component | Min Width | Max Width | Default |
|------|-----------|-----------|-----------|---------|
| Default | Chat Sidebar | 320px | 900px | 550px |
| Chat-Focused | Workspace Sidebar | 480px | 900px | 650px |

**Rationale:**
- **Chat sidebar (550px default)**: Comfortable for chat messages, wider than original 480px
- **Workspace sidebar (650px default)**: Wide enough for markdown editing without cramping
- **Min 320px**: Prevents sidebar from becoming unusable
- **Max 900px**: Prevents sidebar from dominating the screen

### CSS Transitions

```css
.main-area {
  transition: order 0.3s ease;
}

.sidebar-area {
  transition: width 0.15s ease, order 0.3s ease;
}
```

- **Order transition (300ms)**: Smooth visual swap between positions
- **Width transition (150ms)**: Subtle animation when resizing
- **Easing**: `ease` for natural feel

### Resize Handle Behavior

**Events:**
1. `mousedown` - Start drag, record start position and width
2. `mousemove` - Calculate delta, apply new width through store
3. `mouseup` - End drag, cleanup event listeners

**Visual States:**
- Default: Subtle 2px bar
- Hover: Background highlight, primary color bar
- Dragging: Primary background, primary color bar

**Cursor:**
- Shows `col-resize` on hover and during drag
- Applied to `document.body` during drag for better UX

## UX Considerations

### State Preservation

**✅ Components stay mounted** - Using flexbox order means components never unmount
- Chat history preserved when swapping
- Editor content/cursor position preserved
- No flickering or re-initialization

### Visual Feedback

**Swap button:**
- Icon: `ArrowLeftRight` (bidirectional arrows)
- Tooltip: "Swap chat and workspace positions"
- Subtle hover state

**Resize handles:**
- Always visible as subtle divider
- Highlights on hover to indicate interactivity
- Strong visual feedback while dragging

### Accessibility

**Resize handles:**
- `role="separator"`
- `aria-orientation="vertical"`
- `aria-label="Resize sidebar"`

**Swap button:**
- `aria-label="Swap layout"`
- Keyboard accessible (can be focused and activated with Enter/Space)

### Edge Cases

**Empty states:**
- No note open + swap to chat-focused: Empty workspace sidebar (shows empty state)
- Chat closed + in chat-focused mode: Shows new chat interface in main area

**Small screens:**
- Consider adding media query to disable swap on mobile
- Or auto-collapse sidebar and show overlay instead

**Initial load:**
- Loads from localStorage if available
- Falls back to default mode with default widths

## Testing Checklist

### Functionality
- [ ] Swap button toggles between modes correctly
- [ ] Layout swap is smooth and animated
- [ ] Resize handles appear in correct mode only
- [ ] Dragging resize handle adjusts width correctly
- [ ] Width changes persist after page reload
- [ ] Mode preference persists after page reload
- [ ] Width respects min/max bounds (320-900px)
- [ ] Components stay mounted (no state loss)

### Visual
- [ ] No layout shift or flickering during swap
- [ ] Resize handle highlights on hover
- [ ] Cursor changes to col-resize on hover
- [ ] Transitions are smooth (not too fast/slow)
- [ ] Works in both light and dark modes

### Edge Cases
- [ ] Works when no note is open
- [ ] Works when no chat is active
- [ ] Works with websites viewer open
- [ ] Handle cleanup on component destroy
- [ ] No memory leaks from event listeners

### Accessibility
- [ ] Swap button keyboard accessible
- [ ] Resize handle has proper ARIA attributes
- [ ] Tooltips/labels are descriptive
- [ ] Focus indicators visible

### Responsive
- [ ] Works on different screen sizes
- [ ] Consider behavior on tablets/mobile
- [ ] Max width constraints prevent overflow

## Future Enhancements

### Phase 2 Features (Post-Launch)
- **Double-click handle** to reset to default width
- **Keyboard resize** - Arrow keys when handle focused
- **Snap points** - Snap to common widths (500px, 600px, 700px)
- **Collapse/expand** - Double-click to fully collapse sidebar
- **Touch support** - Add touch events for tablets
- **Presets** - Save multiple layout configurations
- **Hotkey** - Cmd/Ctrl+Shift+L to swap layout

### Advanced Features
- **Three-column mode** - Show both chat and workspace simultaneously
- **Detached windows** - Pop out chat or workspace to separate window
- **Layout per route** - Different layouts for different sections
- **Animation preferences** - Let users disable transitions

## Files Summary

### New Files (2)
1. `/lib/stores/layout.ts` - Layout state management
2. `/lib/components/layout/ResizeHandle.svelte` - Resize handle component

### Modified Files (3)
1. `/routes/+page.svelte` - Layout swapping logic
2. `/lib/components/site-header.svelte` - Add swap button
3. `/lib/components/chat/ChatSidebar.svelte` - Remove fixed width
4. `/lib/components/chat/ChatWindow.svelte` - Responsive width handling

### Total Lines of Code
- **Layout store**: ~60 lines
- **ResizeHandle component**: ~90 lines
- **Page updates**: ~50 lines modifications
- **Header updates**: ~15 lines additions
- **ChatSidebar updates**: ~5 lines modifications
- **ChatWindow updates**: ~5 lines modifications

**Total: ~225 lines** (well worth the UX improvement!)

## Implementation Timeline

**Estimated effort: 3-4 hours**

1. **Phase 1 - State Management** (45 min)
   - Create layout store
   - Test persistence

2. **Phase 2 - Resize Handle** (90 min)
   - Build component
   - Test drag behavior
   - Add visual states

3. **Phase 3 - Layout Integration** (45 min)
   - Update +page.svelte
   - Wire up store
   - Test swapping

4. **Phase 4 - Header Button** (15 min)
   - Add button
   - Wire up handler

5. **Phase 5 - Polish** (30 min)
   - Adjust transitions
   - Test edge cases
   - Fix any issues

## Success Criteria

- ✅ Users can swap layout with single button click
- ✅ Both modes support resizable sidebars
- ✅ Preferences persist across sessions
- ✅ Smooth, polished transitions
- ✅ No component state loss during swap
- ✅ Works in light and dark modes
- ✅ Proper bounds checking prevents unusable widths
- ✅ Accessible keyboard navigation
- ✅ Clean, maintainable code (<250 lines total)
