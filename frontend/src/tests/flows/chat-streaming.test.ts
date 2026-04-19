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
		const onWebsiteRenamed = vi.fn();
		const onIngestionUpdated = vi.fn();
		const onConversationTitleUpdated = vi.fn();
		const onAssistantIdentityUpdated = vi.fn();
		const onAssistantSoulUpdated = vi.fn();
		const onProfileUserSettingsUpdated = vi.fn();
		const onOtherPreferencesUpdated = vi.fn();

		const stream = createStream([
			'event: entity_changed\n',
			'data: {"entity_type":"note","entity_id":"note-1","change":"pinned","patch":{"id":"note-1","pinned":true},"invalidate":["notes","note:note-1"]}\n\n',
			'event: entity_changed\n',
			'data: {"entity_type":"website","entity_id":"website-1","change":"renamed","patch":{"id":"website-1","title":"Renamed website"},"invalidate":["websites","website:website-1"]}\n\n',
			'event: collection_invalidated\n',
			'data: {"targets":["ingestion"]}\n\n',
			'event: entity_changed\n',
			'data: {"entity_type":"conversation","entity_id":"conv-1","change":"renamed","patch":{"title":"Renamed","titleGenerated":false,"updatedAt":"2026-03-28T12:00:00Z"},"invalidate":["conversations","conversation:conv-1"]}\n\n',
			'event: collection_invalidated\n',
			'data: {"targets":["assistant_settings"]}\n\n',
			'event: collection_invalidated\n',
			'data: {"targets":["assistant_settings"]}\n\n',
			'event: collection_invalidated\n',
			'data: {"targets":["profile","preferences"]}\n\n',
			'event: collection_invalidated\n',
			'data: {"targets":["preferences"]}\n\n',
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
				onWebsiteRenamed,
				onIngestionUpdated,
				onConversationTitleUpdated,
				onAssistantIdentityUpdated,
				onAssistantSoulUpdated,
				onProfileUserSettingsUpdated,
				onOtherPreferencesUpdated
			}
		);

		expect(onNotePinned).toHaveBeenCalledWith({ id: 'note-1', pinned: true });
		expect(onWebsiteRenamed).toHaveBeenCalledWith({
			id: 'website-1',
			title: 'Renamed website'
		});
		expect(onIngestionUpdated).toHaveBeenCalledWith({});
		expect(onConversationTitleUpdated).toHaveBeenCalledWith({
			id: 'conv-1',
			title: 'Renamed',
			titleGenerated: false,
			updatedAt: '2026-03-28T12:00:00Z'
		});
		expect(onAssistantIdentityUpdated).toHaveBeenCalledWith({});
		expect(onAssistantSoulUpdated).toHaveBeenCalledWith({});
		expect(onProfileUserSettingsUpdated).toHaveBeenCalledWith({});
		expect(onOtherPreferencesUpdated).toHaveBeenCalledWith({});
	});
});
