import { beforeEach, describe, expect, it, vi } from 'vitest';

describe('theme utilities', () => {
	beforeEach(() => {
		localStorage.clear();
		document.documentElement.classList.remove('dark');

		Object.defineProperty(window, 'matchMedia', {
			writable: true,
			value: vi.fn().mockImplementation((query: string) => ({
				matches: query === '(prefers-color-scheme: dark)',
				media: query,
				onchange: null,
				addEventListener: vi.fn(),
				removeEventListener: vi.fn(),
				addListener: vi.fn(),
				removeListener: vi.fn(),
				dispatchEvent: vi.fn()
			}))
		});
	});

	it('reads system as a stored theme mode', async () => {
		localStorage.setItem('theme', 'dark');
		const { getStoredTheme } = await import('$lib/utils/theme');

		expect(getStoredTheme()).toBe('dark');
	});

	it('reads the system theme when no preference is stored', async () => {
		const { getSystemTheme } = await import('$lib/utils/theme');

		expect(getSystemTheme()).toBe('dark');
	});
});
