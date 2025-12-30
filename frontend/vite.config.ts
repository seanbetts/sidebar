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
			reporter: ['text', 'html'],
			provider: 'v8'
		}
	}
});
