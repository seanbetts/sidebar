import { describe, expect, it, vi } from 'vitest';
import {
	selectionKey,
	tasksCacheKey,
	selectionCount,
	isSameSelection,
	normalizeCountsCache,
	buildCountsMap,
	filterTasksForSelection
} from '$lib/stores/tasks-cache-helpers';
import type { Task, TaskProject, TaskSelection, TaskCountsResponse } from '$lib/types/tasks';

const createTask = (overrides: Partial<Task> = {}): Task => ({
	id: 'task-1',
	title: 'Test Task',
	status: 'open',
	deadline: null,
	notes: null,
	projectId: null,
	areaId: null,
	repeating: false,
	repeatTemplate: false,
	updatedAt: null,
	deletedAt: null,
	...overrides
});

const createProject = (overrides: Partial<TaskProject> = {}): TaskProject => ({
	id: 'proj-1',
	title: 'Test Project',
	areaId: null,
	...overrides
});

describe('tasks-cache-helpers', () => {
	describe('selectionKey', () => {
		it('returns type for simple selections', () => {
			expect(selectionKey({ type: 'today' })).toBe('today');
			expect(selectionKey({ type: 'upcoming' })).toBe('upcoming');
			expect(selectionKey({ type: 'inbox' })).toBe('inbox');
		});

		it('includes id for area selection', () => {
			expect(selectionKey({ type: 'area', id: 'area-123' })).toBe('area:area-123');
		});

		it('includes id for project selection', () => {
			expect(selectionKey({ type: 'project', id: 'proj-456' })).toBe('project:proj-456');
		});

		it('includes lowercased query for search selection', () => {
			expect(selectionKey({ type: 'search', query: 'My Search' })).toBe('search:my search');
		});
	});

	describe('tasksCacheKey', () => {
		it('prefixes selection key with tasks.tasks', () => {
			expect(tasksCacheKey({ type: 'today' })).toBe('tasks.tasks.today');
			expect(tasksCacheKey({ type: 'area', id: 'a1' })).toBe('tasks.tasks.area:a1');
		});
	});

	describe('selectionCount', () => {
		it('returns task count for non-area selections', () => {
			const tasks = [createTask(), createTask({ id: 'task-2' })];
			expect(selectionCount({ type: 'today' }, tasks, [])).toBe(2);
		});

		it('excludes project tasks from area count', () => {
			const tasks = [
				createTask({ id: 'task-1', status: 'open' }),
				createTask({ id: 'proj-1', status: 'project' })
			];
			const projects = [createProject({ id: 'proj-1' })];

			expect(selectionCount({ type: 'area', id: 'area-1' }, tasks, projects)).toBe(1);
		});
	});

	describe('isSameSelection', () => {
		it('returns true for same simple types', () => {
			expect(isSameSelection({ type: 'today' }, { type: 'today' })).toBe(true);
			expect(isSameSelection({ type: 'inbox' }, { type: 'inbox' })).toBe(true);
		});

		it('returns false for different types', () => {
			expect(isSameSelection({ type: 'today' }, { type: 'upcoming' })).toBe(false);
		});

		it('compares ids for area selections', () => {
			expect(isSameSelection({ type: 'area', id: 'a1' }, { type: 'area', id: 'a1' })).toBe(true);
			expect(isSameSelection({ type: 'area', id: 'a1' }, { type: 'area', id: 'a2' })).toBe(false);
		});

		it('compares ids for project selections', () => {
			expect(isSameSelection({ type: 'project', id: 'p1' }, { type: 'project', id: 'p1' })).toBe(
				true
			);
			expect(isSameSelection({ type: 'project', id: 'p1' }, { type: 'project', id: 'p2' })).toBe(
				false
			);
		});

		it('compares queries for search selections', () => {
			expect(
				isSameSelection({ type: 'search', query: 'foo' }, { type: 'search', query: 'foo' })
			).toBe(true);
			expect(
				isSameSelection({ type: 'search', query: 'foo' }, { type: 'search', query: 'bar' })
			).toBe(false);
		});
	});

	describe('normalizeCountsCache', () => {
		it('normalizes TaskCountsResponse format', () => {
			const response: TaskCountsResponse = {
				counts: { inbox: 5, today: 10, upcoming: 15 },
				areas: [{ id: 'a1', title: 'Area', count: 3 }],
				projects: [{ id: 'p1', title: 'Project', areaId: null, count: 7 }]
			};

			const result = normalizeCountsCache(response);

			expect(result.todayCount).toBe(10);
			expect(result.map.inbox).toBe(5);
			expect(result.map.today).toBe(10);
			expect(result.map['area:a1']).toBe(3);
			expect(result.map['project:p1']).toBe(7);
		});

		it('normalizes legacy flat map format', () => {
			const legacy = { inbox: 2, today: 4, upcoming: 6 };

			const result = normalizeCountsCache(legacy);

			expect(result.todayCount).toBe(4);
			expect(result.map).toEqual(legacy);
		});

		it('uses inbox count as fallback for todayCount', () => {
			const legacy = { inbox: 8 };

			const result = normalizeCountsCache(legacy);

			expect(result.todayCount).toBe(8);
		});
	});

	describe('buildCountsMap', () => {
		it('builds map from counts response', () => {
			const response: TaskCountsResponse = {
				counts: { inbox: 1, today: 2, upcoming: 3 },
				areas: [
					{ id: 'a1', title: 'Area 1', count: 10 },
					{ id: 'a2', title: 'Area 2', count: 20 }
				],
				projects: [{ id: 'p1', title: 'Project 1', areaId: 'a1', count: 5 }]
			};

			const map = buildCountsMap(response);

			expect(map).toEqual({
				inbox: 1,
				today: 2,
				upcoming: 3,
				'area:a1': 10,
				'area:a2': 20,
				'project:p1': 5
			});
		});

		it('handles empty areas and projects', () => {
			const response: TaskCountsResponse = {
				counts: { inbox: 0, today: 0, upcoming: 0 },
				areas: [],
				projects: []
			};

			const map = buildCountsMap(response);

			expect(map).toEqual({ inbox: 0, today: 0, upcoming: 0 });
		});
	});

	describe('filterTasksForSelection', () => {
		const baseTasks = [
			createTask({ id: 't1', status: 'inbox', areaId: null, projectId: null }),
			createTask({ id: 't2', status: 'open', areaId: 'a1', deadline: '2026-01-23' }),
			createTask({ id: 't3', status: 'open', projectId: 'p1', deadline: '2026-01-25' }),
			createTask({ id: 't4', status: 'someday', deadline: null }),
			createTask({ id: 't5', status: 'completed' }),
			createTask({ id: 't6', status: 'trashed' }),
			createTask({ id: 't7', deletedAt: '2026-01-01' })
		];

		it('filters out deleted, completed, and trashed tasks', () => {
			const result = filterTasksForSelection(baseTasks, { type: 'inbox' });

			const ids = result.map((t) => t.id);
			expect(ids).not.toContain('t5');
			expect(ids).not.toContain('t6');
			expect(ids).not.toContain('t7');
		});

		it('filters inbox tasks', () => {
			const result = filterTasksForSelection(baseTasks, { type: 'inbox' });

			expect(result.map((t) => t.id)).toEqual(['t1']);
		});

		it('filters tasks by area including project tasks', () => {
			const projects = [createProject({ id: 'p1', areaId: 'a1' })];
			const result = filterTasksForSelection(baseTasks, { type: 'area', id: 'a1' }, projects);

			const ids = result.map((t) => t.id);
			expect(ids).toContain('t2');
			expect(ids).toContain('t3');
		});

		it('filters tasks by project', () => {
			const result = filterTasksForSelection(baseTasks, { type: 'project', id: 'p1' });

			expect(result.map((t) => t.id)).toEqual(['t3']);
		});

		it('filters by search query in title and notes', () => {
			const tasks = [
				createTask({ id: 't1', title: 'Buy groceries' }),
				createTask({ id: 't2', title: 'Meeting', notes: 'Discuss groceries budget' }),
				createTask({ id: 't3', title: 'Other task' })
			];

			const result = filterTasksForSelection(tasks, { type: 'search', query: 'groceries' });

			expect(result.map((t) => t.id)).toEqual(['t1', 't2']);
		});

		it('returns all non-deleted tasks for empty search', () => {
			const tasks = [createTask({ id: 't1' }), createTask({ id: 't2' })];

			const result = filterTasksForSelection(tasks, { type: 'search', query: '   ' });

			expect(result).toHaveLength(2);
		});

		it('filters today tasks by due date', () => {
			vi.useFakeTimers();
			vi.setSystemTime(new Date('2026-01-23T12:00:00'));

			const tasks = [
				createTask({ id: 't1', deadline: '2026-01-23' }),
				createTask({ id: 't2', deadline: '2026-01-22' }), // Past, still shows in today
				createTask({ id: 't3', deadline: '2026-01-24' }), // Future
				createTask({ id: 't4', deadline: null }),
				createTask({ id: 't5', status: 'someday', deadline: '2026-01-23' })
			];

			const result = filterTasksForSelection(tasks, { type: 'today' });

			expect(result.map((t) => t.id)).toEqual(['t1', 't2']);

			vi.useRealTimers();
		});

		it('filters upcoming tasks by future due date', () => {
			vi.useFakeTimers();
			vi.setSystemTime(new Date('2026-01-23T12:00:00'));

			const tasks = [
				createTask({ id: 't1', deadline: '2026-01-23' }), // Today
				createTask({ id: 't2', deadline: '2026-01-24' }), // Tomorrow
				createTask({ id: 't3', deadline: '2026-02-01' }), // Future
				createTask({ id: 't4', deadline: null }),
				createTask({ id: 't5', status: 'someday', deadline: '2026-01-25' })
			];

			const result = filterTasksForSelection(tasks, { type: 'upcoming' });

			expect(result.map((t) => t.id)).toEqual(['t2', 't3']);

			vi.useRealTimers();
		});
	});
});
