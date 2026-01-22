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
};

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
