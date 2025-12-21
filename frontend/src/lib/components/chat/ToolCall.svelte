<script lang="ts">
	import type { ToolCall } from '$lib/types/chat';
	import { Badge } from '$lib/components/ui/badge';

	export let toolCall: ToolCall;

	$: statusVariant =
		toolCall.status === 'success'
			? 'default'
			: toolCall.status === 'error'
				? 'destructive'
				: 'secondary';

	$: statusIcon =
		toolCall.status === 'success'
			? '✓'
			: toolCall.status === 'error'
				? '✗'
				: '⋯';

	function formatJSON(obj: any): string {
		try {
			return JSON.stringify(obj, null, 2);
		} catch {
			return String(obj);
		}
	}
</script>

<div class="my-2 p-3 border rounded-lg bg-muted/50">
	<div class="flex items-center gap-2 mb-2">
		<span class="text-sm font-medium text-foreground">🔧 {toolCall.name}</span>
		<Badge variant={statusVariant}>{statusIcon} {toolCall.status}</Badge>
	</div>

	{#if Object.keys(toolCall.parameters).length > 0}
		<details class="mb-2">
			<summary class="text-xs text-muted-foreground cursor-pointer hover:text-foreground">
				Parameters
			</summary>
			<pre class="text-xs bg-card p-2 rounded mt-1 overflow-x-auto border">{formatJSON(
					toolCall.parameters
				)}</pre>
		</details>
	{/if}

	{#if toolCall.result}
		<details open={toolCall.status === 'error'}>
			<summary class="text-xs text-muted-foreground cursor-pointer hover:text-foreground">
				{toolCall.status === 'success' ? 'Result' : 'Error'}
			</summary>
			<pre class="text-xs bg-card p-2 rounded mt-1 overflow-x-auto border">{formatJSON(
					toolCall.result
				)}</pre>
		</details>
	{/if}
</div>
