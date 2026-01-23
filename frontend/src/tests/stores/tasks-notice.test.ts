import { describe, expect, it, vi, beforeEach, afterEach } from 'vitest';
import { createNotice } from '$lib/stores/tasks-notice';

describe('tasks-notice', () => {
	beforeEach(() => {
		vi.useFakeTimers();
	});

	afterEach(() => {
		vi.useRealTimers();
	});

	describe('createNotice', () => {
		it('sets notice message via update function', () => {
			const updates: string[] = [];
			const updateState = vi.fn((updater) => {
				const result = updater({ syncNotice: '' });
				updates.push(result.syncNotice);
			});

			const setNotice = createNotice('syncNotice', updateState);
			setNotice('Task synced');

			expect(updateState).toHaveBeenCalledTimes(1);
			expect(updates).toContain('Task synced');
		});

		it('auto-clears notice after default timeout', () => {
			const updates: string[] = [];
			const updateState = vi.fn((updater) => {
				const result = updater({ syncNotice: '' });
				updates.push(result.syncNotice);
			});

			const setNotice = createNotice('syncNotice', updateState);
			setNotice('Temporary message');

			expect(updates).toEqual(['Temporary message']);

			vi.advanceTimersByTime(6000);

			expect(updates).toEqual(['Temporary message', '']);
		});

		it('uses custom clear timeout', () => {
			const updates: string[] = [];
			const updateState = vi.fn((updater) => {
				const result = updater({ syncNotice: '' });
				updates.push(result.syncNotice);
			});

			const setNotice = createNotice('syncNotice', updateState, 1000);
			setNotice('Quick message');

			vi.advanceTimersByTime(500);
			expect(updates).toEqual(['Quick message']);

			vi.advanceTimersByTime(500);
			expect(updates).toEqual(['Quick message', '']);
		});

		it('cancels previous timer when setting new notice', () => {
			const updates: string[] = [];
			const updateState = vi.fn((updater) => {
				const result = updater({ syncNotice: '' });
				updates.push(result.syncNotice);
			});

			const setNotice = createNotice('syncNotice', updateState, 1000);
			setNotice('First');

			vi.advanceTimersByTime(500);
			setNotice('Second');

			vi.advanceTimersByTime(500);
			// First timer would have cleared by now if not cancelled
			expect(updates).toEqual(['First', 'Second']);

			vi.advanceTimersByTime(500);
			// Second timer clears
			expect(updates).toEqual(['First', 'Second', '']);
		});

		it('does not auto-clear when clearMs is null', () => {
			const updates: string[] = [];
			const updateState = vi.fn((updater) => {
				const result = updater({ conflictNotice: '' });
				updates.push(result.conflictNotice);
			});

			const setNotice = createNotice('conflictNotice', updateState, null);
			setNotice('Persistent notice');

			vi.advanceTimersByTime(60000);

			expect(updates).toEqual(['Persistent notice']);
		});

		it('works with conflictNotice field', () => {
			const updates: string[] = [];
			const updateState = vi.fn((updater) => {
				const result = updater({ conflictNotice: '' });
				updates.push(result.conflictNotice);
			});

			const setNotice = createNotice('conflictNotice', updateState);
			setNotice('Conflict detected');

			expect(updates).toContain('Conflict detected');
		});
	});
});
