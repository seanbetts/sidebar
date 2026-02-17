/**
 * Standard loading indicator sizes (in CSS pixels) used across the app.
 */
export const LOADING_SIZES = {
	inline: 16,
	control: 20,
	panel: 24,
	page: 32,
	extension: 44,
	hero: 128
} as const;

export type LoadingSizeKey = keyof typeof LOADING_SIZES;
