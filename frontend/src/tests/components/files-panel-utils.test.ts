import { describe, expect, it } from 'vitest';
import {
	buildFilesPanelBuckets,
	normalizeIngestionStatus
} from '$lib/components/left-sidebar/files/filesPanelUtils';
import type { IngestionListItem } from '$lib/types/ingestion';

function makeItem(
	id: string,
	status: string | null,
	filename: string,
	recommendedViewer: string | null = null
): IngestionListItem {
	return {
		file: {
			id,
			filename_original: filename,
			mime_original: 'text/plain',
			size_bytes: 10,
			created_at: new Date().toISOString()
		},
		job: {
			status,
			stage: status,
			attempts: 0
		},
		recommended_viewer: recommendedViewer
	};
}

describe('filesPanelUtils', () => {
	it('builds files pane buckets using iOS/macOS parity rules', () => {
		const items = [
			makeItem('processing', 'processing', 'active.txt'),
			makeItem('ready', 'ready', 'ready.txt', 'text_original'),
			makeItem('failed', 'failed', 'failed.txt'),
			makeItem('unknown', null, 'unknown.txt'),
			makeItem('canceled', 'canceled', 'canceled.txt')
		];

		const buckets = buildFilesPanelBuckets(items, '');

		expect(buckets.mainItems.map((item) => item.file.id)).toEqual([
			'processing',
			'ready',
			'unknown',
			'canceled'
		]);
		expect(buckets.failedItems.map((item) => item.file.id)).toEqual(['failed']);
		expect(buckets.processingItems.map((item) => item.file.id)).toEqual(['processing']);
		expect(buckets.readyItems.map((item) => item.file.id)).toEqual(['ready']);
	});

	it('filters all buckets by search query', () => {
		const items = [
			makeItem('active-report', 'processing', 'Report Draft.txt'),
			makeItem('ready-report', 'ready', 'Report Final.txt', 'text_original'),
			makeItem('failed-report', 'failed', 'Report Failed.txt'),
			makeItem('ready-other', 'ready', 'Other.txt', 'text_original')
		];

		const buckets = buildFilesPanelBuckets(items, 'report');

		expect(buckets.filteredMainItems.map((item) => item.file.id)).toEqual([
			'active-report',
			'ready-report'
		]);
		expect(buckets.filteredFailedItems.map((item) => item.file.id)).toEqual(['failed-report']);
		expect(buckets.filteredProcessingItems.map((item) => item.file.id)).toEqual(['active-report']);
		expect(buckets.filteredReadyItems.map((item) => item.file.id)).toEqual(['ready-report']);
	});

	it('normalizes status values safely', () => {
		expect(normalizeIngestionStatus(null)).toBe('');
		expect(normalizeIngestionStatus('  READY  ')).toBe('ready');
		expect(normalizeIngestionStatus('Processing')).toBe('processing');
	});
});
