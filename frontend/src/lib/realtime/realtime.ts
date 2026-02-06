import type { RealtimeChannel, RealtimePostgresChangesPayload } from '@supabase/supabase-js';
import { getSupabaseClient } from '$lib/supabase';
import { websitesStore, type WebsiteItem } from '$lib/stores/websites';
import { treeStore } from '$lib/stores/tree';
import { ingestionStore } from '$lib/stores/ingestion';
import { ingestionViewerStore } from '$lib/stores/ingestion-viewer';
import { scratchpadStore } from '$lib/stores/scratchpad';
import { get } from 'svelte/store';
import { session } from '$lib/stores/auth';

const SCRATCHPAD_TITLE = '✏️ Scratchpad';
let activeUserId: string | null = null;
let activeAccessToken: string | null = null;
let channels: RealtimeChannel[] = [];
let ingestionRefreshTimer: ReturnType<typeof setTimeout> | null = null;
let sessionListener: (() => void) | null = null;

function stopIngestionRefreshTimer() {
	if (ingestionRefreshTimer) {
		clearTimeout(ingestionRefreshTimer);
		ingestionRefreshTimer = null;
	}
}

function stopSessionListener() {
	if (sessionListener) {
		sessionListener();
		sessionListener = null;
	}
}

function watchForSession(userId: string) {
	if (sessionListener) return;
	sessionListener = session.subscribe((value) => {
		if (value?.access_token) {
			stopSessionListener();
			void startRealtime(userId);
		}
	});
}

function scheduleIngestionRefresh() {
	if (ingestionRefreshTimer) return;
	ingestionRefreshTimer = setTimeout(async () => {
		ingestionRefreshTimer = null;
		await ingestionStore.revalidateInBackground();
	}, 500);
}

function notifyScratchpad(content?: string | null) {
	if (typeof content !== 'string') return;
	const cached = scratchpadStore.getCachedContent();
	if (cached === content) return;
	scratchpadStore.setCachedContent(content);
	scratchpadStore.bump();
}

function isArchivedFolder(folder: string): boolean {
	return folder === 'Archive' || folder.startsWith('Archive/');
}

function mapWebsiteRow(row: any): WebsiteItem {
	const metadata = row?.metadata || {};
	return {
		id: row.id,
		title: row.title,
		url: row.url,
		domain: row.domain,
		saved_at: row.saved_at,
		published_at: row.published_at,
		pinned: metadata.pinned ?? false,
		pinned_order: metadata.pinned_order ?? null,
		archived: metadata.archived ?? false,
		favicon_url: metadata.favicon_url ?? null,
		favicon_r2_key: metadata.favicon_r2_key ?? null,
		favicon_extracted_at: metadata.favicon_extracted_at ?? null,
		reading_time: null,
		updated_at: row.updated_at,
		last_opened_at: row.last_opened_at,
		deleted_at: row.deleted_at
	};
}

function handleWebsiteChange(payload: RealtimePostgresChangesPayload<any>) {
	const record = payload.eventType === 'DELETE' ? payload.old : payload.new;
	if (!record) return;
	if (payload.eventType === 'DELETE' || record.deleted_at) {
		websitesStore.removeLocal(record.id);
		return;
	}
	websitesStore.upsertFromRealtime(mapWebsiteRow(record));
}

function handleNoteChange(payload: RealtimePostgresChangesPayload<any>) {
	const record = payload.eventType === 'DELETE' ? payload.old : payload.new;
	if (!record) return;

	if (record.title === SCRATCHPAD_TITLE) {
		if (payload.eventType === 'DELETE') {
			notifyScratchpad(`# ${SCRATCHPAD_TITLE}\n\n`);
			return;
		}
		notifyScratchpad(record.content);
		return;
	}

	if (payload.eventType === 'DELETE' || record.deleted_at) {
		treeStore.removeNode('notes', record.id);
		return;
	}

	const metadata = record.metadata || {};
	const folder = metadata.folder || '';
	const archived = isArchivedFolder(folder);
	const pinned = Boolean(metadata.pinned);
	const pinnedOrder = metadata.pinned_order ?? null;
	const modifiedSeconds = record.updated_at ? Date.parse(record.updated_at) / 1000 : undefined;

	if (payload.eventType === 'INSERT') {
		treeStore.addNoteNode({
			id: record.id,
			name: `${record.title}.md`,
			folder,
			modified: modifiedSeconds,
			pinned,
			pinned_order: pinnedOrder,
			archived
		});
		return;
	}

	const previous = payload.old || {};
	const previousMetadata = previous.metadata || {};
	const previousFolder = previousMetadata.folder || '';
	const previousTitle = previous.title;

	if (previousTitle && previousTitle !== record.title) {
		treeStore.renameNoteNode(record.id, `${record.title}.md`);
	}

	if (previousFolder !== folder) {
		treeStore.moveNoteNode(record.id, folder, { archived });
	}

	treeStore.updateNoteFields(record.id, {
		pinned,
		pinned_order: pinned ? pinnedOrder : null,
		archived,
		modified: record.updated_at ? new Date(record.updated_at).toISOString() : undefined
	});
}

