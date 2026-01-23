import { describe, expect, it, vi, beforeEach } from 'vitest';
import { createDueActions } from '$lib/stores/tasks-due-actions';
import type { Task, TaskSelection } from '$lib/types/tasks';

const createMockTask = (overrides: Partial<Task> = {}): Task => ({
	id: 'task-1',
	title: 'Test Task',
	status: 'open',
	deadline: '2026-01-23',
	notes: null,
	projectId: null,
	areaId: null,
	repeating: false,
	repeatTemplate: false,
	recurrenceRule: null,
	updatedAt: null,
	deletedAt: null,
	...overrides
});

const createMockDeps = () => {
	let state = {
		selection: { type: 'today' } as TaskSelection,
		tasks: [createMockTask()],
		counts: { today: 1, upcoming: 0 },
		todayCount: 1
	};

	return {
		update: vi.fn((updater) => {
			state = updater(state);
		}),
		getState: vi.fn(() => state),
		selectionKey: vi.fn((sel: TaskSelection) => sel.type),
		tasksCacheKey: vi.fn((sel: TaskSelection) => `tasks.tasks.${sel.type}`),
		updateTaskCaches: vi.fn(),
		classifyDueBucket: vi.fn((value: string) => (value === '2026-01-23' ? 'today' : 'upcoming')),
		getCachedData: vi.fn(() => null),
		setCachedData: vi.fn(),
		enqueueTaskOperation: vi.fn().mockResolvedValue({}),
		handleSyncResponse: vi.fn(),
		loadSelection: vi.fn().mockResolvedValue(undefined),
		applyCountsResponse: vi.fn(),
		setSyncNotice: vi.fn(),
		isBrowser: true,
		tasksAPI: {
			counts: vi.fn().mockResolvedValue({ counts: { today: 0, upcoming: 1 } })
		},
		cacheConfig: {
			cacheTtl: 300000,
			cacheVersion: '1',
			countsCacheKey: 'tasks.counts'
		},
		_state: state,
		_getState: () => state,
		_setState: (newState: typeof state) => {
			state = newState;
		}
	};
};

