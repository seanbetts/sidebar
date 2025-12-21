<script lang="ts">
	export let disabled = false;
	export let onsend: ((message: string) => void) | undefined = undefined;

	let inputValue = '';

	function handleSubmit() {
		const message = inputValue.trim();
		if (message && !disabled) {
			onsend?.(message);
			inputValue = '';
		}
	}

	function handleKeydown(event: KeyboardEvent) {
		if (event.key === 'Enter' && !event.shiftKey) {
			event.preventDefault();
			handleSubmit();
		}
	}
</script>

<div class="flex gap-2 p-4 border-t border-gray-200 bg-white">
	<textarea
		bind:value={inputValue}
		onkeydown={handleKeydown}
		placeholder="Type your message... (Enter to send, Shift+Enter for new line)"
		{disabled}
		rows="3"
		class="flex-1 p-3 border border-gray-300 rounded-lg resize-none focus:outline-none focus:ring-2 focus:ring-blue-500 disabled:bg-gray-100 disabled:cursor-not-allowed"
	/>
	<button
		onclick={handleSubmit}
		disabled={disabled || !inputValue.trim()}
		class="px-6 py-2 bg-blue-500 text-white rounded-lg hover:bg-blue-600 disabled:bg-gray-300 disabled:cursor-not-allowed transition-colors font-medium"
	>
		Send
	</button>
</div>
