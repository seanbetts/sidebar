<script lang="ts">
	import { MessageSquare, Search } from 'lucide-svelte';
	import { groupedConversations, conversationListStore } from '$lib/stores/conversations';
	import SidebarEmptyState from '$lib/components/left-sidebar/SidebarEmptyState.svelte';
	import SidebarLoading from '$lib/components/left-sidebar/SidebarLoading.svelte';
	import ConversationItem from './ConversationItem.svelte';

	const groupLabels = {
		today: 'Today',
		yesterday: 'Yesterday',
		lastWeek: 'Last 7 days',
		lastMonth: 'Last 30 days',
		older: 'Older'
	} as const;

	type GroupKey = keyof typeof groupLabels;
</script>

<div class="conversation-list">
	{#if $conversationListStore.loading}
		<SidebarLoading message="Loading conversations..." />
	{:else if $conversationListStore.conversations.length === 0}
		{#if $conversationListStore.searchQuery}
			<SidebarEmptyState icon={Search} title="No results" subtitle="Try a different search." />
		{:else}
			<SidebarEmptyState
				icon={MessageSquare}
				title="No conversations yet"
				subtitle="Start a new chat to begin."
			/>
		{/if}
	{:else}
		{#each Object.entries($groupedConversations) as [groupKey, conversations]}
			{#if conversations.length > 0}
				<div class="group">
					<div class="group-label">{groupLabels[groupKey as GroupKey]}</div>
					{#each conversations as conversation (conversation.id)}
						<ConversationItem {conversation} />
					{/each}
				</div>
			{/if}
		{/each}
	{/if}
</div>

<style>
	.conversation-list {
		flex: 1;
		overflow-y: auto;
		overflow-x: hidden;
	}

	/* Empty state handled by SidebarEmptyState */

	.group {
		margin-bottom: 1rem;
	}

	.group-label {
		padding: 0.5rem 1rem;
		font-size: 0.75rem;
		font-weight: 600;
		color: var(--color-muted-foreground);
		text-transform: uppercase;
		letter-spacing: 0.05em;
	}

	/* Custom scrollbar */
	.conversation-list::-webkit-scrollbar {
		width: 6px;
	}

	.conversation-list::-webkit-scrollbar-track {
		background: transparent;
	}

	.conversation-list::-webkit-scrollbar-thumb {
		background: var(--color-sidebar-border);
		border-radius: 3px;
	}

	.conversation-list::-webkit-scrollbar-thumb:hover {
		background: var(--color-muted-foreground);
	}
</style>
