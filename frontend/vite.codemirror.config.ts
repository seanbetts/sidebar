import path from 'node:path';
import { defineConfig } from 'vite';

export default defineConfig({
	root: path.resolve(__dirname, 'src/codemirror'),
	base: './',
	publicDir: false,
	build: {
		outDir: path.resolve(__dirname, 'dist/codemirror'),
		emptyOutDir: true,
		assetsInlineLimit: 0,
		cssCodeSplit: false,
		target: 'es2018',
		rollupOptions: {
			input: path.resolve(__dirname, 'src/codemirror/editor.html'),
			output: {
				format: 'iife',
				inlineDynamicImports: true,
				entryFileNames: 'editor.js',
				chunkFileNames: 'editor.js',
				assetFileNames: 'editor.css'
			}
		}
	}
});
