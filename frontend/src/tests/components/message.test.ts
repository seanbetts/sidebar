import { render, screen } from '@testing-library/svelte';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import Message from '$lib/components/chat/Message.svelte';
import type { Message as ChatMessage } from '$lib/types/chat';

const { createStubComponent } = vi.hoisted(() => ({
	createStubComponent:
		() =>
		({ target }: { target: HTMLElement }) => {
			if (target) {
				const el = document.createElement('div');
				target.appendChild(el);
			}
			return {
				$set() {},
				$destroy() {}
			};
		}
}));

vi.mock('$lib/components/ui/tooltip', () => ({
	Tooltip: createStubComponent(),
	TooltipTrigger: createStubComponent(),
	TooltipContent: createStubComponent()
}));

vi.mock('$lib/components/chat/ChatMarkdown.svelte', () => ({
	default: ({ target, props }: { target: HTMLElement; props: { content: string } }) => {
		if (target) {
			const el = document.createElement('div');
			el.textContent = props.content;
			target.appendChild(el);
		}
		return {
			$set() {},
			$destroy() {}
		};
	}
}));

function makeMessage(overrides: Partial<ChatMessage> = {}): ChatMessage {
	return {
		id: 'message-1',
		role: 'assistant',
		content: '',
		status: 'streaming',
		timestamp: new Date('2026-04-19T12:00:00.000Z'),
		...overrides
	};
}

describe('Message', () => {
	beforeEach(() => {
		vi.useFakeTimers();
	});

	afterEach(() => {
		vi.useRealTimers();
	});

	it('shows inline thinking state instead of Working text', () => {
		render(Message, {
			props: { message: makeMessage(), activeTool: null }
		});

		expect(screen.getByText('Thinking...')).toBeInTheDocument();
		expect(screen.queryByText('Working...')).not.toBeInTheDocument();
	});

	it('removes the thinking label once streamed content exists', () => {
		render(Message, {
			props: {
				message: makeMessage({
					content: 'Hello',
					status: 'streaming'
				}),
				activeTool: null
			}
		});

		expect(screen.queryByText('Thinking...')).not.toBeInTheDocument();
	});

	it('shows a brief completion acknowledgement when an assistant message completes', async () => {
		const { rerender } = render(Message, {
			props: {
				message: makeMessage({
					content: 'Done',
					status: 'streaming'
				}),
				activeTool: null
			}
		});

		await rerender({
			message: makeMessage({
				content: 'Done',
				status: 'complete'
			}),
			activeTool: null
		});

		expect(screen.getByText('Complete')).toBeInTheDocument();

		await vi.advanceTimersByTimeAsync(1500);

		expect(screen.queryByText('Complete')).not.toBeInTheDocument();
	});
});
