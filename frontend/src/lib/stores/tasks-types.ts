import type {
	Task,
	TaskGroup,
	TaskProject,
	TaskSelection,
	TaskSyncConflict
} from '$lib/types/tasks';

export type TaskNewTaskDraft = {
	title: string;
	notes: string;
	dueDate: string;
	selection: TaskSelection;
	listId?: string;
	listName?: string;
	groupId?: string;
	projectId?: string;
};

export type TasksState = {
	selection: TaskSelection;
	tasks: Task[];
	groups: TaskGroup[];
	projects: TaskProject[];
	todayCount: number;
	counts: Record<string, number>;
	syncNotice: string;
	conflictNotice: string;
	pendingConflicts: TaskSyncConflict[];
	isLoading: boolean;
	searchPending: boolean;
	newTaskDraft: TaskNewTaskDraft | null;
	newTaskSaving: boolean;
	newTaskError: string;
	error: string;
};
