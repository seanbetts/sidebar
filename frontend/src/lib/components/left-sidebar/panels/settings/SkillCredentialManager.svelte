<script lang="ts">
	import { Check, Key, Trash2, X } from 'lucide-svelte';
	import {
		fetchProviderStatus,
		saveProviderKey,
		deleteProviderKey
	} from '$lib/components/left-sidebar/panels/settingsApi';
	import { onMount } from 'svelte';

	export let credentialRequirements: Array<{
		provider: string;
		key_kind: string;
		required: boolean;
	}> = [];

	type ProviderState = {
		connected: boolean;
		lastFour?: string;
		loading: boolean;
		error: string;
		inputValue: string;
		showInput: boolean;
		saving: boolean;
		deleting: boolean;
	};

	let providerStates: Record<string, ProviderState> = {};

	onMount(() => {
		const providers = [...new Set(credentialRequirements.map((r) => r.provider))];
		for (const provider of providers) {
			providerStates[provider] = {
				connected: false,
				lastFour: undefined,
				loading: true,
				error: '',
				inputValue: '',
				showInput: false,
				saving: false,
				deleting: false
			};
			loadProviderStatus(provider);
		}
	});

	async function loadProviderStatus(provider: string) {
		try {
			const data = await fetchProviderStatus(provider);
			providerStates[provider] = {
				...providerStates[provider],
				connected: data?.connected ?? false,
				lastFour: data?.last_four ?? undefined,
				loading: false,
				error: ''
			};
		} catch {
			providerStates[provider] = {
				...providerStates[provider],
				connected: false,
				loading: false,
				error: 'Failed to load status'
			};
		}
	}

	async function handleSave(provider: string) {
		const state = providerStates[provider];
		if (!state || !state.inputValue.trim()) return;
		providerStates[provider] = { ...state, saving: true, error: '' };
		try {
			const data = await saveProviderKey(provider, state.inputValue.trim());
			providerStates[provider] = {
				...providerStates[provider],
				connected: true,
				lastFour: data?.last_four ?? state.inputValue.slice(-4),
				inputValue: '',
				showInput: false,
				saving: false,
				error: ''
			};
		} catch {
			providerStates[provider] = {
				...providerStates[provider],
				saving: false,
				error: 'Failed to save key'
			};
		}
	}

	async function handleDelete(provider: string) {
		const state = providerStates[provider];
		if (!state) return;
		providerStates[provider] = { ...state, deleting: true, error: '' };
		try {
			await deleteProviderKey(provider);
			providerStates[provider] = {
				...providerStates[provider],
				connected: false,
				lastFour: undefined,
				deleting: false,
				error: ''
			};
		} catch {
			providerStates[provider] = {
				...providerStates[provider],
				deleting: false,
				error: 'Failed to remove key'
			};
		}
	}

	$: uniqueProviders = [...new Set(credentialRequirements.map((r) => r.provider))];
</script>

