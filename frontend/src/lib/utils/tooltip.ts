import { browser } from '$app/environment';

/**
 * Return true when hover tooltips should be enabled.
 * @returns True when a fine pointer and hover are available.
 */
export function canShowTooltips(): boolean {
	if (!browser || typeof window === 'undefined') return false;
	return window.matchMedia('(hover: hover) and (pointer: fine)').matches;
}
