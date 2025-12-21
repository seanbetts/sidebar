<script lang="ts">
	import type { ToolCall } from '$lib/types/chat';

	export let toolCall: ToolCall;

	$: statusColor =
		toolCall.status === 'success'
			? 'bg-green-100 border-green-300'
			: toolCall.status === 'error'
				? 'bg-red-100 border-red-300'
				: 'bg-blue-100 border-blue-300';

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

<div class="my-2 p-3 border rounded-lg {statusColor}">
	<div class="flex items-center gap-2 mb-2">
		<span class="text-sm font-medium">🔧 {toolCall.name}</span>
		<span class="text-xs px-2 py-1 rounded bg-white">{statusIcon} {toolCall.status}</span>
	</div>

	{#if Object.keys(toolCall.parameters).length > 0}
		<details class="mb-2">
			<summary class="text-xs text-gray-600 cursor-pointer hover:text-gray-800">
				Parameters
			</summary>
			<pre class="text-xs bg-white p-2 rounded mt-1 overflow-x-auto">{formatJSON(
					toolCall.parameters
				)}</pre>
		</details>
	{/if}

	{#if toolCall.result}
		<details open={toolCall.status === 'error'}>
			<summary class="text-xs text-gray-600 cursor-pointer hover:text-gray-800">
				{toolCall.status === 'success' ? 'Result' : 'Error'}
			</summary>
			<pre class="text-xs bg-white p-2 rounded mt-1 overflow-x-auto">{formatJSON(
					toolCall.result
				)}</pre>
		</details>
	{/if}
</div>
