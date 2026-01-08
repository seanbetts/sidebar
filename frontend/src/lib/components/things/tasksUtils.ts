import type { ThingsArea, ThingsProject, ThingsTask } from '$lib/types/things';

export type TaskSection = {
	id: string;
	title: string;
	tasks: ThingsTask[];
};

const MS_PER_DAY = 24 * 60 * 60 * 1000;

const startOfDay = (date: Date) => {
	const next = new Date(date);
	next.setHours(0, 0, 0, 0);
	return next;
};

const formatDateKey = (date: Date): string => {
	const year = date.getFullYear();
	const month = String(date.getMonth() + 1).padStart(2, '0');
	const day = String(date.getDate()).padStart(2, '0');
	return `${year}-${month}-${day}`;
};

const formatDayLabel = (date: Date, dayDiff: number): string => {
	if (dayDiff === 0) return 'Today';
	if (dayDiff === 1) return 'Tomorrow';
	return date.toLocaleDateString(undefined, { weekday: 'long', month: 'short', day: 'numeric' });
};

const formatWeekLabel = (date: Date): string => {
	const label = date.toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
	return `Week of ${label}`;
};

const formatMonthLabel = (date: Date): string =>
	date.toLocaleDateString(undefined, { month: 'long', year: 'numeric' });

const addDays = (date: Date, days: number): Date => {
	const next = new Date(date);
	next.setDate(next.getDate() + days);
	return next;
};

export const nextWeekday = (date: Date, targetDay: number): Date => {
	const currentDay = date.getDay();
	let daysAhead = (targetDay - currentDay + 7) % 7;
	if (daysAhead === 0) {
		daysAhead = 7;
	}
	return addDays(date, daysAhead);
};

const taskDeadline = (task: ThingsTask): string | null =>
	task.deadline ?? task.deadlineStart ?? null;

const parseTaskDate = (task: ThingsTask): Date | null => {
	const deadline = taskDeadline(task);
	if (!deadline) return null;
	return new Date(`${deadline.slice(0, 10)}T00:00:00`);
};

export const buildTodaySections = (
	tasks: ThingsTask[],
	areas: ThingsArea[],
	projects: ThingsProject[],
	areaTitleById: Map<string, string>,
	projectTitleById: Map<string, string>
): TaskSection[] => {
	const sections: TaskSection[] = [];
	const buckets = new Map<string, { title: string; tasks: ThingsTask[] }>();

	areas.forEach((area) => {
		buckets.set(`area:${area.id}`, { title: area.title, tasks: [] });
	});

	tasks.forEach((task) => {
		const project = task.projectId ? projects.find((item) => item.id === task.projectId) : null;
		const areaId = task.areaId ?? project?.areaId ?? null;
		if (areaId) {
			const key = `area:${areaId}`;
			if (!buckets.has(key)) {
				const title = areaTitleById.get(areaId) ?? 'Area';
				buckets.set(key, { title, tasks: [] });
			}
			buckets.get(key)?.tasks.push(task);
			return;
		}
		if (task.projectId) {
			const key = `project:${task.projectId}`;
			if (!buckets.has(key)) {
				buckets.set(key, {
					title: projectTitleById.get(task.projectId) ?? 'Project',
					tasks: []
				});
			}
			buckets.get(key)?.tasks.push(task);
			return;
		}
		if (!buckets.has('other')) {
			buckets.set('other', { title: 'Other', tasks: [] });
		}
		buckets.get('other')?.tasks.push(task);
	});

	areas.forEach((area) => {
		const bucket = buckets.get(`area:${area.id}`);
		if (bucket?.tasks.length) {
			sections.push({ id: area.id, title: bucket.title, tasks: bucket.tasks });
		}
	});

	buckets.forEach((bucket, key) => {
		if (key.startsWith('project:') && bucket.tasks.length) {
			sections.push({ id: key, title: bucket.title, tasks: bucket.tasks });
		}
	});

	const other = buckets.get('other');
	if (other?.tasks.length) {
		sections.push({ id: 'other', title: other.title, tasks: other.tasks });
	}

	return sections;
};

export const buildSearchSections = (tasks: ThingsTask[], areas: ThingsArea[]): TaskSection[] => {
	const sections: TaskSection[] = [];
	const tasksByArea = new Map<string, ThingsTask[]>();
	const unassigned: ThingsTask[] = [];

	areas.forEach((area) => tasksByArea.set(area.id, []));
	tasks.forEach((task) => {
		if (task.areaId && tasksByArea.has(task.areaId)) {
			tasksByArea.get(task.areaId)?.push(task);
		} else {
			unassigned.push(task);
		}
	});

	areas.forEach((area) => {
		const bucket = tasksByArea.get(area.id) ?? [];
		if (bucket.length) {
			sections.push({ id: area.id, title: area.title, tasks: sortByDueDate(bucket) });
		}
	});

	if (unassigned.length) {
		sections.push({ id: 'other', title: 'Other', tasks: sortByDueDate(unassigned) });
	}

	return sections;
};

