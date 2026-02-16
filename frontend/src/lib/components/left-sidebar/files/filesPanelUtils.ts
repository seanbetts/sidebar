import {
	FileChartPie,
	FileText,
	FileSpreadsheet,
	FileMusic,
	FileVideoCamera,
	FileChartLine,
	Image
} from 'lucide-svelte';
import type { IngestionListItem } from '$lib/types/ingestion';

export const categoryOrder = [
	'audio',
	'documents',
	'images',
	'presentations',
	'reports',
	'spreadsheets',
	'video',
	'other'
];

export const categoryLabels: Record<string, string> = {
	images: 'Images',
	documents: 'Documents',
	spreadsheets: 'Spreadsheets',
	presentations: 'Presentations',
	reports: 'Reports',
	audio: 'Audio',
	video: 'Video',
	other: 'Other'
};

export function iconForCategory(category: string | null | undefined) {
	if (category === 'images') return Image;
	if (category === 'spreadsheets') return FileSpreadsheet;
	if (category === 'presentations') return FileChartPie;
	if (category === 'reports') return FileChartLine;
	if (category === 'audio') return FileMusic;
	if (category === 'video') return FileVideoCamera;
	return FileText;
}

export function stripExtension(name: string): string {
	const index = name.lastIndexOf('.');
	if (index <= 0) return name;
	return name.slice(0, index);
}

const TERMINAL_STATUSES = new Set(['ready', 'failed', 'canceled']);

/**
 * Normalize ingestion status values for consistent filtering.
 *
 * @param status Raw status value.
 * @returns Lowercased status string.
 */
export function normalizeIngestionStatus(status: string | null | undefined): string {
	return (status ?? '').trim().toLowerCase();
}

/**
 * Files panel bucket result.
 */
export interface FilesPanelBuckets {
	processingItems: IngestionListItem[];
	failedItems: IngestionListItem[];
	readyItems: IngestionListItem[];
	mainItems: IngestionListItem[];
	filteredProcessingItems: IngestionListItem[];
	filteredFailedItems: IngestionListItem[];
	filteredReadyItems: IngestionListItem[];
	filteredMainItems: IngestionListItem[];
}

/**
 * Build files panel buckets used by sidebar rendering.
 *
 * Mirrors iOS/macOS panel behavior:
 * - Main list includes all non-failed items.
 * - Processing list includes active non-terminal statuses only.
 * - Ready list includes only openable ready items.
 *
 * @param items Ingestion list items.
 * @param searchQuery Current search query.
 * @returns Grouped and search-filtered buckets.
 */
export function buildFilesPanelBuckets(
	items: IngestionListItem[],
	searchQuery: string
): FilesPanelBuckets {
	const normalizedQuery = searchQuery.trim().toLowerCase();
	const processingItems = items.filter((item) => {
		const status = normalizeIngestionStatus(item.job.status);
		return status !== '' && !TERMINAL_STATUSES.has(status);
	});
	const failedItems = items.filter(
		(item) => normalizeIngestionStatus(item.job.status) === 'failed'
	);
	const readyItems = items.filter(
		(item) =>
			normalizeIngestionStatus(item.job.status) === 'ready' && Boolean(item.recommended_viewer)
	);
	const mainItems = items.filter((item) => normalizeIngestionStatus(item.job.status) !== 'failed');

	const filterByQuery = (list: IngestionListItem[]) =>
		normalizedQuery
			? list.filter((item) =>
					(item.file.filename_original || '').toLowerCase().includes(normalizedQuery)
				)
			: list;

	return {
		processingItems,
		failedItems,
		readyItems,
		mainItems,
		filteredProcessingItems: filterByQuery(processingItems),
		filteredFailedItems: filterByQuery(failedItems),
		filteredReadyItems: filterByQuery(readyItems),
		filteredMainItems: filterByQuery(mainItems)
	};
}
