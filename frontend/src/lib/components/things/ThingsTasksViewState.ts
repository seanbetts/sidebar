import { CalendarCheck, CalendarClock, Inbox, Layers, List, Search } from 'lucide-svelte';
import type { ThingsNewTaskDraft, ThingsSelection, ThingsState } from '$lib/stores/things';
import type { ThingsArea, ThingsProject, ThingsTask } from '$lib/types/things';
import {
  buildSearchSections,
  buildTodaySections,
  buildUpcomingSections,
  sortByDueDate,
  type TaskSection
} from '$lib/components/things/tasksUtils';

export type ThingsTaskViewType = 'inbox' | 'today' | 'upcoming' | 'area' | 'project' | 'search';

export type ThingsTasksViewState = {
  tasks: ThingsTask[];
  selectionLabel: string;
  titleIcon: typeof CalendarCheck;
  selectionQuery: string;
  areas: ThingsArea[];
  projects: ThingsProject[];
  isLoading: boolean;
  searchPending: boolean;
  error: string;
  sections: TaskSection[];
  totalCount: number;
  hasLoaded: boolean;
  projectTitleById: Map<string, string>;
  areaTitleById: Map<string, string>;
  selectionType: ThingsTaskViewType;
  selection: ThingsSelection;
  newTaskDraft: ThingsNewTaskDraft | null;
  showDraft: boolean;
  areaOptions: ThingsArea[];
  projectsByArea: Map<string, ThingsProject[]>;
  orphanProjects: ThingsProject[];
};

export const isSameSelection = (a: ThingsSelection, b: ThingsSelection) => {
  if (a.type !== b.type) return false;
  if (a.type === 'area' || a.type === 'project') {
    return a.id === (b as { id: string }).id;
  }
  if (a.type === 'search') {
    return a.query === (b as { query: string }).query;
  }
  return true;
};

export const computeTasksViewState = (state: ThingsState): ThingsTasksViewState => {
  const { tasks, areas, projects, selection, isLoading, searchPending, error, newTaskDraft } = state;
  const selectionType = selection.type as ThingsTaskViewType;
  const projectIds = new Set(projects.map((project) => project.id));
  const filteredTasks = tasks.filter((task) => task.status !== 'project');
  const visibleTasks =
    selectionType === 'area' || selectionType === 'search'
      ? filteredTasks.filter((task) => !projectIds.has(task.id))
      : filteredTasks;
  const sortedTasks =
    selectionType === 'area' || selectionType === 'project' || selectionType === 'search'
      ? sortByDueDate(visibleTasks)
      : visibleTasks;
  const projectTitleById = new Map(projects.map((project) => [project.id, project.title]));
  const areaTitleById = new Map(areas.map((area) => [area.id, area.title]));
  const areaOptions = [...areas].sort((a, b) => a.title.localeCompare(b.title));
  const projectOptions = [...projects].sort((a, b) => a.title.localeCompare(b.title));
  const projectsByArea = new Map<string, ThingsProject[]>();
  const orphanProjects: ThingsProject[] = [];

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
    selectionLabel = areas.find((area) => area.id === selection.id)?.title || 'Area';
    titleIcon = Layers;
    sections = sortedTasks.length ? [{ id: 'all', title: '', tasks: sortedTasks }] : [];
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

  const totalCount = sections.reduce((sum, section) => sum + section.tasks.length, 0);
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
