import { browser } from '$app/environment';

export interface SettingsRealtimePayload {
	assistant_identity?: {
		name?: string;
		tone?: string;
		values?: string;
		boundaries?: string;
	};
	assistant_identity_meta?: {
		updated_at?: string;
		version?: number;
		reason?: string | null;
	};
	assistant_soul?: {
		purpose?: string;
		operating_principles?: string;
		adaptation_policy?: string;
		success_signals?: string;
	};
	assistant_soul_meta?: {
		updated_at?: string;
		version?: number;
		reason?: string | null;
	};
	communication_style?: string;
	working_relationship?: string;
	name?: string;
	job_title?: string;
	employer?: string;
	date_of_birth?: string | null;
	gender?: string;
	pronouns?: string;
	location?: string;
	profile_image_url?: string | null;
	enabled_skills?: string[];
}

const SETTINGS_REALTIME_EVENT = 'settings:realtime-update';

/**
 * Broadcast realtime settings updates to open settings surfaces.
 *
 * @param payload Settings fields updated by an AI tool.
 */
export function dispatchSettingsRealtimeUpdate(payload: SettingsRealtimePayload): void {
	if (!browser) return;

	window.dispatchEvent(
		new CustomEvent<SettingsRealtimePayload>(SETTINGS_REALTIME_EVENT, {
			detail: payload
		})
	);
}

/**
 * Subscribe to realtime settings updates.
 *
 * @param callback Listener for settings updates.
 * @returns Unsubscribe function.
 */
export function onSettingsRealtimeUpdate(
	callback: (payload: SettingsRealtimePayload) => void
): () => void {
	if (!browser) return () => undefined;

	const handler = ((event: CustomEvent<SettingsRealtimePayload>) => {
		callback(event.detail);
	}) as EventListener;

	window.addEventListener(SETTINGS_REALTIME_EVENT, handler);
	return () => window.removeEventListener(SETTINGS_REALTIME_EVENT, handler);
}
