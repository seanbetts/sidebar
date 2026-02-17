import { sveltekit } from '@sveltejs/kit/vite';
import { defineConfig } from 'vite';
import tailwindcss from '@tailwindcss/vite';
import { configDefaults } from 'vitest/config';

const runApiSmoke = process.env.RUN_API_SMOKE === '1';

export default defineConfig({
	plugins: [tailwindcss(), sveltekit()],
	resolve: {
		conditions: ['browser', 'development']
	},
	server: {
		port: 3000
	},
	test: {
		environment: 'jsdom',
		setupFiles: ['./src/tests/setup.ts'],
		globals: true,
		exclude: runApiSmoke
			? configDefaults.exclude
			: [...configDefaults.exclude, 'src/tests/flows/api-smoke.test.ts'],
		server: {
			deps: {
				inline: ['svelte']
			}
		},
		coverage: {
			include: ['src/lib/stores/*.ts', 'src/lib/stores/chat/**', 'src/lib/services/**'],
			exclude: ['src/lib/stores/tasks-types.ts'],
			reporter: ['text', 'html'],
			provider: 'v8',
			thresholds: {
				lines: 70,
				statements: 70,
				branches: 60,
				functions: 60
			}
		}
	}
});
