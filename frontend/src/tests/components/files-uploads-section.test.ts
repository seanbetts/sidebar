import { render, screen } from '@testing-library/svelte';
import userEvent from '@testing-library/user-event';
import type { ComponentType } from 'svelte';
import { describe, expect, it, vi } from 'vitest';
import FilesUploadsSection from '$lib/components/left-sidebar/files/FilesUploadsSection.svelte';
import type { IngestionListItem } from '$lib/types/ingestion';

const baseItem: IngestionListItem = {
	file: {
		id: 'file-1',
		filename_original: 'failed.txt',
		mime_original: 'text/plain',
		size_bytes: 12,
		created_at: new Date().toISOString()
	},
	job: {
		status: 'failed',
		stage: 'failed',
		attempts: 1,
		user_message: 'Upload failed.'
	},
	recommended_viewer: null
};

const DummyIcon = (() => null) as unknown as ComponentType;

describe('FilesUploadsSection', () => {
	it('renders failed uploads and triggers delete', async () => {
		const user = userEvent.setup();
		const onDelete = vi.fn();

		render(FilesUploadsSection, {
			props: {
				processingItems: [],
				failedItems: [baseItem],
				readyItems: [],
				openMenuKey: null,
				iconForCategory: () => DummyIcon,
				stripExtension: (name: string) => name,
				onOpen: vi.fn(),
				onToggleMenu: vi.fn(),
				onRename: vi.fn(),
				onPinToggle: vi.fn(),
				onDownload: vi.fn(),
				onDelete
			}
		});

		expect(screen.getByText('Failed uploads')).toBeInTheDocument();
		expect(screen.getByText('failed.txt')).toBeInTheDocument();

		await user.click(screen.getByLabelText('Delete upload'));
		expect(onDelete).toHaveBeenCalled();
	});
});
