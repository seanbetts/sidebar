import { describe, expect, it, vi } from 'vitest';

type RootLayoutLoad = typeof import('../../routes/+layout.server').load;

interface LoadOptions {
	url: string;
	envOverrides?: Record<string, string | undefined>;
}

const baseEnv = {
	SUPABASE_URL: 'https://supabase.example.test',
	SUPABASE_ANON_KEY: 'anon-key',
	MAINTENANCE_MODE: 'false'
};

async function runLoad(options: LoadOptions) {
	vi.resetModules();
	vi.doMock('$env/dynamic/private', () => ({
		env: {
			...baseEnv,
			...options.envOverrides
		}
	}));

	const module = await import('../../routes/+layout.server');
	const loadInput = {
		locals: { session: null, user: null },
		url: new URL(options.url)
	} as Parameters<RootLayoutLoad>[0];
	const result = await module.load(loadInput);
	if (!result) {
		throw new Error('Expected layout load to return data');
	}
	return result as Exclude<Awaited<ReturnType<RootLayoutLoad>>, void>;
}

describe('root layout maintenance mode', () => {
	it('does not enable maintenance mode when MAINTENANCE_MODE is false', async () => {
		const result = await runLoad({
			url: 'https://trysidebar.ai/'
		});

		expect(result.maintenanceMode).toBe(false);
	});

	it('enables maintenance mode when MAINTENANCE_MODE env var is true', async () => {
		const result = await runLoad({
			url: 'https://trysidebar.ai/',
			envOverrides: { MAINTENANCE_MODE: 'true' }
		});

		expect(result.maintenanceMode).toBe(true);
	});

	it('bypasses maintenance mode for privacy route even when enabled', async () => {
		const result = await runLoad({
			url: 'https://trysidebar.ai/privacy',
			envOverrides: { MAINTENANCE_MODE: 'true' }
		});

		expect(result.maintenanceMode).toBe(false);
	});

	it('bypasses maintenance mode for nested privacy paths', async () => {
		const result = await runLoad({
			url: 'https://trysidebar.ai/privacy/ios',
			envOverrides: { MAINTENANCE_MODE: 'true' }
		});

		expect(result.maintenanceMode).toBe(false);
	});

	it('throws when required Supabase environment variables are missing', async () => {
		await expect(
			runLoad({
				url: 'https://example.com/privacy',
				envOverrides: {
					SUPABASE_URL: '',
					SUPABASE_ANON_KEY: ''
				}
			})
		).rejects.toThrow('Missing SUPABASE_URL or SUPABASE_ANON_KEY');
	});
});
