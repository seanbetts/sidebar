# Frontend Agent Rules

## Component Size

Hard limit: 600 LOC

**When approaching limit:**

- Extract sub-components
- Move logic to composables/utils
- Split into container + presentational components

## State Management

### Stores

Located in `frontend/src/lib/stores/`

**Pattern:**

```typescript
export const myStore = createMyStore();

function createMyStore() {
	const { subscribe, update, set } = writable<T>(initial);

	return {
		subscribe
		// Methods that update state
	};
}
```

### Store Subscriptions in Components

Use the repo's existing Svelte patterns. Store auto-subscriptions are common, and Svelte 5 runes are also used in some route components. Match the file you are editing instead of forcing a different reactive style.

```svelte
<script>
	import { myStore } from '$lib/stores/myStore';
	$: data = $myStore.data; // Auto-subscribes
</script>
```

## API Calls

Prefer stores, composables, or centralized services. Avoid ad hoc `fetch()` calls in leaf components when shared state or reuse is involved.

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

Keep chat SSE logic in the existing chat streaming layer. `ChatWindow.svelte` orchestrates user actions, while the event wiring lives in `frontend/src/lib/composables/useChatSSE.ts`.

```typescript
const chatSse = useChatSSE();
await chatSse.connect({ assistantMessageId, message, conversationId });
```

## Testing

- Tests in `src/tests/`
- Use `@testing-library/svelte`
- Mock fetch with vitest
- Coverage target: 70%+

## Styling

- Use Tailwind classes as the default styling tool
- Component-specific styles in `<style>` blocks are fine
- Follow existing global styling patterns when needed. `frontend/src/app.css` and targeted `:global(...)` rules already exist, so avoid unnecessary new global rules but do not treat all global CSS as forbidden.

## Common Mistakes

**DON'T:**

- Make API calls directly in components
- Forget to unsubscribe from stores (use `$` prefix)
- Leave console.log statements
- Create giant components (> 600 LOC)

**DO:**

- Extract logic to composables/utils
- Use TypeScript types for all data
- Handle loading and error states
- Write JSDoc for exported functions
