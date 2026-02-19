import { fireEvent, render } from '@testing-library/svelte';
import { tick } from 'svelte';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import type { Message as MessageType } from '$lib/types/chat';
import MessageList from '$lib/components/chat/MessageList.svelte';

const { createStubComponent } = vi.hoisted(() => ({
	createStubComponent:
		(testId: string) =>
		({ target }: { target: HTMLElement }) => {
			if (target) {
				const el = document.createElement('div');
				el.dataset.testid = testId;
				target.appendChild(el);
			}
			return {
				$set() {},
				$destroy() {}
			};
		}
}));

vi.mock('$lib/components/chat/Message.svelte', () => ({
	default: createStubComponent('message-row')
}));

type MutableScrollMetrics = {
	getScrollTop: () => number;
	setScrollTop: (value: number) => void;
	setScrollHeight: (value: number) => void;
	setClientHeight: (value: number) => void;
};

function installScrollMetrics(
	element: HTMLElement,
	initial: { scrollHeight: number; clientHeight: number; scrollTop: number }
): MutableScrollMetrics {
	let scrollHeight = initial.scrollHeight;
	let clientHeight = initial.clientHeight;
	let scrollTop = initial.scrollTop;

	Object.defineProperty(element, 'scrollHeight', {
		configurable: true,
		get: () => scrollHeight
	});
	Object.defineProperty(element, 'clientHeight', {
		configurable: true,
		get: () => clientHeight
	});
	Object.defineProperty(element, 'scrollTop', {
		configurable: true,
		get: () => scrollTop,
		set: (value: number) => {
			scrollTop = value;
		}
	});

	return {
		getScrollTop: () => scrollTop,
		setScrollTop: (value: number) => {
			scrollTop = value;
		},
		setScrollHeight: (value: number) => {
			scrollHeight = value;
		},
		setClientHeight: (value: number) => {
			clientHeight = value;
		}
	};
}

function createMessages(prefix: string): MessageType[] {
	return [
		{
			id: `${prefix}-1`,
			role: 'user',
			content: `${prefix}-user`,
			status: 'complete',
			timestamp: new Date('2026-02-16T00:00:00.000Z')
		},
		{
			id: `${prefix}-2`,
			role: 'assistant',
			content: `${prefix}-assistant`,
			status: 'complete',
			timestamp: new Date('2026-02-16T00:00:01.000Z')
		}
	];
}

let resizeObserverCallback: ResizeObserverCallback | null = null;

async function flushScrollWork() {
	await tick();
	await Promise.resolve();
}

beforeEach(() => {
	resizeObserverCallback = null;

	class ResizeObserverMock {
		constructor(callback: ResizeObserverCallback) {
			resizeObserverCallback = callback;
		}

		observe() {}

		disconnect() {}
	}

	vi.stubGlobal('ResizeObserver', ResizeObserverMock as unknown as typeof ResizeObserver);
	vi.stubGlobal('requestAnimationFrame', ((callback: FrameRequestCallback): number => {
		callback(0);
		return 1;
	}) as typeof requestAnimationFrame);
	vi.stubGlobal('cancelAnimationFrame', vi.fn());
});

afterEach(() => {
	vi.unstubAllGlobals();
});

describe('MessageList', () => {
	it('scrolls to bottom on initial render when messages exist', async () => {
		const { container } = render(MessageList, {
			props: { messages: createMessages('initial'), conversationId: 'conv-1', activeTool: null }
		});
		const list = container.querySelector('.message-list') as HTMLElement;
		const metrics = installScrollMetrics(list, {
			scrollHeight: 900,
			clientHeight: 300,
			scrollTop: 0
		});

		await flushScrollWork();

		expect(metrics.getScrollTop()).toBe(900);
	});

	it('scrolls to bottom when conversation changes even if message count is unchanged', async () => {
		const { container, rerender } = render(MessageList, {
			props: { messages: createMessages('one'), conversationId: 'conv-1', activeTool: null }
		});
		const list = container.querySelector('.message-list') as HTMLElement;
		const metrics = installScrollMetrics(list, {
			scrollHeight: 1100,
			clientHeight: 400,
			scrollTop: 0
		});

		await flushScrollWork();
		metrics.setScrollTop(120);
		await fireEvent.scroll(list);
		metrics.setScrollHeight(1600);

		await rerender({
			messages: createMessages('two'),
			conversationId: 'conv-2',
			activeTool: null
		});
		await flushScrollWork();

		expect(metrics.getScrollTop()).toBe(1600);
	});

	it('re-pins to bottom on window resize when user is near bottom', async () => {
		const { container } = render(MessageList, {
			props: { messages: createMessages('resize-near'), conversationId: 'conv-3', activeTool: null }
		});
		const list = container.querySelector('.message-list') as HTMLElement;
		const metrics = installScrollMetrics(list, {
			scrollHeight: 1200,
			clientHeight: 400,
			scrollTop: 0
		});

		await flushScrollWork();
		metrics.setScrollTop(800);
		await fireEvent.scroll(list);

		metrics.setScrollHeight(1700);
		window.dispatchEvent(new Event('resize'));
		await flushScrollWork();

		expect(metrics.getScrollTop()).toBe(1700);
	});

	it('does not force scroll on resize when user has scrolled away from bottom', async () => {
		const { container } = render(MessageList, {
			props: { messages: createMessages('resize-away'), conversationId: 'conv-4', activeTool: null }
		});
		const list = container.querySelector('.message-list') as HTMLElement;
		const metrics = installScrollMetrics(list, {
			scrollHeight: 1400,
			clientHeight: 400,
			scrollTop: 0
		});

		await flushScrollWork();
		metrics.setScrollTop(120);
		await fireEvent.scroll(list);

		metrics.setScrollHeight(1900);
		window.dispatchEvent(new Event('resize'));
		await flushScrollWork();

		expect(metrics.getScrollTop()).toBe(120);
	});

	it('re-pins to bottom when message content grows after render', async () => {
		const { container } = render(MessageList, {
			props: { messages: createMessages('growth'), conversationId: 'conv-5', activeTool: null }
		});
		const list = container.querySelector('.message-list') as HTMLElement;
		const messagesContainer = container.querySelector('.messages-container') as HTMLElement;
		const metrics = installScrollMetrics(list, {
			scrollHeight: 1000,
			clientHeight: 350,
			scrollTop: 0
		});

		await flushScrollWork();
		metrics.setScrollHeight(1550);
		if (!resizeObserverCallback) {
			throw new Error('ResizeObserver callback was not registered');
		}
		resizeObserverCallback(
			[
				{
					target: messagesContainer,
					contentRect: messagesContainer.getBoundingClientRect()
				} as unknown as ResizeObserverEntry
			],
			{} as ResizeObserver
		);
		await flushScrollWork();

		expect(metrics.getScrollTop()).toBe(1550);
	});
});
