export type Task = {
	id: string;
	title: string;
	status: string;
	deadline?: string | null;
	deadlineStart?: string | null;
	notes?: string | null;
	projectId?: string | null;
	areaId?: string | null;
	repeating?: boolean;
	repeatTemplate?: boolean;
	tags?: string[];
	updatedAt?: string | null;
	deletedAt?: string | null;
};

export type TaskSelection =
	| { type: 'inbox' }
	| { type: 'today' }
	| { type: 'upcoming' }
	| { type: 'area'; id: string }
	| { type: 'project'; id: string }
	| { type: 'search'; query: string };

export type TaskProject = {
	id: string;
	title: string;
	areaId?: string | null;
	status: string;
	updatedAt?: string | null;
};

export type TaskArea = {
	id: string;
	title: string;
	updatedAt?: string | null;
};

export type TaskListResponse = {
	scope: string;
	generatedAt?: string;
	tasks: Task[];
	projects?: TaskProject[];
	areas?: TaskArea[];
};

export type TaskCountsResponse = {
	generatedAt?: string;
	counts: {
		inbox: number;
		today: number;
		upcoming: number;
	};
	projects: Array<{ id: string; count: number }>;
	areas: Array<{ id: string; count: number }>;
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
	areas: TaskArea[];
};

export type TaskSyncResponse = {
	applied: string[];
	tasks: Task[];
	nextTasks: Task[];
	conflicts: TaskSyncConflict[];
	updates: TaskSyncUpdates;
	serverUpdatedSince: string;
};
