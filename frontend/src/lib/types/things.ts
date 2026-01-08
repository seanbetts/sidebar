export type ThingsBridgeInfo = {
	bridgeId: string;
	deviceId: string;
	deviceName: string;
	baseUrl: string;
	capabilities?: Record<string, boolean>;
	lastSeenAt: string | null;
	updatedAt: string | null;
};

export type ThingsBridgeStatus = {
	activeBridgeId: string | null;
	activeBridge: ThingsBridgeInfo | null;
	bridges: ThingsBridgeInfo[];
};

export type ThingsTask = {
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

export type ThingsProject = {
	id: string;
	title: string;
	areaId?: string | null;
	status: string;
	updatedAt?: string | null;
};

export type ThingsArea = {
	id: string;
	title: string;
	updatedAt?: string | null;
};

export type ThingsListResponse = {
	scope: string;
	generatedAt?: string;
	tasks: ThingsTask[];
	projects?: ThingsProject[];
	areas?: ThingsArea[];
};

export type ThingsCountsResponse = {
	generatedAt?: string;
	counts: {
		inbox: number;
		today: number;
		upcoming: number;
	};
	projects: Array<{ id: string; count: number }>;
	areas: Array<{ id: string; count: number }>;
};

export type ThingsBridgeDiagnostics = {
	dbAccess: boolean;
	dbPath: string | null;
	dbError: string | null;
};
