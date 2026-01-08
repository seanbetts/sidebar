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
			'jsdoc/check-param-names': 'error',
			'jsdoc/check-tag-names': 'error',
			'jsdoc/check-types': 'error',
			'jsdoc/require-description': 'error',
			'jsdoc/require-param': 'error',
			'jsdoc/require-param-description': 'error',
			'jsdoc/require-param-type': 'off',
			'jsdoc/require-returns': 'error',
			'jsdoc/require-returns-description': 'error',
			'jsdoc/require-returns-type': 'off',
			'jsdoc/require-jsdoc': [
				'error',
				{
					require: {
						FunctionDeclaration: true,
						MethodDefinition: true,
						ClassDeclaration: true,
						ArrowFunctionExpression: false,
						FunctionExpression: false
					},
					publicOnly: true,
					enableFixer: false
				}
			]
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
				localStorage: 'readonly',
				sessionStorage: 'readonly',
				crypto: 'readonly',
				window: 'readonly',
				document: 'readonly',
				navigator: 'readonly',
				// Node globals (for SSR)
				process: 'readonly',
				Buffer: 'readonly'
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
			}
		},
		plugins: {
			svelte
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
