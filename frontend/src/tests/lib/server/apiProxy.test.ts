import type { RequestEvent } from '@sveltejs/kit';
import type { Span } from '@opentelemetry/api';
import { describe, expect, it, vi } from 'vitest';

import { createProxyHandler } from '$lib/server/apiProxy';

vi.mock('$lib/server/api', () => ({
	getApiUrl: () => 'http://example.test',
	buildAuthHeaders: () => ({ Authorization: 'Bearer test' })
}));

describe('createProxyHandler', () => {
	const locals = { supabase: {} as App.Locals['supabase'], session: null, user: null };
	const spanStub = {} as unknown as Span;
	const baseEvent: RequestEvent = {
		cookies: {
			get: vi.fn(),
			getAll: vi.fn(),
			set: vi.fn(),
			delete: vi.fn(),
			serialize: vi.fn()
		},
		fetch: vi.fn(),
		getClientAddress: () => '127.0.0.1',
		locals,
		params: {},
		platform: undefined,
		request: new Request('http://localhost'),
		route: { id: null },
		setHeaders: vi.fn(),
		url: new URL('http://localhost'),
		isDataRequest: false,
		isSubRequest: false,
		isRemoteRequest: false,
		tracing: {
			enabled: false,
			root: spanStub,
			current: spanStub
		}
	};

	const createEvent = (overrides: Partial<RequestEvent>) =>
		({
			...baseEvent,
			...overrides,
			locals: overrides.locals ? { ...locals, ...overrides.locals } : locals
		}) as RequestEvent;

	it('proxies GET requests and returns JSON', async () => {
		const fetchMock = vi
			.fn()
			.mockResolvedValue(new Response(JSON.stringify({ ok: true }), { status: 200 }));

		const handler = createProxyHandler({
			pathBuilder: (params) => `/api/v1/notes/${params.id}`
		});

		const response = await handler(
			createEvent({
				locals,
				fetch: fetchMock,
				params: { id: '123' },
				request: new Request('http://localhost'),
				url: new URL('http://localhost')
			})
		);

		expect(fetchMock).toHaveBeenCalledWith('http://example.test/api/v1/notes/123', {
			method: 'GET',
			headers: { Authorization: 'Bearer test' }
		});
		expect(response.status).toBe(200);
		await expect(response.json()).resolves.toEqual({ ok: true });
	});

	it('proxies requests with body content', async () => {
		const fetchMock = vi
			.fn()
			.mockResolvedValue(new Response(JSON.stringify({ saved: true }), { status: 201 }));

		const handler = createProxyHandler({
			method: 'POST',
			pathBuilder: () => '/api/v1/notes',
			bodyFromRequest: true
		});

		const request = new Request('http://localhost', {
			method: 'POST',
			headers: { 'Content-Type': 'application/json' },
			body: JSON.stringify({ title: 'Note' })
		});

		const response = await handler(
			createEvent({
				locals,
				fetch: fetchMock,
				params: {},
				request,
				url: new URL('http://localhost')
			})
		);

		const fetchArgs = fetchMock.mock.calls[0];
		expect(fetchArgs[0]).toBe('http://example.test/api/v1/notes');
		expect(fetchArgs[1]).toMatchObject({
			method: 'POST',
			headers: {
				Authorization: 'Bearer test',
				'Content-Type': 'application/json'
			}
		});
		expect(fetchArgs[1]?.body).toBe(JSON.stringify({ title: 'Note' }));
		expect(response.status).toBe(201);
	});

	it('appends query params when configured', async () => {
		const fetchMock = vi
			.fn()
			.mockResolvedValue(new Response(JSON.stringify({ ok: true }), { status: 200 }));

		const handler = createProxyHandler({
			method: 'POST',
			pathBuilder: () => '/api/v1/notes/search',
			queryParamsFromUrl: true
		});

		const response = await handler(
			createEvent({
				locals,
				fetch: fetchMock,
				params: {},
				request: new Request('http://localhost'),
				url: new URL('http://localhost?query=test&limit=10')
			})
		);

		expect(fetchMock).toHaveBeenCalledWith(
			'http://example.test/api/v1/notes/search?query=test&limit=10',
			{
				method: 'POST',
				headers: { Authorization: 'Bearer test' }
			}
		);
		expect(response.status).toBe(200);
	});

	it('returns backend error payloads', async () => {
		const fetchMock = vi
			.fn()
			.mockResolvedValue(new Response(JSON.stringify({ error: 'Not found' }), { status: 404 }));

		const handler = createProxyHandler({
			pathBuilder: () => '/api/v1/notes/missing'
		});

		const response = await handler(
			createEvent({
				locals,
				fetch: fetchMock,
				params: {},
				request: new Request('http://localhost'),
				url: new URL('http://localhost')
			})
		);

		expect(response.status).toBe(404);
		await expect(response.json()).resolves.toEqual({ error: 'Not found' });
	});

	it('returns text responses when configured', async () => {
		const fetchMock = vi
			.fn()
			.mockResolvedValue(
				new Response('ok-text', { status: 202, headers: { 'Content-Type': 'text/plain' } })
			);

		const handler = createProxyHandler({
			pathBuilder: () => '/api/v1/settings',
			responseType: 'text'
		});

		const response = await handler(
			createEvent({
				locals,
				fetch: fetchMock,
				params: {},
				request: new Request('http://localhost'),
				url: new URL('http://localhost')
			})
		);

		expect(response.status).toBe(202);
		await expect(response.text()).resolves.toBe('ok-text');
	});

	it('streams responses when configured', async () => {
		const fetchMock = vi
			.fn()
			.mockResolvedValue(
				new Response('streamed', { status: 200, headers: { 'Content-Type': 'text/plain' } })
			);

		const handler = createProxyHandler({
			pathBuilder: () => '/api/v1/files/download',
			responseType: 'stream'
		});

		const response = await handler(
			createEvent({
				locals,
				fetch: fetchMock,
				params: {},
				request: new Request('http://localhost'),
				url: new URL('http://localhost')
			})
		);

		expect(response.status).toBe(200);
		await expect(response.text()).resolves.toBe('streamed');
	});

	it('returns 500 on unexpected errors', async () => {
		const fetchMock = vi.fn().mockRejectedValue(new Error('Boom'));

		const handler = createProxyHandler({
			pathBuilder: () => '/api/v1/notes'
		});

		const response = await handler(
			createEvent({
				locals,
				fetch: fetchMock,
				params: {},
				request: new Request('http://localhost'),
				url: new URL('http://localhost')
			})
		);

		expect(response.status).toBe(500);
		await expect(response.json()).resolves.toEqual({ error: 'Boom' });
	});
});
