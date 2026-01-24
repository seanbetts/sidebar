export type Task = {
	id: string;
	title: string;
	status: string;
	deadline?: string | null;
	notes?: string | null;
	projectId?: string | null;
	groupId?: string | null;
	repeating?: boolean;
	repeatTemplate?: boolean;
	recurrenceRule?: RecurrenceRule | null;
	nextInstanceDate?: string | null;
	isPreview?: boolean;
	updatedAt?: string | null;
	deletedAt?: string | null;
};

export type RecurrenceRule = {
	type: 'daily' | 'weekly' | 'monthly';
	interval?: number;
	weekday?: number;
	day_of_month?: number;
};

export type TaskSelection =
	| { type: 'inbox' }
	| { type: 'today' }
	| { type: 'upcoming' }
	| { type: 'group'; id: string }
	| { type: 'project'; id: string }
	| { type: 'search'; query: string };

export type TaskProject = {
	id: string;
	title: string;
	groupId?: string | null;
	status: string;
	updatedAt?: string | null;
};

export type TaskGroup = {
	id: string;
	title: string;
	updatedAt?: string | null;
};

export type TaskListResponse = {
	scope: string;
	generatedAt?: string;
	tasks: Task[];
	projects?: TaskProject[];
	groups?: TaskGroup[];
};

export type TaskCountsResponse = {
	generatedAt?: string;
	counts: {
		inbox: number;
		today: number;
		upcoming: number;
	};
	projects: Array<{ id: string; count: number }>;
	groups: Array<{ id: string; count: number }>;
};

export type TaskSyncOperation = {
	operation_id: string;
	op: string;
	client_updated_at?: string;
	[key: string]: unknown;
};

export type TaskSyncConflict = {
	operationId: string;
	op?: string | null;
	id: string;
	clientUpdatedAt?: string | null;
	serverUpdatedAt?: string | null;
	serverTask: Task;
};

export type TaskSyncUpdates = {
	tasks: Task[];
	projects: TaskProject[];
	groups: TaskGroup[];
};

export type TaskSyncResponse = {
	applied: string[];
	tasks: Task[];
	nextTasks: Task[];
	conflicts: TaskSyncConflict[];
	updates: TaskSyncUpdates;
	serverUpdatedSince: string;
};
