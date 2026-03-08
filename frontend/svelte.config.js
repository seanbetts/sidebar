import { vitePreprocess } from '@sveltejs/vite-plugin-svelte';

const adapter = process.env.CF_PAGES
	? (await import('@sveltejs/adapter-cloudflare')).default
	: (await import('@sveltejs/adapter-node')).default;

/** @type {import('@sveltejs/kit').Config} */
const config = {
	// Consult https://kit.svelte.dev/docs/integrations#preprocessors
	// for more information about preprocessors
	preprocess: vitePreprocess(),

	kit: {
		adapter: adapter(),
		alias: {
			$lib: './src/lib'
		}
	}
};

export default config;
