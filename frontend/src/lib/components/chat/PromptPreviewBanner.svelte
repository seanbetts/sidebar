<script lang="ts">
	import type { PromptPreviewReportDocument, PromptPreviewSection } from '$lib/types/promptPreview';

	export let systemPrompt: string | null = null;
	export let firstMessagePrompt: string | null = null;
	export let systemPromptSections: PromptPreviewSection[] = [];
	export let firstMessagePromptSections: PromptPreviewSection[] = [];
	export let promptReport: {
		system_prompt?: PromptPreviewReportDocument;
		first_message_prompt?: PromptPreviewReportDocument;
	} | null = null;

	function describeReport(doc: PromptPreviewReportDocument | undefined): string {
		if (!doc) return 'No diagnostics';
		const base = `${doc.total_chars}/${doc.max_chars} chars`;
		return doc.truncated ? `${base} (truncated)` : base;
	}
</script>

<div class="prompt-preview-banner">
	<div class="prompt-preview-label">System Prompt Preview</div>
	{#if promptReport}
		<div class="prompt-preview-metrics">
			<span>System: {describeReport(promptReport.system_prompt)}</span>
			<span>First: {describeReport(promptReport.first_message_prompt)}</span>
		</div>
	{/if}

	{#if systemPromptSections.length > 0}
		<div class="prompt-preview-section-list">
			{#each systemPromptSections as section (section.id)}
				<span class="prompt-preview-section-item">{section.id} ({section.chars})</span>
			{/each}
		</div>
	{/if}

	{#if firstMessagePromptSections.length > 0}
		<div class="prompt-preview-section-list">
			{#each firstMessagePromptSections as section (section.id)}
				<span class="prompt-preview-section-item">{section.id} ({section.chars})</span>
			{/each}
		</div>
	{/if}

	{#if systemPrompt}
		<details class="prompt-preview-details">
			<summary>System prompt text</summary>
			<pre>{systemPrompt}</pre>
		</details>
	{/if}
	{#if firstMessagePrompt}
		<details class="prompt-preview-details">
			<summary>First message prompt text</summary>
			<pre>{firstMessagePrompt}</pre>
		</details>
	{/if}
</div>

<style>
	.prompt-preview-banner {
		display: flex;
		flex-direction: column;
		gap: 0.35rem;
		padding: 0.4rem 0.55rem;
		border: 1px solid var(--color-border);
		border-radius: 0.6rem;
		background: color-mix(in oklab, var(--color-card) 82%, transparent);
	}

	.prompt-preview-label {
		font-size: 0.72rem;
		text-transform: uppercase;
		letter-spacing: 0.06em;
		color: var(--color-muted-foreground);
	}

	.prompt-preview-metrics {
		display: flex;
		flex-wrap: wrap;
		gap: 0.45rem 0.75rem;
		font-size: 0.72rem;
		color: var(--color-foreground);
	}

	.prompt-preview-section-list {
		display: flex;
		flex-wrap: wrap;
		gap: 0.25rem;
	}

	.prompt-preview-section-item {
		font-size: 0.7rem;
		color: var(--color-foreground);
		border: 1px solid var(--color-border);
		background: color-mix(in oklab, var(--color-background) 90%, transparent);
		border-radius: 999px;
		padding: 0.12rem 0.45rem;
	}

	.prompt-preview-details {
		border-top: 1px dashed var(--color-border);
		padding-top: 0.3rem;
	}

	.prompt-preview-details summary {
		cursor: pointer;
		font-size: 0.72rem;
		color: var(--color-muted-foreground);
	}

	.prompt-preview-details pre {
		margin: 0.35rem 0 0;
		white-space: pre-wrap;
		font-size: 0.72rem;
		color: var(--color-foreground);
		max-height: 10rem;
		overflow: auto;
	}
</style>
