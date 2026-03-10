import adapter from '@sveltejs/adapter-static';
import { vitePreprocess } from '@sveltejs/vite-plugin-svelte';

/** @type {import('@sveltejs/kit').Config} */
export default {
  preprocess: vitePreprocess(),
  kit: {
    adapter: adapter({
      pages: 'build',
      assets: 'build',
      fallback: null,
      precompress: false
    }),
    alias: {
      $lib: './src/lib'
    },
    prerender: {
      handleHttpError: ({ path, message }) => {
        // Ignore missing static assets during build — they will be added later
        if (path.startsWith('/favicon') || path === '/logo.svg' || path === '/apple-touch-icon.png') {
          return;
        }
        throw new Error(message);
      }
    }
  }
};
