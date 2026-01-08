import { describe, expect, it } from 'vitest';

const RUN_SMOKE = process.env.RUN_API_SMOKE === '1';
const BASE_URL = process.env.API_SMOKE_BASE_URL || 'http://localhost:3000';
const DEFAULT_TIMEOUT_MS = 8000;

const allowedStatuses = new Set([200, 201, 204, 400, 401, 403, 405, 409, 422]);

async function fetchWithTimeout(
	url: string,
	init: RequestInit = {},
	timeoutMs = DEFAULT_TIMEOUT_MS
) {
	const controller = new AbortController();
	const timer = setTimeout(() => controller.abort(), timeoutMs);
	try {
		const response = await fetch(url, { ...init, signal: controller.signal });
		return response;
	} finally {
		clearTimeout(timer);
	}
}

const suite = RUN_SMOKE ? describe : describe.skip;

suite('API smoke (requires local server)', () => {
	const getEndpoints = [
		'/api/v1/health',
		'/api/v1/settings',
		'/api/v1/settings/profile-image',
		'/api/v1/skills',
		'/api/v1/notes/tree',
		'/api/v1/websites',
		'/api/v1/ingestion',
		'/api/v1/things/bridges/status',
		'/api/v1/things/diagnostics',
		'/api/v1/things/counts',
		'/api/v1/things/lists/today',
		'/api/v1/things/lists/upcoming',
		'/api/v1/places/reverse?lat=51.05587&lng=-0.13055',
		'/api/v1/weather?lat=51.05587&lon=-0.13055'
	];

	const postEndpoints: Array<{ path: string; body?: Record<string, unknown> }> = [
		{ path: '/api/v1/notes/search', body: { query: '', limit: 1 } },
		{ path: '/api/v1/websites/search', body: { query: '', limit: 1 } },
		{ path: '/api/v1/files/search', body: { basePath: 'documents', query: '', limit: 1 } }
	];

	const optionalPostEndpoints: Array<{ path: string; body?: Record<string, unknown> }> = [
		{ path: '/api/v1/ingestion/youtube', body: { url: '' } }
	];

	for (const path of getEndpoints) {
		const timeoutMs = path.includes('/api/v1/things/lists/upcoming') ? 10000 : DEFAULT_TIMEOUT_MS;
		it(
			`exposes ${path}`,
			async () => {
				const response = await fetchWithTimeout(`${BASE_URL}${path}`);
				expect(response.status).not.toBe(404);
				expect(allowedStatuses.has(response.status)).toBe(true);
			},
			timeoutMs
		);
	}

	for (const { path, body } of postEndpoints) {
		it(`exposes ${path} (POST)`, async () => {
			const response = await fetchWithTimeout(`${BASE_URL}${path}`, {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify(body ?? {})
			});
			expect(response.status).not.toBe(404);
			expect(allowedStatuses.has(response.status)).toBe(true);
		});
	}

	if (process.env.RUN_API_SMOKE_YOUTUBE === '1') {
		for (const { path, body } of optionalPostEndpoints) {
			it(`exposes ${path} (POST)`, async () => {
				const response = await fetchWithTimeout(`${BASE_URL}${path}`, {
					method: 'POST',
					headers: { 'Content-Type': 'application/json' },
					body: JSON.stringify(body ?? {})
				});
				expect(response.status).not.toBe(404);
				expect(allowedStatuses.has(response.status)).toBe(true);
			});
		}
	}

	it('exposes conversations list route', async () => {
		const response = await fetchWithTimeout(`${BASE_URL}/api/v1/conversations`);
		expect(response.status).not.toBe(404);
		expect(allowedStatuses.has(response.status)).toBe(true);
	});

	it('exposes files tree route', async () => {
		const response = await fetchWithTimeout(`${BASE_URL}/api/v1/files/tree?basePath=documents`);
		expect(response.status).not.toBe(404);
		expect(allowedStatuses.has(response.status)).toBe(true);
	});

	it('exposes chat stream route', async () => {
		const response = await fetchWithTimeout(`${BASE_URL}/api/v1/chat/stream`, {
			method: 'POST',
			headers: { 'Content-Type': 'application/json' },
			body: JSON.stringify({ message: 'smoke test' })
		});
		expect(response.status).not.toBe(404);
		expect(allowedStatuses.has(response.status)).toBe(true);
		await response.body?.cancel();
	});
});
