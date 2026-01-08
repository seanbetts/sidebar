import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

vi.mock('$app/environment', () => ({
	browser: true
}));

vi.mock('$lib/utils/publicEnv', () => ({
	getPublicEnv: () => ({
		PUBLIC_CHAT_METRICS_ENDPOINT: '/api/metrics/chat',
		PUBLIC_CHAT_METRICS_SAMPLE_RATE: '1'
	})
}));

describe('chatMetrics', () => {
	beforeEach(() => {
		vi.resetModules();
		vi.useFakeTimers();
		vi.setSystemTime(new Date('2026-01-07T00:00:00Z'));
		const sendBeacon = vi.fn().mockReturnValue(true);
		Object.defineProperty(global.navigator, 'sendBeacon', {
			value: sendBeacon,
			configurable: true
		});
	});

	afterEach(() => {
		vi.useRealTimers();
	});

	it('reports stream and tool timings', async () => {
		const sendBeacon = vi.spyOn(global.navigator, 'sendBeacon');
		const {
			startChatStream,
			markFirstEvent,
			markFirstToken,
			markStreamComplete,
			markToolStart,
			markToolEnd
		} = await import('$lib/utils/chatMetrics');

		startChatStream('msg-1');
		markFirstEvent('msg-1', 42);
		vi.setSystemTime(new Date('2026-01-07T00:00:01Z'));
		markFirstToken('msg-1');

		markToolStart('msg-1', 'Search');
		vi.setSystemTime(new Date('2026-01-07T00:00:03Z'));
		markToolEnd('msg-1', 'Search', 'success');

		vi.setSystemTime(new Date('2026-01-07T00:00:05Z'));
		markStreamComplete('msg-1');

		expect(sendBeacon).toHaveBeenCalled();
		const payloads = sendBeacon.mock.calls.map((call) => JSON.parse(call[1] as string));
		expect(payloads).toEqual(
			expect.arrayContaining([
				expect.objectContaining({ name: 'sse_connect_ms' }),
				expect.objectContaining({ name: 'first_token_latency_ms' }),
				expect.objectContaining({
					name: 'tool_duration_ms',
					tool_name: 'Search',
					status: 'success'
				}),
				expect.objectContaining({ name: 'stream_duration_ms' })
			])
		);
	});
});
