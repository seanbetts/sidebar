export type ThemeMode = 'light' | 'dark';
export type ThemeSource = 'user' | 'weather' | 'ai' | 'system' | 'unknown';

/**
 * Apply a theme mode and optionally persist to localStorage.
 *
 * @param theme - Theme mode to apply.
 * @param persist - Whether to store the choice in localStorage.
 * @param source - Optional source label for debugging.
 */
export function applyThemeMode(theme: ThemeMode, persist: boolean, source?: ThemeSource): void {
	if (typeof document === 'undefined') {
		return;
	}
	const root = document.documentElement;
	if (theme === 'dark') {
		root.classList.add('dark');
		if (persist) {
			localStorage.setItem('theme', 'dark');
			localStorage.setItem('themeSource', source ?? 'unknown');
		}
	} else {
		root.classList.remove('dark');
		if (persist) {
			localStorage.setItem('theme', 'light');
			localStorage.setItem('themeSource', source ?? 'unknown');
		}
	}
	if (typeof window !== 'undefined') {
		window.dispatchEvent(new CustomEvent('themechange', { detail: { theme, source } }));
	}
}

/**
 * Set and persist a theme mode.
 *
 * @param theme - Theme mode to apply.
 * @param source - Optional source label for debugging.
 */
export function setThemeMode(theme: ThemeMode, source?: ThemeSource): void {
	applyThemeMode(theme, true, source);
}

/**
 * Read the stored theme preference from localStorage.
 *
 * @returns Stored theme mode or null when unset.
 */
export function getStoredTheme(): ThemeMode | null {
	const stored = localStorage.getItem('theme');
	if (stored === 'light' || stored === 'dark') {
		return stored;
	}
	return null;
}
