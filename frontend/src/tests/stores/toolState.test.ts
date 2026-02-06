import { describe, expect, it, vi, beforeEach } from 'vitest';
import { createToolStateHandlers } from '$lib/stores/chat/toolState';

describe('toolState handlers', () => {
	let state: any;
	let update: (fn: (s: any) => any) => void;
	let getState: () => any;

	beforeEach(() => {
		state = {
			messages: [{ id: 'msg-1', needsNewline: false }],
			activeTool: null
		};
		update = (fn) => {
			state = fn(state);
		};
		getState = () => state;
	});

	it('sets active tool status', () => {
		const handlers = createToolStateHandlers(update, getState);
		handlers.setActiveTool('msg-1', 'tool', 'running');

		expect(state.activeTool?.name).toBe('tool');
		expect(state.activeTool?.status).toBe('running');
	});

	it('finalizes tool status and marks newline on error', () => {
		vi.useFakeTimers();
		const handlers = createToolStateHandlers(update, getState);
		handlers.setActiveTool('msg-1', 'tool', 'running');

		handlers.finalizeActiveTool('msg-1', 'tool', 'error', 0, 10);
		vi.runAllTimers();

		expect(state.messages[0].needsNewline).toBe(true);
		expect(state.activeTool).toBeNull();
		vi.useRealTimers();
	});

	it('finalizes successful tool status and clears indicator', () => {
		vi.useFakeTimers();
		const handlers = createToolStateHandlers(update, getState);
		handlers.setActiveTool('msg-1', 'tool', 'running');

		handlers.finalizeActiveTool('msg-1', 'tool', 'success', 0, 10);
		vi.runAllTimers();

		expect(state.messages[0].needsNewline).toBe(false);
		expect(state.activeTool).toBeNull();
		vi.useRealTimers();
	});

	it('marks newline explicitly', () => {
		const handlers = createToolStateHandlers(update, getState);
		handlers.markNeedsNewline('msg-1');
		expect(state.messages[0].needsNewline).toBe(true);
	});
});
