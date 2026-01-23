import { sveltekit } from '@sveltejs/kit/vite';
import { defineConfig } from 'vite';
import tailwindcss from '@tailwindcss/vite';

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
