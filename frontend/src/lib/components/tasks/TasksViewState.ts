import { CalendarCheck, CalendarClock, Inbox, Layers, List, Search } from 'lucide-svelte';
import type { TaskNewTaskDraft, TaskSelection, TasksState } from '$lib/stores/tasks';
import type { Task, TaskArea, TaskProject } from '$lib/types/tasks';
import {
	buildAreaSections,
	buildSearchSections,
	buildTodaySections,
	buildUpcomingSections,
	expandRepeatingTasks,
	sortByDueDate,
	type TaskSection
} from '$lib/components/tasks/tasksUtils';

export type TaskViewType = 'inbox' | 'today' | 'upcoming' | 'area' | 'project' | 'search';

export type TasksViewState = {
	tasks: Task[];
	selectionLabel: string;
	titleIcon: typeof CalendarCheck;
	selectionQuery: string;
	areas: TaskArea[];
	projects: TaskProject[];
	isLoading: boolean;
	searchPending: boolean;
	error: string;
	sections: TaskSection[];
	totalCount: number;
	hasLoaded: boolean;
	projectTitleById: Map<string, string>;
	areaTitleById: Map<string, string>;
	selectionType: TaskViewType;
	selection: TaskSelection;
	newTaskDraft: TaskNewTaskDraft | null;
	showDraft: boolean;
	areaOptions: TaskArea[];
	projectsByArea: Map<string, TaskProject[]>;
	orphanProjects: TaskProject[];
};

export const isSameSelection = (a: TaskSelection, b: TaskSelection) => {
	if (a.type !== b.type) return false;
	if (a.type === 'area' || a.type === 'project') {
		return a.id === (b as { id: string }).id;
	}
	if (a.type === 'search') {
		return a.query === (b as { query: string }).query;
	}
	return true;
};

export const computeTasksViewState = (state: TasksState): TasksViewState => {
	const { tasks, areas, projects, selection, isLoading, searchPending, error, newTaskDraft } =
		state;
	const selectionType = selection.type as TaskViewType;
	const projectIds = new Set(projects.map((project) => project.id));
	const filteredTasks = tasks.filter((task) => task.status !== 'project');
	const expandedTasks =
		selectionType === 'today' ? filteredTasks : expandRepeatingTasks(filteredTasks);
	const visibleTasks =
		selectionType === 'area' || selectionType === 'search'
			? expandedTasks.filter((task) => !projectIds.has(task.id))
			: expandedTasks;
	const sortedTasks =
		selectionType === 'area' || selectionType === 'project' || selectionType === 'search'
			? sortByDueDate(visibleTasks)
			: visibleTasks;
	const projectTitleById = new Map(projects.map((project) => [project.id, project.title]));
	const areaTitleById = new Map(areas.map((area) => [area.id, area.title]));
	const areaOptions = [...areas].sort((a, b) => a.title.localeCompare(b.title));
	const projectOptions = [...projects].sort((a, b) => a.title.localeCompare(b.title));
	const projectsByArea = new Map<string, TaskProject[]>();
	const orphanProjects: TaskProject[] = [];

	projectOptions.forEach((project) => {
		if (project.areaId) {
			const bucket = projectsByArea.get(project.areaId) ?? [];
			bucket.push(project);
			projectsByArea.set(project.areaId, bucket);
		} else {
			orphanProjects.push(project);
		}
	});

	const selectionQuery = selectionType === 'search' && 'query' in selection ? selection.query : '';
	let selectionLabel = 'Tasks';
	let titleIcon = CalendarCheck;
	let sections: TaskSection[] = [];

	if (selectionType === 'today') {
		selectionLabel = 'Today';
		titleIcon = CalendarCheck;
		sections = buildTodaySections(sortedTasks, areas, projects, areaTitleById, projectTitleById);
	} else if (selectionType === 'upcoming') {
		selectionLabel = 'Upcoming';
		titleIcon = CalendarClock;
		sections = buildUpcomingSections(sortedTasks);
	} else if (selectionType === 'inbox') {
		selectionLabel = 'Inbox';
		titleIcon = Inbox;
		sections = sortedTasks.length ? [{ id: 'all', title: '', tasks: sortedTasks }] : [];
	} else if (selectionType === 'area' && selection.type === 'area') {
		const areaTitle = areas.find((area) => area.id === selection.id)?.title || 'Area';
		selectionLabel = areaTitle;
		titleIcon = Layers;
		sections = buildAreaSections(sortedTasks, selection.id, areaTitle, projects);
	} else if (selectionType === 'project' && selection.type === 'project') {
		selectionLabel = projects.find((project) => project.id === selection.id)?.title || 'Project';
		titleIcon = List;
		sections = sortedTasks.length ? [{ id: 'all', title: '', tasks: sortedTasks }] : [];
	} else if (selectionType === 'search') {
		selectionLabel = selectionQuery ? `Search: ${selectionQuery}` : 'Search';
		titleIcon = Search;
		sections = buildSearchSections(sortedTasks, areas);
	} else {
		sections = sortedTasks.length ? [{ id: 'all', title: '', tasks: sortedTasks }] : [];
	}

	const totalCount = sections.reduce(
		(sum, section) => sum + section.tasks.filter((task) => !task.isPreview).length,
		0
	);
	const hasLoaded = !isLoading;
	const showDraft = Boolean(newTaskDraft && isSameSelection(selection, newTaskDraft.selection));

	return {
		tasks,
		selectionLabel,
		titleIcon,
		selectionQuery,
		areas,
		projects,
		isLoading,
		searchPending,
		error,
		sections,
		totalCount,
		hasLoaded,
		projectTitleById,
		areaTitleById,
		selectionType,
		selection,
		newTaskDraft,
		showDraft,
		areaOptions,
		projectsByArea,
		orphanProjects
	};
};
