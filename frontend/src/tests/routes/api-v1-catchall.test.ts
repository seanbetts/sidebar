import { describe, expect, it, vi } from 'vitest';

vi.mock('$lib/server/api', () => ({
	getApiUrl: () => 'http://example.test',
	buildAuthHeaders: () => ({ Authorization: 'Bearer test' })
}));

import { POST } from '../../routes/api/v1/[...path]/+server';

describe('api/v1 catch-all proxy', () => {
	it('forwards user-agent and app-version headers', async () => {
		const fetchMock = vi.fn().mockResolvedValue(new Response('ok', { status: 200 }));
		const request = new Request('http://localhost/api/v1/chat/stream?foo=1', {
			method: 'POST',
			headers: {
				'Content-Type': 'application/json',
				'User-Agent': 'sideBar-web-test',
				'X-App-Version': '1.2.3'
			},
			body: JSON.stringify({ message: 'Hello' })
		});

		const response = await POST({
			request,
			url: new URL('http://localhost/api/v1/chat/stream?foo=1'),
			locals: {},
			fetch: fetchMock
		} as any);

		expect(response.status).toBe(200);
		expect(fetchMock).toHaveBeenCalledTimes(1);
		const [targetUrl, init] = fetchMock.mock.calls[0] as [string, RequestInit];
		expect(targetUrl).toBe('http://example.test/api/v1/chat/stream?foo=1');
		const headers = init.headers as Headers;
		expect(headers.get('user-agent')).toBe('sideBar-web-test');
		expect(headers.get('x-app-version')).toBe('1.2.3');
		expect(headers.get('authorization')).toBe('Bearer test');
	});
});
