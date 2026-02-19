/**
 * Check whether a user agent string belongs to an iPhone browser.
 * @param userAgent Browser user agent string.
 * @returns True when the user agent identifies as iPhone.
 */
export function isIPhoneUserAgent(userAgent: string): boolean {
	return /\biPhone\b/i.test(userAgent);
}
