import { describe, expect, it } from 'vitest';

import type { Task } from '$lib/types/tasks';
import { recurrenceLabel, taskSubtitle } from '$lib/components/tasks/tasksUtils';

const baseTask = (overrides: Partial<Task> = {}): Task => ({
	id: 'task-1',
	title: 'Task',
	status: 'open',
	deadline: null,
	notes: null,
	projectId: null,
	groupId: null,
	repeating: false,
	repeatTemplate: false,
	updatedAt: null,
	deletedAt: null,
	...overrides
});

describe('tasksUtils recurrenceLabel', () => {
	it('formats daily recurrence', () => {
		const task = baseTask({ recurrenceRule: { type: 'daily', interval: 2 } });
		expect(recurrenceLabel(task)).toBe('Every 2 days');
	});

	it('formats weekly recurrence with weekday', () => {
		const task = baseTask({ recurrenceRule: { type: 'weekly', interval: 1, weekday: 2 } });
		expect(recurrenceLabel(task)).toBe('Weekly on Tue');
	});

	it('formats monthly recurrence with day of month', () => {
		const task = baseTask({ recurrenceRule: { type: 'monthly', interval: 3, day_of_month: 5 } });
		expect(recurrenceLabel(task)).toBe('Every 3 months on day 5');
	});
});

describe('tasksUtils taskSubtitle', () => {
	it('appends recurrence label to project subtitle', () => {
		const task = baseTask({
			projectId: 'project-1',
			recurrenceRule: { type: 'weekly', interval: 1, weekday: 1 }
		});
		const projectTitles = new Map([['project-1', 'Project Alpha']]);
		const groupTitles = new Map<string, string>();

		const subtitle = taskSubtitle(task, 'project', 'Project Alpha', projectTitles, groupTitles);

		expect(subtitle).toBe('Project Alpha');
	});

	it('returns recurrence label when no project or group', () => {
		const task = baseTask({ recurrenceRule: { type: 'daily', interval: 1 } });
		const subtitle = taskSubtitle(task, 'today', 'Today', new Map(), new Map());

		expect(subtitle).toBe('');
	});
});
