import js from '@eslint/js';
import tsPlugin from '@typescript-eslint/eslint-plugin';
import tsParser from '@typescript-eslint/parser';
import jsdoc from 'eslint-plugin-jsdoc';

export default [
  js.configs.recommended,
  {
    files: ['**/*.ts', '**/*.js'],
    plugins: {
      '@typescript-eslint': tsPlugin,
      jsdoc
    },
    languageOptions: {
      parser: tsParser,
      parserOptions: {
        ecmaVersion: 2022,
        sourceType: 'module',
        project: './tsconfig.json'
      }
    },
    rules: {
      // JSDoc rules
      'jsdoc/check-alignment': 'warn',
      'jsdoc/check-param-names': 'warn',
      'jsdoc/check-tag-names': 'warn',
      'jsdoc/check-types': 'warn',
      'jsdoc/require-description': 'warn',
      'jsdoc/require-param': 'warn',
      'jsdoc/require-param-description': 'warn',
      'jsdoc/require-param-type': 'off', // TypeScript handles this
      'jsdoc/require-returns': 'warn',
      'jsdoc/require-returns-description': 'warn',
      'jsdoc/require-returns-type': 'off', // TypeScript handles this

      // Require JSDoc for exported functions/classes
      'jsdoc/require-jsdoc': [
        'warn',
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
    },
    settings: {
      jsdoc: {
        mode: 'typescript',
        tagNamePreference: {
          returns: 'returns'
        }
      }
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
