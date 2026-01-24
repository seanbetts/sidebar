import js from '@eslint/js';
import svelte from 'eslint-plugin-svelte';
import svelteParser from 'svelte-eslint-parser';
import tsPlugin from '@typescript-eslint/eslint-plugin';
import tsParser from '@typescript-eslint/parser';

const nodeMajor = Number.parseInt(process.versions.node.split('.')[0], 10);
const jsdoc = nodeMajor >= 20 ? (await import('eslint-plugin-jsdoc')).default : null;
const jsdocRules = jsdoc
	? {
			'jsdoc/check-alignment': 'error',
			'jsdoc/check-tag-names': 'error',
			'jsdoc/check-types': 'error',
			'jsdoc/require-param-type': 'off',
			'jsdoc/require-returns-type': 'off'
		}
	: {};
const jsdocSettings = jsdoc
	? {
			jsdoc: {
				mode: 'typescript',
				tagNamePreference: {
					returns: 'returns'
				}
			}
		}
	: {};

export default [
	js.configs.recommended,
	...svelte.configs['flat/recommended'],
	{
		files: ['**/*.ts', '**/*.js'],
		plugins: {
			'@typescript-eslint': tsPlugin,
			...(jsdoc ? { jsdoc } : {})
		},
		languageOptions: {
			parser: tsParser,
			parserOptions: {
				ecmaVersion: 2022,
				sourceType: 'module',
				project: './tsconfig.json'
			},
			globals: {
				// Browser globals
				console: 'readonly',
				fetch: 'readonly',
				setTimeout: 'readonly',
				clearTimeout: 'readonly',
				setInterval: 'readonly',
				clearInterval: 'readonly',
				requestAnimationFrame: 'readonly',
				cancelAnimationFrame: 'readonly',
				getComputedStyle: 'readonly',
				localStorage: 'readonly',
				sessionStorage: 'readonly',
				indexedDB: 'readonly',
				crypto: 'readonly',
				window: 'readonly',
				document: 'readonly',
				navigator: 'readonly',
				URL: 'readonly',
				Blob: 'readonly',
				Response: 'readonly',
				Request: 'readonly',
				// DOM types
				Event: 'readonly',
				KeyboardEvent: 'readonly',
				MouseEvent: 'readonly',
				PointerEvent: 'readonly',
				DragEvent: 'readonly',
				SubmitEvent: 'readonly',
				HTMLElement: 'readonly',
				HTMLDivElement: 'readonly',
				HTMLInputElement: 'readonly',
				HTMLTextAreaElement: 'readonly',
				HTMLButtonElement: 'readonly',
				HTMLCanvasElement: 'readonly',
				HTMLTableSectionElement: 'readonly',
				HTMLAnchorElement: 'readonly',
				HTMLParagraphElement: 'readonly',
				FileList: 'readonly',
				File: 'readonly',
				CustomEvent: 'readonly',
				HTMLSelectElement: 'readonly',
				HTMLSpanElement: 'readonly',
				HTMLTableCellElement: 'readonly',
				HTMLTableRowElement: 'readonly',
				ResizeObserver: 'readonly',
				Node: 'readonly',
				// Node globals (for SSR/tests)
				process: 'readonly',
				Buffer: 'readonly',
				global: 'readonly',
				App: 'readonly'
			}
		},
		rules: {
			// Allow unused vars in function params (common in TypeScript interfaces)
			'no-unused-vars': 'off',
			'@typescript-eslint/no-unused-vars': [
				'warn',
				{
					argsIgnorePattern: '^_',
					varsIgnorePattern: '^_',
					args: 'none' // Don't check function parameters
				}
			],

			...jsdocRules
		},
		settings: {
			...jsdocSettings
		}
	},
	{
		files: ['**/*.svelte'],
		languageOptions: {
			parser: svelteParser,
			parserOptions: {
				parser: tsParser,
				ecmaVersion: 2022,
				sourceType: 'module',
				extraFileExtensions: ['.svelte']
			},
			globals: {
				console: 'readonly',
				fetch: 'readonly',
				setTimeout: 'readonly',
				clearTimeout: 'readonly',
				setInterval: 'readonly',
				clearInterval: 'readonly',
				requestAnimationFrame: 'readonly',
				cancelAnimationFrame: 'readonly',
				getComputedStyle: 'readonly',
				localStorage: 'readonly',
				sessionStorage: 'readonly',
				indexedDB: 'readonly',
				crypto: 'readonly',
				window: 'readonly',
				document: 'readonly',
				navigator: 'readonly',
				URL: 'readonly',
				Blob: 'readonly',
				Response: 'readonly',
				Request: 'readonly',
				Event: 'readonly',
				KeyboardEvent: 'readonly',
				MouseEvent: 'readonly',
				PointerEvent: 'readonly',
				DragEvent: 'readonly',
				SubmitEvent: 'readonly',
				HTMLElement: 'readonly',
				HTMLDivElement: 'readonly',
				HTMLInputElement: 'readonly',
				HTMLTextAreaElement: 'readonly',
				HTMLButtonElement: 'readonly',
				HTMLCanvasElement: 'readonly',
				HTMLTableSectionElement: 'readonly',
				HTMLAnchorElement: 'readonly',
				HTMLParagraphElement: 'readonly',
				FileList: 'readonly',
				File: 'readonly',
				CustomEvent: 'readonly',
				HTMLSelectElement: 'readonly',
				HTMLSpanElement: 'readonly',
				HTMLTableCellElement: 'readonly',
				HTMLTableRowElement: 'readonly',
				ResizeObserver: 'readonly',
				Node: 'readonly',
				process: 'readonly',
				Buffer: 'readonly',
				global: 'readonly',
				App: 'readonly'
			}
		},
		plugins: {
			svelte,
			'@typescript-eslint': tsPlugin
		},
		rules: {
			'no-unused-vars': 'off',
			'@typescript-eslint/no-unused-vars': [
				'warn',
				{
					argsIgnorePattern: '^_',
					varsIgnorePattern: '^_',
					args: 'none'
				}
			],
			'svelte/valid-compile': 'warn'
		}
	},
	{
		// Ignore generated files and vendor code
		ignores: [
			'**/.svelte-kit/**',
			'**/build/**',
			'**/dist/**',
			'**/node_modules/**',
			'**/*.config.js',
			'**/*.config.ts'
		]
	}
];