describe('tasks-due-actions', () => {
	let mockDeps: ReturnType<typeof createMockDeps>;
	let actions: ReturnType<typeof createDueActions>;

	beforeEach(() => {
		vi.stubGlobal('navigator', { onLine: true });
		mockDeps = createMockDeps();
		actions = createDueActions(mockDeps);
	});

	describe('setDueDate', () => {
		it('updates task with new due date optimistically', async () => {
			await actions.setDueDate('task-1', '2026-01-25');

			expect(mockDeps.updateTaskCaches).toHaveBeenCalledWith(
				expect.objectContaining({
					taskId: 'task-1',
					task: expect.objectContaining({ deadline: '2026-01-25' }),
					targetBucket: 'upcoming'
				})
			);
		});

		it('enqueues defer operation', async () => {
			await actions.setDueDate('task-1', '2026-01-25');

			expect(mockDeps.enqueueTaskOperation).toHaveBeenCalledWith({
				op: 'defer',
				id: 'task-1',
				due_date: '2026-01-25'
			});
		});

		it('uses provided operation type', async () => {
			await actions.setDueDate('task-1', '2026-01-25', 'defer');

			expect(mockDeps.enqueueTaskOperation).toHaveBeenCalledWith(
				expect.objectContaining({ op: 'defer' })
			);
		});

		it('handles sync response', async () => {
			const response = { task: { id: 'task-1' } };
			mockDeps.enqueueTaskOperation.mockResolvedValue(response);

			await actions.setDueDate('task-1', '2026-01-25');

			expect(mockDeps.handleSyncResponse).toHaveBeenCalledWith(response);
		});

		it('refreshes task lists when online', async () => {
			await actions.setDueDate('task-1', '2026-01-25');

			expect(mockDeps.loadSelection).toHaveBeenCalled();
		});

		it('sets sync notice when offline', async () => {
			vi.stubGlobal('navigator', { onLine: false });

			await actions.setDueDate('task-1', '2026-01-25');

			expect(mockDeps.setSyncNotice).toHaveBeenCalledWith('Task updated offline');
		});

		it('handles errors', async () => {
			mockDeps.enqueueTaskOperation.mockRejectedValue(new Error('Network error'));

			await actions.setDueDate('task-1', '2026-01-25');

			expect(mockDeps.update).toHaveBeenLastCalledWith(expect.any(Function));
			const lastCall = mockDeps.update.mock.calls[mockDeps.update.mock.calls.length - 1];
			const result = lastCall[0]({
				selection: { type: 'today' },
				tasks: [],
				counts: {},
				todayCount: 0
			});
			expect(result.error).toBe('Network error');
		});

		it('does nothing for non-existent task', async () => {
			mockDeps._setState({
				...mockDeps._getState(),
				tasks: []
			});

			await actions.setDueDate('task-999', '2026-01-25');

			expect(mockDeps.updateTaskCaches).not.toHaveBeenCalled();
		});
	});

	describe('clearDueDate', () => {
		it('clears task deadline optimistically', async () => {
			await actions.clearDueDate('task-1');

			expect(mockDeps.update).toHaveBeenCalled();
		});

		it('removes task from today/upcoming lists', async () => {
			mockDeps._setState({
				...mockDeps._getState(),
				selection: { type: 'today' },
				tasks: [createMockTask()],
				counts: { today: 1 }
			});

			await actions.clearDueDate('task-1');

			const updateCall = mockDeps.update.mock.calls[0];
			const result = updateCall[0](mockDeps._getState());
			expect(result.tasks).toHaveLength(0);
		});

		it('enqueues clear_due operation', async () => {
			await actions.clearDueDate('task-1');

			expect(mockDeps.enqueueTaskOperation).toHaveBeenCalledWith({
				op: 'clear_due',
				id: 'task-1'
			});
		});

		it('updates counts after clearing', async () => {
			mockDeps._setState({
				...mockDeps._getState(),
				selection: { type: 'today' },
				tasks: [createMockTask()],
				counts: { today: 1 },
				todayCount: 1
			});

			await actions.clearDueDate('task-1');

			const updateCall = mockDeps.update.mock.calls[0];
			const result = updateCall[0](mockDeps._getState());
			expect(result.todayCount).toBe(0);
		});

		it('sets sync notice when offline', async () => {
			vi.stubGlobal('navigator', { onLine: false });

			await actions.clearDueDate('task-1');

			expect(mockDeps.setSyncNotice).toHaveBeenCalledWith('Task updated offline');
		});

		it('handles errors', async () => {
			mockDeps.enqueueTaskOperation.mockRejectedValue(new Error('Failed'));

			await actions.clearDueDate('task-1');

			const lastCall = mockDeps.update.mock.calls[mockDeps.update.mock.calls.length - 1];
			const result = lastCall[0]({
				selection: { type: 'today' },
				tasks: [],
				counts: {},
				todayCount: 0
			});
			expect(result.error).toBe('Failed');
		});
	});

	describe('setRepeat', () => {
		it('updates task with recurrence rule', async () => {
			const rule = { type: 'daily' as const, interval: 1 };

			await actions.setRepeat('task-1', rule, '2026-01-23');

			expect(mockDeps.updateTaskCaches).toHaveBeenCalledWith(
				expect.objectContaining({
					taskId: 'task-1',
					task: expect.objectContaining({
						repeating: true,
						recurrenceRule: rule
					})
				})
			);
		});

		it('enqueues set_repeat operation', async () => {
			const rule = { type: 'weekly' as const, interval: 1, weekday: 1 };

			await actions.setRepeat('task-1', rule, '2026-01-23');

			expect(mockDeps.enqueueTaskOperation).toHaveBeenCalledWith({
				op: 'set_repeat',
				id: 'task-1',
				recurrence_rule: rule,
				start_date: '2026-01-23'
			});
		});

		it('clears recurrence with null rule', async () => {
			mockDeps._setState({
				...mockDeps._getState(),
				tasks: [createMockTask({ repeating: true, recurrenceRule: { type: 'daily', interval: 1 } })]
			});

			await actions.setRepeat('task-1', null, null);

			expect(mockDeps.enqueueTaskOperation).toHaveBeenCalledWith({
				op: 'set_repeat',
				id: 'task-1',
				recurrence_rule: null,
				start_date: '2026-01-23'
			});
		});

		it('uses existing deadline when startDate is null', async () => {
			mockDeps._setState({
				...mockDeps._getState(),
				tasks: [createMockTask({ deadline: '2026-02-01' })]
			});

			await actions.setRepeat('task-1', { type: 'daily', interval: 1 }, null);

			expect(mockDeps.enqueueTaskOperation).toHaveBeenCalledWith(
				expect.objectContaining({
					start_date: '2026-02-01'
				})
			);
		});

		it('updates cache without targetBucket when no due date', async () => {
			mockDeps._setState({
				...mockDeps._getState(),
				tasks: [createMockTask({ deadline: null })]
			});

			await actions.setRepeat('task-1', { type: 'daily', interval: 1 }, null);

			expect(mockDeps.updateTaskCaches).not.toHaveBeenCalled();
			expect(mockDeps.update).toHaveBeenCalled();
		});

		it('sets sync notice when offline', async () => {
			vi.stubGlobal('navigator', { onLine: false });

			await actions.setRepeat('task-1', { type: 'daily', interval: 1 }, '2026-01-23');

			expect(mockDeps.setSyncNotice).toHaveBeenCalledWith('Task updated offline');
		});

		it('handles errors', async () => {
			mockDeps.enqueueTaskOperation.mockRejectedValue(new Error('Repeat failed'));

			await actions.setRepeat('task-1', { type: 'daily', interval: 1 }, '2026-01-23');

			const lastCall = mockDeps.update.mock.calls[mockDeps.update.mock.calls.length - 1];
			const result = lastCall[0]({
				selection: { type: 'today' },
				tasks: [],
				counts: {},
				todayCount: 0
			});
			expect(result.error).toBe('Repeat failed');
		});
	});

	describe('refreshTaskLists (internal)', () => {
		it('reloads current selection and both today/upcoming', async () => {
			mockDeps._setState({
				...mockDeps._getState(),
				selection: { type: 'area', areaId: 'area-1' }
			});

			await actions.setDueDate('task-1', '2026-01-25');

			expect(mockDeps.loadSelection).toHaveBeenCalledWith(
				{ type: 'area', areaId: 'area-1' },
				expect.objectContaining({ force: true })
			);
			expect(mockDeps.loadSelection).toHaveBeenCalledWith(
				{ type: 'today' },
				expect.objectContaining({ force: true })
			);
			expect(mockDeps.loadSelection).toHaveBeenCalledWith(
				{ type: 'upcoming' },
				expect.objectContaining({ force: true })
			);
		});

		it('skips today reload when already viewing today', async () => {
			mockDeps._setState({
				...mockDeps._getState(),
				selection: { type: 'today' }
			});

			await actions.setDueDate('task-1', '2026-01-25');

			const todayCalls = mockDeps.loadSelection.mock.calls.filter(
				(call) => call[0].type === 'today'
			);
			expect(todayCalls).toHaveLength(1);
		});

		it('updates counts after refresh', async () => {
			await actions.setDueDate('task-1', '2026-01-25');

			expect(mockDeps.tasksAPI.counts).toHaveBeenCalled();
		});

		it('handles count refresh errors', async () => {
			mockDeps.tasksAPI.counts.mockRejectedValue(new Error('Count failed'));

			await actions.setDueDate('task-1', '2026-01-25');

			// Wait for async refresh to complete
			await new Promise((resolve) => setTimeout(resolve, 0));

			const lastCall = mockDeps.update.mock.calls[mockDeps.update.mock.calls.length - 1];
			const result = lastCall[0]({
				selection: { type: 'today' },
				tasks: [],
				counts: {},
				todayCount: 0
			});
			expect(result.error).toBe('Failed to update task counts');
		});
	});
});
