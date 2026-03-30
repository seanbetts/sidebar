import { render, screen } from '@testing-library/svelte';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import ConversationList from '$lib/components/left-sidebar/ConversationList.svelte';

const {
	createStubComponent,
	conversationListStore,
	groupedConversations,
	setConversationState,
	setGroupedState
} = vi.hoisted(() => {
	const createStore = <T>(initial: T) => {
		let value = initial;
		const subscribers = new Set<(next: T) => void>();
		return {
			subscribe(run: (next: T) => void) {
				run(value);
				subscribers.add(run);
				return () => subscribers.delete(run);
			},
			set(next: T) {
				value = next;
				subscribers.forEach((fn) => fn(value));
			}
		};
	};

	const conversationState = createStore({
		loading: false,
		conversations: [] as Array<Record<string, unknown>>,
		searchQuery: ''
	});
	const groupedState = createStore({
		today: [],
		yesterday: [],
		lastWeek: [],
		lastMonth: [],
		older: []
	});

	return {
		createStubComponent:
			() =>
			({ target }: { target: HTMLElement }) => {
				if (target) {
					const el = document.createElement('div');
					target.appendChild(el);
				}
				return { $set() {}, $destroy() {} };
			},
		conversationListStore: { subscribe: conversationState.subscribe },
		groupedConversations: { subscribe: groupedState.subscribe },
		setConversationState: conversationState.set,
		setGroupedState: groupedState.set
	};
});

vi.mock('$lib/stores/conversations', () => ({
	conversationListStore,
	groupedConversations
}));

vi.mock('$lib/components/left-sidebar/ConversationItem.svelte', () => ({
	default: createStubComponent()
}));

describe('ConversationList', () => {
	beforeEach(() => {
		setConversationState({
			loading: false,
			conversations: [],
			searchQuery: ''
		});
		setGroupedState({
			today: [],
			yesterday: [],
			lastWeek: [],
			lastMonth: [],
			older: []
		});
	});

	it('shows the standardized empty chat copy', () => {
		render(ConversationList);

		expect(screen.getByText('No conversations')).toBeInTheDocument();
		expect(screen.queryByText('No conversations yet')).not.toBeInTheDocument();
	});
});
