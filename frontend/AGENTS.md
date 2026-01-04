# Frontend Agent Rules

## Component Size

Hard limit: 600 LOC

**When approaching limit:**
- Extract sub-components
- Move logic to custom hooks/utils
- Split into container + presentational components

## State Management

### Stores
Located in `src/lib/stores/`

**Pattern:**
```typescript
export const myStore = createMyStore();

function createMyStore() {
  const { subscribe, update, set } = writable<T>(initial);

  return {
    subscribe,
    // Methods that update state
  };
}
```

### Store Subscriptions in Components
Use `$` prefix for auto-subscription:
```svelte
<script>
  import { myStore } from '$lib/stores/myStore';
  $: data = $myStore.data;  // Auto-subscribes
</script>
```

## API Calls

Always through stores or centralized services, never directly in components.

**Pattern:**
```typescript
// In store
async loadData() {
  const response = await fetch('/api/endpoint');
  if (!response.ok) throw new APIError(...);
  const data = await response.json();
  update(state => ({ ...state, data }));
}
```

## SSE (Server-Sent Events)

Handle SSE events in `ChatWindow.svelte` callbacks:
```typescript
await sseClient.connect(message, {
  onNoteCreated: async (data) => {
    await filesStore.load('notes');
  },
  onNoteUpdated: async (data) => {
    await filesStore.load('notes');
  }
});
```

## Testing

- Tests in `src/tests/`
- Use `@testing-library/svelte`
- Mock fetch with vitest
- Coverage target: 70%+

## Styling

- Use Tailwind classes
- Component-specific styles in `<style>` blocks
- Don't create global CSS (use Tailwind utilities)

## Common Mistakes

**DON'T:**
- Make API calls directly in components
- Forget to unsubscribe from stores (use `$` prefix)
- Leave console.log statements
- Create giant components (> 600 LOC)

**DO:**
- Extract logic to custom hooks/utils
- Use TypeScript types for all data
- Handle loading and error states
- Write JSDoc for exported functions
