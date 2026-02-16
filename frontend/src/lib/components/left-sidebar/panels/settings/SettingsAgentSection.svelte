<script lang="ts">
	export let assistantIdentityName = '';
	export let assistantIdentityTone = '';
	export let assistantIdentityValues = '';
	export let assistantIdentityBoundaries = '';
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
</div>
