<script lang="ts">
	import { Loader2 } from 'lucide-svelte';
	import type { WeatherUnit } from '$lib/stores/weatherPreferences';

	export let communicationStyle = '';
	export let workingRelationship = '';
	export let weatherUnit: WeatherUnit = 'celsius';
	export let setWeatherUnit: (unit: WeatherUnit) => void;
	export let isLoadingSettings = false;
	export let settingsError = '';

	function handleWeatherUnitChange(event: Event) {
		const target = event.currentTarget as HTMLSelectElement | null;
		if (!target) return;
		const unit: WeatherUnit = target.value === 'fahrenheit' ? 'fahrenheit' : 'celsius';
		weatherUnit = unit;
		setWeatherUnit(unit);
	}
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
	<label class="settings-label">
		<span>Temperature units</span>
		<select
			class="settings-input"
			bind:value={weatherUnit}
			disabled={isLoadingSettings}
			on:change={handleWeatherUnitChange}
		>
			<option value="celsius">Celsius</option>
			<option value="fahrenheit">Fahrenheit</option>
		</select>
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
