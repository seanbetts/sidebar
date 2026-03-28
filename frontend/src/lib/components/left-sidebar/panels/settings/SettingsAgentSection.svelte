<script lang="ts">
	export let assistantIdentityName = '';
	export let assistantIdentityTone = '';
	export let assistantIdentityValues = '';
	export let assistantIdentityBoundaries = '';
	export let assistantIdentityMeta: {
		updated_at?: string;
		version?: number;
		reason?: string | null;
	} = {};
	export let assistantSoulPurpose = '';
	export let assistantSoulOperatingPrinciples = '';
	export let assistantSoulAdaptationPolicy = '';
	export let assistantSoulSuccessSignals = '';
	export let assistantSoulMeta: { updated_at?: string; version?: number; reason?: string | null } =
		{};

	$: assistantDisplayName = assistantIdentityName.trim() || 'Assistant';
	$: purposeLabel = `${assistantDisplayName}'s Purpose`;
	$: operatingPrinciplesLabel = `${assistantDisplayName}'s Operating Principles`;
	$: adaptationPolicyLabel = `${assistantDisplayName}'s Adaptation Policy`;
	$: successSignalsLabel = `${assistantDisplayName}'s Success Signals`;
</script>

<h3>Agent</h3>
<p>Managed by the assistant. User edits are disabled for these fields.</p>
<div class="settings-form">
	<label class="settings-label">
		<span>Assistant name</span>
		<input class="settings-input" value={assistantIdentityName} readonly aria-readonly="true" />
	</label>
	<label class="settings-label">
		<span>Assistant tone</span>
		<textarea
			class="settings-textarea"
			value={assistantIdentityTone}
			rows="4"
			readonly
			aria-readonly="true"
		></textarea>
	</label>
	<label class="settings-label">
		<span>Assistant values</span>
		<textarea
			class="settings-textarea"
			value={assistantIdentityValues}
			rows="4"
			readonly
			aria-readonly="true"
		></textarea>
	</label>
	<label class="settings-label">
		<span>Assistant boundaries</span>
		<textarea
			class="settings-textarea"
			value={assistantIdentityBoundaries}
			rows="4"
			readonly
			aria-readonly="true"
		></textarea>
	</label>
	{#if assistantIdentityMeta?.updated_at}
		<p class="settings-meta">
			Identity updated {assistantIdentityMeta.updated_at} (v{assistantIdentityMeta.version ?? 1})
			{#if assistantIdentityMeta.reason}
				- {assistantIdentityMeta.reason}
			{/if}
		</p>
	{/if}
	<label class="settings-label">
		<span>{purposeLabel}</span>
		<textarea
			class="settings-textarea"
			value={assistantSoulPurpose}
			rows="3"
			readonly
			aria-readonly="true"
		></textarea>
	</label>
	<label class="settings-label">
		<span>{operatingPrinciplesLabel}</span>
		<textarea
			class="settings-textarea"
			value={assistantSoulOperatingPrinciples}
			rows="4"
			readonly
			aria-readonly="true"
		></textarea>
	</label>
	<label class="settings-label">
		<span>{adaptationPolicyLabel}</span>
		<textarea
			class="settings-textarea"
			value={assistantSoulAdaptationPolicy}
			rows="4"
			readonly
			aria-readonly="true"
		></textarea>
	</label>
	<label class="settings-label">
		<span>{successSignalsLabel}</span>
		<textarea
			class="settings-textarea"
			value={assistantSoulSuccessSignals}
			rows="3"
			readonly
			aria-readonly="true"
		></textarea>
	</label>
	{#if assistantSoulMeta?.updated_at}
		<p class="settings-meta">
			Soul updated {assistantSoulMeta.updated_at} (v{assistantSoulMeta.version ?? 1})
			{#if assistantSoulMeta.reason}
				- {assistantSoulMeta.reason}
			{/if}
		</p>
	{/if}
</div>
