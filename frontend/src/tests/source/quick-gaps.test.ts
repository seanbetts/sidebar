import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const readSource = (path: string) => readFileSync(path, 'utf8');

describe('quick implementation gap source checks', () => {
	it('keeps sidebar loading placeholders static', () => {
		const source = readSource('src/lib/components/left-sidebar/SidebarLoading.svelte');

		expect(source).not.toContain('loading-shimmer');
		expect(source).not.toContain('@keyframes');
		expect(source).not.toContain('animation:');
	});

	it('uses the native-matched dark background value', () => {
		const source = readSource('src/app.css');

		expect(source).toContain('--background: oklch(0.065 0 0);');
		expect(source).not.toContain('--background: oklch(0.16 0 0);');
	});

	it('does not present a task conflict decision dialog', () => {
		const source = readSource('src/lib/components/tasks/TasksViewController.svelte');

		expect(source).not.toContain('TaskConflictDialog');
		expect(source).not.toContain('handleKeepLocal');
		expect(source).not.toContain('activeConflict');
	});
});
