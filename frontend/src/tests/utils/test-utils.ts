import { vi } from 'vitest';

type MockResponseOptions = {
	ok?: boolean;
	status?: number;
	json?: unknown;
	text?: string;
};

export const mockFetch = (options: MockResponseOptions = {}) => {
	const { ok = true, status = ok ? 200 : 500, json, text } = options;
	const response = {
		ok,
		status,
		json: async () => json,
		text: async () => text ?? (json ? JSON.stringify(json) : '')
	} as Response;

	global.fetch = vi.fn(async () => response) as typeof fetch;
	return response;
};
