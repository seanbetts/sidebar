<script lang="ts">
	import { Button } from '$lib/components/ui/button';

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

<div class="flex gap-2 p-4 border-t bg-background">
	<textarea
		bind:value={inputValue}
		onkeydown={handleKeydown}
		placeholder="Type your message... (Enter to send, Shift+Enter for new line)"
		{disabled}
		rows="3"
		class="flex-1 p-3 border rounded-lg resize-none bg-background text-foreground placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring disabled:cursor-not-allowed disabled:opacity-50"
	></textarea>
	<Button onclick={handleSubmit} disabled={disabled || !inputValue.trim()} class="px-6">
		Send
	</Button>
</div>