function handleIngestedFileChange(payload: RealtimePostgresChangesPayload<any>) {
	const record = payload.eventType === 'DELETE' ? payload.old : payload.new;
	if (!record) return;

	if (payload.eventType === 'DELETE' || record.deleted_at) {
		ingestionStore.removeItem(record.id);
		return;
	}

	if (payload.eventType === 'INSERT') {
		scheduleIngestionRefresh();
		return;
	}

	ingestionStore.updateFileFields(record.id, {
		filename_original: record.filename_original,
		path: record.path,
		mime_original: record.mime_original,
		size_bytes: record.size_bytes,
		sha256: record.sha256,
		source_url: record.source_url,
		source_metadata: record.source_metadata,
		pinned: record.pinned,
		pinned_order: record.pinned_order
	});
}

function handleFileJobChange(payload: RealtimePostgresChangesPayload<any>) {
	const record = payload.eventType === 'DELETE' ? payload.old : payload.new;
	if (!record) return;

	ingestionStore.updateJob(record.file_id, {
		status: record.status,
		stage: record.stage,
		error_code: record.error_code,
		error_message: record.error_message,
		attempts: record.attempts,
		updated_at: record.updated_at
	});

	ingestionViewerStore.updateActiveJob(record.file_id, {
		status: record.status,
		stage: record.stage,
		error_code: record.error_code,
		error_message: record.error_message,
		attempts: record.attempts,
		updated_at: record.updated_at
	});

	const state = get(ingestionStore);
	const hasItem = state.items.some((item) => item.file.id === record.file_id);
	if (!hasItem) {
		scheduleIngestionRefresh();
	}
}

/**
 * Stop realtime subscriptions and timers.
 */
export function stopRealtime() {
	if (!channels.length) {
		activeUserId = null;
		activeAccessToken = null;
		stopIngestionRefreshTimer();
		stopSessionListener();
		return;
	}
	const supabase = getSupabaseClient();
	channels.forEach((channel) => {
		supabase.removeChannel(channel);
	});
	channels = [];
	activeUserId = null;
	activeAccessToken = null;
	stopIngestionRefreshTimer();
	stopSessionListener();
}

/**
 * Start realtime subscriptions for the active user.
 *
 * @param userId Supabase user id.
 */
export async function startRealtime(userId: string | null) {
	if (!userId) {
		stopRealtime();
		return;
	}
	const token = get(session)?.access_token ?? null;
	if (!token) {
		activeUserId = userId;
		activeAccessToken = null;
		watchForSession(userId);
		return;
	}

	if (activeUserId === userId && token === activeAccessToken && channels.length) {
		return;
	}

	stopRealtime();
	activeUserId = userId;
	activeAccessToken = token;

	const supabase = getSupabaseClient();
	supabase.realtime.setAuth(token);

	const notesChannel = supabase.channel(`notes-${userId}`).on(
		'postgres_changes',
		{
			event: '*',
			schema: 'public',
			table: 'notes',
			filter: `user_id=eq.${userId}`
		},
		handleNoteChange
	);

	const websitesChannel = supabase.channel(`websites-${userId}`).on(
		'postgres_changes',
		{
			event: '*',
			schema: 'public',
			table: 'websites',
			filter: `user_id=eq.${userId}`
		},
		handleWebsiteChange
	);

	const ingestedFilesChannel = supabase.channel(`ingested-files-${userId}`).on(
		'postgres_changes',
		{
			event: '*',
			schema: 'public',
			table: 'ingested_files',
			filter: `user_id=eq.${userId}`
		},
		handleIngestedFileChange
	);

	const jobsChannel = supabase.channel(`file-jobs-${userId}`).on(
		'postgres_changes',
		{
			event: '*',
			schema: 'public',
			table: 'file_processing_jobs'
		},
		handleFileJobChange
	);

	channels = [notesChannel, websitesChannel, ingestedFilesChannel, jobsChannel];
	channels.forEach((channel) => {
		channel.subscribe();
	});
}
