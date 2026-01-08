<script lang="ts">
	import { Loader2 } from 'lucide-svelte';

	export let communicationStyle = '';
	export let workingRelationship = '';
	export let isLoadingSettings = false;
	export let settingsError = '';
</script>

<h3>System</h3>
<p>Customize the prompts that guide your assistant.</p>
<div class="settings-form">
	<label class="settings-label">
		<span>Communication style</span>
		<textarea
			class="settings-textarea"
			bind:value={communicationStyle}
			placeholder="Style, tone, and formatting rules."
			rows="8"
		></textarea>
	</label>
	<label class="settings-label">
		<span>Working relationship</span>
		<textarea
			class="settings-textarea"
			bind:value={workingRelationship}
			placeholder="How the assistant should challenge and collaborate with you."
			rows="8"
		></textarea>
	</label>
	<div class="settings-actions">
		{#if isLoadingSettings}
			<div class="settings-meta">
				<Loader2 size={16} class="spin" />
				Loading...
			</div>
		{/if}
	</div>
	{#if settingsError}
		<div class="settings-error">{settingsError}</div>
	{/if}
</div>