<div class="credential-manager">
	<div class="credential-title">API Keys Required</div>
	{#each uniqueProviders as provider}
		{@const state = providerStates[provider]}
		{#if state}
			<div class="credential-row">
				<div class="credential-info">
					<div class="credential-provider">
						<Key size={14} />
						<span>{provider}</span>
					</div>
					{#if state.loading}
						<span class="credential-status muted">Loading…</span>
					{:else if state.connected}
						<div class="credential-connected">
							<Check size={12} />
							<span>Connected{state.lastFour ? ` (…${state.lastFour})` : ''}</span>
						</div>
					{:else}
						<span class="credential-status missing">Not connected</span>
					{/if}
				</div>
				<div class="credential-actions">
					{#if state.connected}
						<button
							class="credential-btn credential-btn-remove"
							onclick={() => handleDelete(provider)}
							disabled={state.deleting}
							aria-label="Remove key"
						>
							{#if state.deleting}
								Removing…
							{:else}
								<Trash2 size={13} />
							{/if}
						</button>
					{:else if state.showInput}
						<button
							class="credential-btn credential-btn-cancel"
							onclick={() =>
								(providerStates[provider] = {
									...providerStates[provider],
									showInput: false,
									inputValue: '',
									error: ''
								})}
							aria-label="Cancel"
						>
							<X size={13} />
						</button>
					{:else}
						<button
							class="credential-btn credential-btn-add"
							onclick={() =>
								(providerStates[provider] = {
									...providerStates[provider],
									showInput: true
								})}
						>
							Add key
						</button>
					{/if}
				</div>
			</div>
			{#if state.showInput && !state.connected}
				<div class="credential-input-row">
					<input
						class="credential-input"
						type="password"
						placeholder="Paste API key…"
						bind:value={providerStates[provider].inputValue}
						onkeydown={(e) => e.key === 'Enter' && handleSave(provider)}
					/>
					<button
						class="credential-btn credential-btn-save"
						onclick={() => handleSave(provider)}
						disabled={state.saving || !state.inputValue.trim()}
					>
						{state.saving ? 'Saving…' : 'Save'}
					</button>
				</div>
			{/if}
			{#if state.error}
				<div class="credential-error">{state.error}</div>
			{/if}
		{/if}
	{/each}
</div>

<style>
	.credential-manager {
		display: flex;
		flex-direction: column;
		gap: 0.6rem;
		padding: 0.75rem;
		border: 1px solid var(--color-border);
		border-radius: 0.75rem;
		background: color-mix(in oklab, var(--color-card) 60%, transparent);
	}

	.credential-title {
		font-size: 0.72rem;
		font-weight: 600;
		text-transform: uppercase;
		letter-spacing: 0.06em;
		color: var(--color-muted-foreground);
		margin-bottom: 0.15rem;
	}

	.credential-row {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 0.75rem;
	}

	.credential-info {
		display: flex;
		align-items: center;
		gap: 0.6rem;
		min-width: 0;
	}

	.credential-provider {
		display: inline-flex;
		align-items: center;
		gap: 0.3rem;
		font-size: 0.85rem;
		font-weight: 500;
		color: var(--color-foreground);
	}

	.credential-connected {
		display: inline-flex;
		align-items: center;
		gap: 0.25rem;
		font-size: 0.75rem;
		color: #2f8a4d;
	}

	.credential-status {
		font-size: 0.75rem;
	}

	.credential-status.muted {
		color: var(--color-muted-foreground);
	}

	.credential-status.missing {
		color: var(--color-muted-foreground);
	}

	.credential-actions {
		flex-shrink: 0;
	}

	.credential-btn {
		display: inline-flex;
		align-items: center;
		gap: 0.3rem;
		border: 1px solid var(--color-border);
		border-radius: 999px;
		padding: 0.3rem 0.6rem;
		font-size: 0.75rem;
		background: transparent;
		color: var(--color-muted-foreground);
		cursor: pointer;
		transition: background 0.15s;
	}

	.credential-btn:hover:not(:disabled) {
		background: var(--color-sidebar-accent);
		color: var(--color-foreground);
	}

	.credential-btn:disabled {
		opacity: 0.55;
		cursor: not-allowed;
	}

	.credential-btn-add {
		color: var(--color-foreground);
	}

	.credential-btn-remove {
		color: var(--color-muted-foreground);
	}

	.credential-btn-save {
		color: var(--color-foreground);
		font-weight: 500;
	}

	.credential-input-row {
		display: flex;
		gap: 0.5rem;
		align-items: center;
	}

	.credential-input {
		flex: 1;
		border: 1px solid var(--color-border);
		border-radius: 0.5rem;
		padding: 0.4rem 0.6rem;
		font-size: 0.8rem;
		background: var(--color-card);
		color: var(--color-foreground);
		min-width: 0;
	}

	.credential-input:focus {
		outline: none;
		border-color: var(--color-ring);
	}

	.credential-error {
		font-size: 0.75rem;
		color: #d55b5b;
	}
</style>
