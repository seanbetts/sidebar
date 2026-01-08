import { beforeEach, describe, expect, it, vi } from 'vitest';

const storeState = {
	conversations: [{ id: 'conv-1', titleGenerated: false }],
	setGeneratingTitle: vi.fn(),
	updateConversationTitle: vi.fn()
};

const conversationListStore = {
	subscribe: (fn: (value: any) => void) => {
		fn(storeState);
		return () => {};
	},
	setGeneratingTitle: storeState.setGeneratingTitle,
	updateConversationTitle: storeState.updateConversationTitle
};

vi.mock('$lib/stores/conversations', () => ({ conversationListStore }));

describe('generateConversationTitle', () => {
	beforeEach(() => {
		storeState.setGeneratingTitle.mockClear();
		storeState.updateConversationTitle.mockClear();
		storeState.conversations = [{ id: 'conv-1', titleGenerated: false }];
	});

	it('skips when already generated', async () => {
		storeState.conversations = [{ id: 'conv-1', titleGenerated: true }];
		const { generateConversationTitle } = await import('$lib/stores/chat/generateTitle');

		await generateConversationTitle('conv-1');

		expect(storeState.setGeneratingTitle).not.toHaveBeenCalled();
	});

	it('updates title on success', async () => {
		vi.spyOn(global, 'fetch').mockResolvedValue({
			ok: true,
			json: async () => ({ title: 'New title', fallback: false })
		} as Response);
		const { generateConversationTitle } = await import('$lib/stores/chat/generateTitle');

		await generateConversationTitle('conv-1');

		expect(storeState.setGeneratingTitle).toHaveBeenCalledWith('conv-1', true);
		expect(storeState.updateConversationTitle).toHaveBeenCalledWith('conv-1', 'New title', true);
	});

	it('clears generating on failure', async () => {
		vi.spyOn(global, 'fetch').mockResolvedValue({
			ok: false,
			statusText: 'error'
		} as Response);
		const { generateConversationTitle } = await import('$lib/stores/chat/generateTitle');

		await generateConversationTitle('conv-1');

		expect(storeState.setGeneratingTitle).toHaveBeenCalledWith('conv-1', false);
	});
});
