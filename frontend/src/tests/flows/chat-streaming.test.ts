import { describe, expect, it, vi } from 'vitest';
import { SSEClient } from '$lib/api/sse';

const createStream = (chunks: string[]) =>
	new ReadableStream<Uint8Array>({
		start(controller) {
			chunks.forEach((chunk) => controller.enqueue(new TextEncoder().encode(chunk)));
			controller.close();
		}
	});

describe('chat streaming flow', () => {
	it('parses tokens and completes the stream', async () => {
		const client = new SSEClient();
		const onToken = vi.fn();
		const onComplete = vi.fn();
		const onError = vi.fn();

		const stream = createStream([
			'event: token\n',
			'data: {"content":"Hello"}\n\n',
			'event: complete\n',
			'data: {}\n\n'
		]);

		global.fetch = vi.fn(async () => ({
			ok: true,
			status: 200,
			statusText: 'OK',
			body: stream
		})) as unknown as typeof fetch;

		await client.connect({ message: 'Hi' }, { onToken, onComplete, onError });

		expect(onToken).toHaveBeenCalledWith('Hello');
		expect(onComplete).toHaveBeenCalled();
		expect(onError).not.toHaveBeenCalled();
	});

	it('dispatches custom SSE events', async () => {
		const client = new SSEClient();
		const onNotePinned = vi.fn();
		const onIngestionUpdated = vi.fn();
		const onConversationTitleUpdated = vi.fn();
		const onProfileUserSettingsUpdated = vi.fn();
		const onOtherPreferencesUpdated = vi.fn();

		const stream = createStream([
			'event: note_pinned\n',
			'data: {"id":"note-1","pinned":true}\n\n',
			'event: ingestion_updated\n',
			'data: {"file_id":"file-1"}\n\n',
			'event: conversation_title_updated\n',
			'data: {"id":"conv-1","title":"Renamed","titleGenerated":false,"updatedAt":"2026-03-28T12:00:00Z"}\n\n',
			'event: profile_user_settings_updated\n',
			'data: {"name":"Sean"}\n\n',
			'event: other_preferences_updated\n',
			'data: {"weather_unit":"fahrenheit","biometric_unlock_enabled":true}\n\n',
			'event: complete\n',
			'data: {}\n\n'
		]);

		global.fetch = vi.fn(async () => ({
			ok: true,
			status: 200,
			statusText: 'OK',
			body: stream
		})) as unknown as typeof fetch;

		await client.connect(
			{ message: 'Hi' },
			{
				onNotePinned,
				onIngestionUpdated,
				onConversationTitleUpdated,
				onProfileUserSettingsUpdated,
				onOtherPreferencesUpdated
			}
		);

		expect(onNotePinned).toHaveBeenCalledWith({ id: 'note-1', pinned: true });
		expect(onIngestionUpdated).toHaveBeenCalledWith({ file_id: 'file-1' });
		expect(onConversationTitleUpdated).toHaveBeenCalledWith({
			id: 'conv-1',
			title: 'Renamed',
			titleGenerated: false,
			updatedAt: '2026-03-28T12:00:00Z'
		});
		expect(onProfileUserSettingsUpdated).toHaveBeenCalledWith({ name: 'Sean' });
		expect(onOtherPreferencesUpdated).toHaveBeenCalledWith({
			weather_unit: 'fahrenheit',
			biometric_unlock_enabled: true
		});
	});
});
