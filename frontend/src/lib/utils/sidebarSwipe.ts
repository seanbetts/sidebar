export type SidebarSwipeAction = 'none' | 'collapse' | 'expand';

export interface SidebarSwipeSample {
	startX: number;
	endX: number;
	startY: number;
	endY: number;
	durationMs: number;
	startedNearLeadingEdge: boolean;
	isSidebarCollapsed: boolean;
}

export interface SidebarSwipeConfig {
	minHorizontalDistancePx: number;
	maxVerticalDistancePx: number;
	maxDurationMs: number;
	edgeActivationPx: number;
}

/**
 * Thresholds for sidebar swipe gestures on touch tablets.
 */
export const SIDEBAR_SWIPE_CONFIG: SidebarSwipeConfig = {
	minHorizontalDistancePx: 72,
	maxVerticalDistancePx: 52,
	maxDurationMs: 500,
	edgeActivationPx: 48
};

/**
 * Decide whether a touch gesture should collapse or expand the sidebar.
 * @param sample Swipe measurement captured from touchstart/touchend events.
 * @param config Gesture thresholds.
 * @returns Swipe action for the sidebar.
 */
export function resolveSidebarSwipeAction(
	sample: SidebarSwipeSample,
	config: SidebarSwipeConfig = SIDEBAR_SWIPE_CONFIG
): SidebarSwipeAction {
	const deltaX = sample.endX - sample.startX;
	const verticalDistance = Math.abs(sample.endY - sample.startY);

	if (sample.durationMs > config.maxDurationMs) return 'none';
	if (verticalDistance > config.maxVerticalDistancePx) return 'none';

	if (!sample.isSidebarCollapsed && deltaX <= -config.minHorizontalDistancePx) {
		return 'collapse';
	}

	if (
		sample.isSidebarCollapsed &&
		sample.startedNearLeadingEdge &&
		deltaX >= config.minHorizontalDistancePx
	) {
		return 'expand';
	}

	return 'none';
}

/**
 * Enable sidebar swipe only on touch-enabled tablet-sized viewports.
 * @param viewportWidth Current viewport width in CSS pixels.
 * @param maxTouchPoints Browser touch capability.
 * @returns True when gestures should be active.
 */
export function supportsSidebarSwipeGestures(
	viewportWidth: number,
	maxTouchPoints: number
): boolean {
	const isTouchDevice = maxTouchPoints > 0;
	const isTabletWidth = viewportWidth >= 768 && viewportWidth <= 1366;
	return isTouchDevice && isTabletWidth;
}
