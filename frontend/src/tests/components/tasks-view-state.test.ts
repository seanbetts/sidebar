import { describe, expect, it } from 'vitest';

import { computeTasksViewState } from '$lib/components/tasks/TasksViewState';
import type { TasksState } from '$lib/stores/tasks';
import type { Task } from '$lib/types/tasks';

const baseState = (overrides: Partial<TasksState> = {}): TasksState => ({
	selection: { type: 'today' },
	tasks: [],
	groups: [],
	projects: [],
	todayCount: 0,
	counts: {},
	syncNotice: '',
	conflictNotice: '',
	isLoading: false,
	searchPending: false,
	newTaskDraft: null,
	newTaskSaving: false,
	newTaskError: '',
	error: '',
	...overrides
});

describe('computeTasksViewState', () => {
	it('does not add repeat previews in today view', () => {
		const task: Task = {
			id: 'task-1',
			title: 'Daily standup',
			status: 'open',
			deadline: '2025-01-01',
			notes: '',
			projectId: null,
			groupId: null,
			repeating: true,
			repeatTemplate: false,
			recurrenceRule: { type: 'daily', interval: 1 },
			nextInstanceDate: '2025-01-02'
		};
		const state = baseState({ tasks: [task] });
		const viewState = computeTasksViewState(state);
		const allTasks = viewState.sections.flatMap((section) => section.tasks);

		expect(allTasks).toHaveLength(1);
		expect(allTasks[0].id).toBe('task-1');
		expect(allTasks[0].isPreview).toBeUndefined();
	});
});
