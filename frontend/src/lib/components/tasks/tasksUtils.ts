import type { Task, TaskArea, TaskProject } from '$lib/types/tasks';

export type TaskSection = {
	id: string;
	title: string;
	tasks: Task[];
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

const taskDeadline = (task: Task): string | null => task.deadline ?? null;
const titleForSort = (task: Task) => (task.title ?? '').toLowerCase();

const compareByDueThenTitle = (a: Task, b: Task) => {
	const dateA = parseTaskDate(a);
	const dateB = parseTaskDate(b);
	if (a.isPreview !== b.isPreview) {
		return a.isPreview ? 1 : -1;
	}
	if (!dateA && !dateB) return titleForSort(a).localeCompare(titleForSort(b));
	if (!dateA) return 1;
	if (!dateB) return -1;
	const diff = dateA.getTime() - dateB.getTime();
	if (diff !== 0) return diff;
	return titleForSort(a).localeCompare(titleForSort(b));
};

const parseTaskDate = (task: Task): Date | null => {
	const deadline = taskDeadline(task);
	if (!deadline) return null;
	return new Date(`${deadline.slice(0, 10)}T00:00:00`);
};

export const recurrenceLabel = (task: Task): string | null => {
	const rule = task.recurrenceRule;
	if (!rule) return null;
	const interval = rule.interval ?? 1;
	if (rule.type === 'daily') {
		return interval === 1 ? 'Daily' : `Every ${interval} days`;
	}
	if (rule.type === 'weekly') {
		const weekdays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
		const dayLabel = rule.weekday !== undefined ? weekdays[rule.weekday] : null;
		if (interval === 1 && dayLabel) return `Weekly on ${dayLabel}`;
		if (dayLabel) return `Every ${interval} weeks on ${dayLabel}`;
		return interval === 1 ? 'Weekly' : `Every ${interval} weeks`;
	}
	if (rule.type === 'monthly') {
		const day = rule.day_of_month ?? null;
		if (day && interval === 1) return `Monthly on day ${day}`;
		if (day) return `Every ${interval} months on day ${day}`;
		return interval === 1 ? 'Monthly' : `Every ${interval} months`;
	}
	return null;
};

export const expandRepeatingTasks = (tasks: Task[]): Task[] => {
	const expanded: Task[] = [];
	tasks.forEach((task) => {
		expanded.push(task);
		if (task.repeating && task.nextInstanceDate) {
			expanded.push({
				...task,
				id: `${task.id}-next`,
				deadline: task.nextInstanceDate,
				repeatTemplate: true,
				isPreview: true
			});
		}
	});
	return expanded;
};

export const buildTodaySections = (
	tasks: Task[],
	areas: TaskArea[],
	projects: TaskProject[],
	areaTitleById: Map<string, string>,
	projectTitleById: Map<string, string>
): TaskSection[] => {
	const sections: TaskSection[] = [];
	const buckets = new Map<string, { title: string; tasks: Task[] }>();

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

export const buildSearchSections = (tasks: Task[], areas: TaskArea[]): TaskSection[] => {
	const sections: TaskSection[] = [];
	const tasksByArea = new Map<string, Task[]>();
	const unassigned: Task[] = [];

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

export const buildAreaSections = (
	tasks: Task[],
	areaId: string,
	areaTitle: string,
	projects: TaskProject[]
): TaskSection[] => {
	const sections: TaskSection[] = [];
	const projectsInArea = projects.filter((project) => project.areaId === areaId);
	const projectById = new Map(projectsInArea.map((project) => [project.id, project]));
	const projectSections = new Map<string, Task[]>();
	const areaTasks: Task[] = [];

	tasks.forEach((task) => {
		if (task.projectId && projectById.has(task.projectId)) {
			const bucket = projectSections.get(task.projectId) ?? [];
			bucket.push(task);
			projectSections.set(task.projectId, bucket);
			return;
		}
		if (task.areaId === areaId || task.projectId == null) {
			areaTasks.push(task);
		}
	});

	if (areaTasks.length) {
		sections.push({ id: 'area', title: areaTitle, tasks: areaTasks });
	}

	projectsInArea
		.sort((a, b) => a.title.localeCompare(b.title))
		.forEach((project) => {
			const bucket = projectSections.get(project.id);
			if (bucket?.length) {
				sections.push({ id: project.id, title: project.title, tasks: bucket });
			}
		});

	return sections;
};

export const buildUpcomingSections = (tasks: Task[]): TaskSection[] => {
	const today = startOfDay(new Date());
	const overdue: Task[] = [];
	const undated: Task[] = [];
	const daily = new Map<string, TaskSection>();
	const weekly = new Map<number, TaskSection>();
	const monthly = new Map<string, { date: Date; section: TaskSection }>();

	const sorted = [...tasks].sort(compareByDueThenTitle);

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

export const sortByDueDate = (tasks: Task[]): Task[] => [...tasks].sort(compareByDueThenTitle);

export const taskSubtitle = (
	task: Task,
	selectionType: 'inbox' | 'today' | 'upcoming' | 'area' | 'project' | 'search',
	selectionLabel: string,
	projectTitleById: Map<string, string>,
	areaTitleById: Map<string, string>
): string => {
	const projectTitle = task.projectId ? projectTitleById.get(task.projectId) : '';
	const areaTitle = task.areaId ? areaTitleById.get(task.areaId) : '';
	let base = '';
	if (selectionType === 'project') {
		base = projectTitle || selectionLabel;
		return base;
	}
	if (selectionType === 'area') {
		base = projectTitle || areaTitle || '';
		return base;
	}
	if (selectionType === 'today' || selectionType === 'upcoming') {
		base = projectTitle || areaTitle || '';
		return base;
	}
	if (selectionType === 'search') {
		base = projectTitle || areaTitle || '';
		return base;
	}
	if (taskDeadline(task)) {
		base = `Due ${taskDeadline(task)?.slice(0, 10)}`;
		return base;
	}
	base = projectTitle || areaTitle || '';
	return base;
};

export const dueLabel = (task: Task): string | null => {
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

export const getTaskDueDate = (task: Task) => taskDeadline(task);

export const formatDateKeyForToday = () => formatDateKey(new Date());

export const formatDateKeyWithOffset = (days: number) => formatDateKey(addDays(new Date(), days));

export const formatDateKeyForDate = (date: Date) => formatDateKey(date);
