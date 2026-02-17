import { browser } from '$app/environment';

/**
 * Determine whether the current user agent is an iPhone.
 *
 * @param userAgent Optional user agent override for tests.
 * @returns True when the user agent indicates iPhone.
 */
export function isIPhoneDevice(userAgent?: string): boolean {
	const ua =
		typeof userAgent === 'string'
			? userAgent
			: browser && typeof navigator !== 'undefined'
				? navigator.userAgent
				: '';
	return /\biPhone\b/i.test(ua);
}