export const buildUpcomingSections = (tasks: ThingsTask[]): TaskSection[] => {
	const today = startOfDay(new Date());
	const overdue: ThingsTask[] = [];
	const undated: ThingsTask[] = [];
	const daily = new Map<string, TaskSection>();
	const weekly = new Map<number, TaskSection>();
	const monthly = new Map<string, { date: Date; section: TaskSection }>();

	const sorted = [...tasks].sort((a, b) => {
		const dateA = parseTaskDate(a);
		const dateB = parseTaskDate(b);
		if (!dateA && !dateB) return 0;
		if (!dateA) return 1;
		if (!dateB) return -1;
		return dateA.getTime() - dateB.getTime();
	});

	sorted.forEach((task) => {
		const date = parseTaskDate(task);
		if (!date) {
			undated.push(task);
			return;
		}
		const dayDiff = Math.floor((startOfDay(date).getTime() - today.getTime()) / MS_PER_DAY);
		if (dayDiff < 0) {
			overdue.push(task);
			return;
		}
		if (dayDiff <= 6) {
			const key = formatDateKey(date);
			const label = formatDayLabel(date, dayDiff);
			const section = daily.get(key) ?? { id: key, title: label, tasks: [] };
			section.tasks.push(task);
			daily.set(key, section);
			return;
		}
		if (dayDiff <= 27) {
			const weekIndex = Math.floor(dayDiff / 7);
			const weekStart = addDays(today, weekIndex * 7);
			const label = formatWeekLabel(weekStart);
			const section = weekly.get(weekIndex) ?? { id: `week-${weekIndex}`, title: label, tasks: [] };
			section.tasks.push(task);
			weekly.set(weekIndex, section);
			return;
		}
		const monthKey = `${date.getFullYear()}-${date.getMonth()}`;
		const existing = monthly.get(monthKey);
		if (existing) {
			existing.section.tasks.push(task);
		} else {
			monthly.set(monthKey, {
				date,
				section: { id: `month-${monthKey}`, title: formatMonthLabel(date), tasks: [task] }
			});
		}
	});

	const sections: TaskSection[] = [];

	if (overdue.length) {
		sections.push({ id: 'overdue', title: 'Overdue', tasks: overdue });
	}

	for (let i = 0; i <= 6; i += 1) {
		const date = addDays(today, i);
		const key = formatDateKey(date);
		const section = daily.get(key);
		if (section) sections.push(section);
	}

	for (let weekIndex = 1; weekIndex <= 3; weekIndex += 1) {
		const section = weekly.get(weekIndex);
		if (section) sections.push(section);
	}

	const monthSections = [...monthly.values()].sort((a, b) => a.date.getTime() - b.date.getTime());
	monthSections.forEach((entry) => sections.push(entry.section));

	if (undated.length) {
		sections.push({ id: 'undated', title: 'No date', tasks: undated });
	}

	return sections;
};

export const sortByDueDate = (tasks: ThingsTask[]): ThingsTask[] => {
	return [...tasks].sort((a, b) => {
		const dateA = parseTaskDate(a);
		const dateB = parseTaskDate(b);
		if (!dateA && !dateB) return 0;
		if (!dateA) return 1;
		if (!dateB) return -1;
		return dateA.getTime() - dateB.getTime();
	});
};

export const taskSubtitle = (
	task: ThingsTask,
	selectionType: 'inbox' | 'today' | 'upcoming' | 'area' | 'project' | 'search',
	selectionLabel: string,
	projectTitleById: Map<string, string>,
	areaTitleById: Map<string, string>
): string => {
	const projectTitle = task.projectId ? projectTitleById.get(task.projectId) : '';
	const areaTitle = task.areaId ? areaTitleById.get(task.areaId) : '';
	if (selectionType === 'project') {
		return projectTitle || selectionLabel;
	}
	if (selectionType === 'area') {
		return projectTitle || areaTitle || '';
	}
	if (selectionType === 'today' || selectionType === 'upcoming') {
		return projectTitle || areaTitle || '';
	}
	if (selectionType === 'search') {
		return projectTitle || areaTitle || '';
	}
	if (taskDeadline(task)) {
		return `Due ${taskDeadline(task)?.slice(0, 10)}`;
	}
	return projectTitle || areaTitle || '';
};

export const dueLabel = (task: ThingsTask): string | null => {
	const date = parseTaskDate(task);
	if (!date) return null;
	const today = startOfDay(new Date());
	const dayDiff = Math.floor((startOfDay(date).getTime() - today.getTime()) / MS_PER_DAY);
	if (dayDiff === 0) {
		return 'Today';
	}
	if (dayDiff === 1) {
		return 'Tomorrow';
	}
	if (dayDiff > 1 && dayDiff <= 6) {
		return date.toLocaleDateString(undefined, { weekday: 'short' });
	}
	return date.toLocaleDateString(undefined, { day: 'numeric', month: 'short' });
};

export const getTaskDueDate = (task: ThingsTask) => taskDeadline(task);

export const formatDateKeyForToday = () => formatDateKey(new Date());

export const formatDateKeyWithOffset = (days: number) => formatDateKey(addDays(new Date(), days));

export const formatDateKeyForDate = (date: Date) => formatDateKey(date);
