<script lang="ts">
	import { onMount, tick } from 'svelte';
	import { Button } from '$lib/components/ui/button';
	import { Paperclip, Send } from 'lucide-svelte';
	import { chatStore } from '$lib/stores/chat';

	export let disabled = false;
	export let onsend: ((message: string) => void) | undefined = undefined;
	export let onattach: ((files: FileList) => void) | undefined = undefined;

	let inputValue = '';
	let textarea: HTMLTextAreaElement;
	let attachmentInput: HTMLInputElement;
	let previousConversationId: string | null = null;
	const MAX_TEXTAREA_HEIGHT = 220;

	const resizeTextarea = () => {
		if (!textarea) return;
		textarea.style.height = 'auto';
		const nextHeight = Math.min(textarea.scrollHeight, MAX_TEXTAREA_HEIGHT);
		textarea.style.height = `${nextHeight}px`;
		textarea.style.overflowY = textarea.scrollHeight > MAX_TEXTAREA_HEIGHT ? 'auto' : 'hidden';
	};

	onMount(() => {
		// Auto-focus the input when component mounts
		textarea?.focus();
		resizeTextarea();
	});

	// Auto-focus when conversation changes (new chat)
	$: if ($chatStore.conversationId !== previousConversationId) {
		previousConversationId = $chatStore.conversationId;
		tick().then(() => {
			textarea?.focus();
			resizeTextarea();
		});
	}

	$: if (textarea && inputValue !== undefined) {
		resizeTextarea();
	}

	function handleSubmit() {
		const message = inputValue.trim();
		if (message && !disabled) {
			onsend?.(message);
			inputValue = '';
			// Re-focus after sending
			tick().then(() => {
				textarea?.focus();
				resizeTextarea();
			});
		}
	}

	function handleKeydown(event: KeyboardEvent) {
		if (event.key === 'Enter' && !event.shiftKey) {
			event.preventDefault();
			handleSubmit();
		}
	}

	function handleAttachClick() {
		attachmentInput?.click();
	}

	function handleAttachChange(event: Event) {
		const target = event.target as HTMLInputElement;
		if (target.files && target.files.length > 0) {
			onattach?.(target.files);
			target.value = '';
		}
	}
</script>

<div class="chat-input-bar">
	<div class="chat-input-shell">
		<textarea
			bind:this={textarea}
			bind:value={inputValue}
			onkeydown={handleKeydown}
			oninput={resizeTextarea}
			placeholder="Ask Anything..."
			{disabled}
			rows="1"
			class="chat-input-textarea"
		></textarea>
		<div class="chat-input-actions">
			<div class="chat-input-left">
				<input
					type="file"
					bind:this={attachmentInput}
					onchange={handleAttachChange}
					class="attachment-input"
					multiple
				/>
				<Button
					size="icon"
					variant="ghost"
					onclick={handleAttachClick}
					aria-label="Attach file"
					title="Attach file"
					disabled={disabled}
				>
					<Paperclip size={16} />
				</Button>
			</div>
			<Button
				onclick={handleSubmit}
				disabled={disabled || !inputValue.trim()}
				size="icon"
				aria-label="Send message"
			>
				<Send size={16} />
			</Button>
		</div>
	</div>
</div>

<style>
	.chat-input-bar {
		padding: 1rem;
		background-color: var(--color-background);
	}

	.chat-input-shell {
		display: flex;
		flex-direction: column;
		gap: 0.5rem;
		border: 1px solid var(--color-border);
		border-radius: 0.9rem;
		padding: 0.75rem 0.75rem 0.6rem;
		background-color: var(--color-card);
		max-width: 860px;
		margin: 0 auto;
	}

	.chat-input-textarea {
		width: 100%;
		min-height: 38px;
		border: none;
		outline: none;
		resize: none;
		background-color: transparent;
		color: var(--color-foreground);
		font-size: 0.95rem;
		line-height: 1.5;
	}

	.chat-input-textarea::placeholder {
		color: var(--color-muted-foreground);
	}

	.chat-input-textarea:disabled {
		opacity: 0.6;
		cursor: not-allowed;
	}

	.chat-input-actions {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 0.75rem;
	}

	.chat-input-left {
		min-height: 1px;
		flex: 1;
		display: flex;
		align-items: center;
		gap: 0.5rem;
	}

	.attachment-input {
		display: none;
	}
</style>
