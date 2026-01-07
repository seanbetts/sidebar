# Toast Feedback Improvements Plan

## Executive Summary

**Goal**: Add consistent toast feedback for silent failures across CRUD operations and fix asymmetric error handling in transcript operations.

**Current Status**: Toast notifications are well-implemented for long-running async tasks (transcripts, chat streaming, health checks) but silently fail for user-initiated CRUD operations (rename, delete, pin, archive, move). This creates inconsistent UX where users don't know if operations failed.

**Impact**: 20+ operations across 5 files currently fail silently, leaving users uncertain about operation status.

**Implementation Time**: ~2 hours

---

## Goals & Rationale

### UX Principle
Use toasts for two scenarios:
1. **Long-running async tasks** - User might context-switch, needs notification when complete/failed
2. **Silent errors without UI error states** - User has no way to know operation failed

### Current Problems

#### Problem 1: Silent CRUD Failures
When operations fail, users get no feedback:
- **Delete** - Dialog closes, user thinks it worked (but it didn't)
- **Pin/Unpin** - Icon doesn't change, looks like UI lag
- **Archive** - Item doesn't move, looks like UI lag
- **Rename** - Input reverts, user thinks they mis-typed (not that server failed)
- **Move** - Item doesn't move, looks like UI lag

#### Problem 2: Inconsistent Transcript Error Handling
- `SiteHeader.svelte:176` - Transcript polling failure shows toast with **Retry** button ✅
- `WebsitesViewer.svelte:275` - Transcript queueing failure says "Please try again" but has **NO** retry button ❌

### Benefits
- **Clear feedback** - Users know when operations fail vs. when they're successful
- **Reduced confusion** - Server errors are distinguished from user errors
- **Consistent UX** - All CRUD operations follow same error pattern
- **Better debugging** - Users can report specific errors instead of "it didn't work"

---

## Current Toast Usage (Reference)

### Already Using Toasts ✅
| File | Scenario | Toast Type | Has Action |
|------|----------|------------|------------|
| `+layout.svelte:78,83,87` | Health check failures | Error | No |
| `site-header.svelte:125` | Transcript retry fails | Error | No |
| `site-header.svelte:161` | Transcript ready | Success | No |
| `site-header.svelte:176` | Transcript failed/canceled | Error | Yes (Retry) |
| `WebsitesViewer.svelte:275` | Transcript queue fails | Error | No |
| `ChatWindow.svelte:47` | Files still processing | Error | No |
| `ChatWindow.svelte:136` | Chat send fails | Error | No |
| `ChatWindow.svelte:201` | Attachment retry fails | Error | No |
| `useChatSSE.ts:208` | SSE stream error | Error | No |
| `MarkdownEditor.svelte:88` | Note updated externally | Message | No |

### Silent Failures (Gaps to Fix) ❌
| File | Operations | Current Behavior |
|------|-----------|------------------|
| `ConversationItem.svelte` | Rename, Delete | Logs error, no user feedback |
| `useEditorActions.ts` | Rename, Move, Archive, Unarchive, Pin, Delete | Logs error, no user feedback |
| `useFileActions.ts` | Rename, Move, MoveFolder, Archive, Unarchive, Pin, Delete | Logs error, no user feedback |
| `useWebsiteActions.ts` | Rename, Pin, Archive, Delete | Logs error, returns false, no toast |

---

## Implementation Plan

### Phase 1: Fix Asymmetric Transcript Error (15 min)

#### File: `frontend/src/lib/components/websites/WebsitesViewer.svelte`

**Current (line 275-277)**:
```typescript
toast.error('Transcript failed', {
  description: 'Please try again.'
});
```

**Updated**:
```typescript
toast.error('Transcript failed', {
  description: 'Click to retry transcription.',
  action: {
    label: 'Retry',
    onClick: () => {
      const videoId = extractYouTubeVideoId(url);
      if (videoId && website) {
        queueTranscript(url, website.id, videoId);
      }
    }
  }
});
```

**Context Needed**: The `queueTranscript` function and `url` should be available in the error catch block scope.

---

### Phase 2: Add Toast Feedback to Website Actions (20 min)

#### File: `frontend/src/lib/hooks/useWebsiteActions.ts`

**Import Required**:
```typescript
import { toast } from 'svelte-sonner';
```

**Changes Required**:

1. **renameWebsite** (line 30-50):
```typescript
catch (error) {
  toast.error('Failed to rename website');
  logError('Failed to rename website', error, {
    scope: options.scope ?? defaultScope('rename'),
    websiteId
  });
  return false;
}
```

2. **pinWebsite** (line 52-76):
```typescript
catch (error) {
  toast.error('Failed to pin website');
  logError('Failed to update website pin', error, {
    scope: options.scope ?? defaultScope('pin'),
    websiteId,
    pinned
  });
  return false;
}
```

3. **archiveWebsite** (line 78-101):
```typescript
catch (error) {
  toast.error('Failed to archive website');
  logError('Failed to archive website', error, {
    scope: options.scope ?? defaultScope('archive'),
    websiteId,
    archived
  });
  return false;
}
```

4. **deleteWebsite** (line 103-122):
```typescript
catch (error) {
  toast.error('Failed to delete website');
  logError('Failed to delete website', error, {
    scope: options.scope ?? defaultScope('delete'),
    websiteId
  });
  return false;
}
```

---

### Phase 3: Add Toast Feedback to Editor Actions (30 min)

#### File: `frontend/src/lib/hooks/useEditorActions.ts`

**Import Required**:
```typescript
import { toast } from 'svelte-sonner';
```

**Changes Required**:

1. **handleRename** (line 109-116):
```typescript
if (!response.ok) {
  toast.error('Failed to rename note');
  logError('Failed to rename note', new Error('Request failed'), {
    scope: 'editorActions.rename',
    noteId: currentNoteId,
    status: response.status
  });
  return;
}
```

2. **handleMove** (line 132-139):
```typescript
if (!response.ok) {
  toast.error('Failed to move note');
  logError('Failed to move note', new Error('Request failed'), {
    scope: 'editorActions.move',
    noteId: currentNoteId,
    status: response.status
  });
  return;
}
```

3. **handleArchive** (line 152-159):
```typescript
if (!response.ok) {
  toast.error('Failed to archive note');
  logError('Failed to archive note', new Error('Request failed'), {
    scope: 'editorActions.archive',
    noteId: currentNoteId,
    status: response.status
  });
  return;
}
```

4. **handleUnarchive** (line 173-180):
```typescript
if (!response.ok) {
  toast.error('Failed to unarchive note');
  logError('Failed to unarchive note', new Error('Request failed'), {
    scope: 'editorActions.unarchive',
    noteId: currentNoteId,
    status: response.status
  });
  return;
}
```

5. **handlePinToggle** (line 195-202):
```typescript
if (!response.ok) {
  toast.error('Failed to pin note');
  logError('Failed to update pin', new Error('Request failed'), {
    scope: 'editorActions.pin',
    noteId: currentNoteId,
    status: response.status
  });
  return;
}
```

6. **handleDelete** (line 244-251):
```typescript
if (!response.ok) {
  toast.error('Failed to delete note');
  logError('Failed to delete note', new Error('Request failed'), {
    scope: 'editorActions.delete',
    noteId: currentNoteId,
    status: response.status
  });
  return false;
}
```

---

### Phase 4: Add Toast Feedback to File Actions (30 min)

#### File: `frontend/src/lib/hooks/useFileActions.ts`

**Import Required**:
```typescript
import { toast } from 'svelte-sonner';
```

**Changes Required**:

1. **saveRename** (line 134-141):
```typescript
catch (error) {
  toast.error('Failed to rename');
  logError('Failed to rename', error, {
    scope: 'fileActions.rename',
    basePath,
    nodePath: node.path
  });
  ctx.setEditedName(node.name);
}
```

2. **handlePinToggle** (line 168-174):
```typescript
catch (error) {
  toast.error('Failed to pin note');
  logError('Failed to pin note', error, {
    scope: 'fileActions.pin',
    noteId: node.path
  });
}
```

3. **handleArchive** (line 188-194):
```typescript
catch (error) {
  toast.error('Failed to archive note');
  logError('Failed to archive note', error, {
    scope: 'fileActions.archive',
    noteId: node.path
  });
}
```

4. **handleUnarchive** (line 208-214):
```typescript
catch (error) {
  toast.error('Failed to unarchive note');
  logError('Failed to unarchive note', error, {
    scope: 'fileActions.unarchive',
    noteId: node.path
  });
}
```

5. **handleMove** (line 243-250):
```typescript
catch (error) {
  toast.error('Failed to move file');
  logError('Failed to move file', error, {
    scope: 'fileActions.move',
    basePath: ctx.getBasePath(),
    nodePath: node.path,
    destination: folder
  });
}
```

6. **handleMoveFolder** (line 283-290):
```typescript
catch (error) {
  toast.error('Failed to move folder');
  logError('Failed to move folder', error, {
    scope: 'fileActions.moveFolder',
    basePath: ctx.getBasePath(),
    nodePath: node.path,
    destination: newParent
  });
}
```

7. **confirmDelete** (line 356-363):
```typescript
catch (error) {
  toast.error('Failed to delete');
  logError('Failed to delete', error, {
    scope: 'fileActions.delete',
    basePath: ctx.getBasePath(),
    nodePath: node.path
  });
  return false;
}
```

---

### Phase 5: Add Toast Feedback to Conversation Actions (20 min)

#### File: `frontend/src/lib/components/left-sidebar/ConversationItem.svelte`

**Import Required** (line 8):
```typescript
import { toast } from 'svelte-sonner';
```

**Changes Required**:

1. **saveRename** (line 42-49):
```typescript
catch (error) {
  toast.error('Failed to rename conversation');
  logError('Failed to rename conversation', error, {
    scope: 'ConversationItem',
    conversationId: conversation.id
  });
  editedTitle = conversation.title;
}
```

2. **confirmDelete** (line 81-88):
```typescript
catch (error) {
  toast.error('Failed to delete conversation');
  logError('Failed to delete conversation', error, {
    scope: 'ConversationItem',
    conversationId: conversation.id
  });
  return false;
}
```

---

## Testing Checklist

After implementation, test each scenario by simulating failures (e.g., disconnect network):

### Websites
- [ ] Rename website fails → shows toast
- [ ] Pin website fails → shows toast
- [ ] Archive website fails → shows toast
- [ ] Delete website fails → shows toast
- [ ] Queue transcript fails → shows toast with Retry button

### Notes (Editor)
- [ ] Rename note fails → shows toast
- [ ] Move note fails → shows toast
- [ ] Archive note fails → shows toast
- [ ] Unarchive note fails → shows toast
- [ ] Pin note fails → shows toast
- [ ] Delete note fails → shows toast

### Notes/Files (Tree)
- [ ] Rename file/folder fails → shows toast
- [ ] Move file/folder fails → shows toast
- [ ] Archive note fails → shows toast
- [ ] Unarchive note fails → shows toast
- [ ] Pin note fails → shows toast
- [ ] Delete file/folder fails → shows toast

### Conversations
- [ ] Rename conversation fails → shows toast
- [ ] Delete conversation fails → shows toast

---

## Summary of Changes

### Files Modified: 5
1. `frontend/src/lib/components/websites/WebsitesViewer.svelte` - Add retry action to transcript error
2. `frontend/src/lib/hooks/useWebsiteActions.ts` - Add toasts to all operations (4 functions)
3. `frontend/src/lib/hooks/useEditorActions.ts` - Add toasts to all operations (6 functions)
4. `frontend/src/lib/hooks/useFileActions.ts` - Add toasts to all operations (7 functions)
5. `frontend/src/lib/components/left-sidebar/ConversationItem.svelte` - Add toasts to rename/delete (2 functions)

### Toast Messages Added: 19
- 4 website operations
- 6 editor operations
- 7 file tree operations
- 2 conversation operations

### Pattern Applied
All error handlers follow this pattern:
```typescript
catch (error) {
  toast.error('Failed to [operation]');
  logError(...); // existing
  // existing cleanup/return
}
```

---

## Future Enhancements (Out of Scope)

1. **Keyboard shortcuts in toasts** - "Press Ctrl+Z to undo" for delete operations
2. **Undo actions** - Add undo button to delete toasts before 5-second timeout
3. **Success toasts** - Currently only errors get toasts; consider adding success feedback for major operations
4. **Progress toasts** - For long-running operations (file uploads, batch operations)
5. **Toast grouping** - If multiple operations fail, group into single toast

---

## Notes

- All toast imports use: `import { toast } from 'svelte-sonner';`
- Toast library is already configured in `+layout.svelte` with `position="top-right"` and `richColors`
- Error messages kept simple and user-friendly (no technical jargon)
- All toasts maintain existing `logError()` calls for debugging
- No changes to success paths - only error paths get toasts
