import { describe, expect, it } from 'vitest';
import {
	SIDEBAR_SWIPE_CONFIG,
	resolveSidebarSwipeAction,
	supportsSidebarSwipeGestures
} from '$lib/utils/sidebarSwipe';

describe('resolveSidebarSwipeAction', () => {
	it('collapses when swiping left on an expanded sidebar', () => {
		const action = resolveSidebarSwipeAction({
			startX: 360,
			endX: 240,
			startY: 140,
			endY: 144,
			durationMs: 180,
			startedNearLeadingEdge: false,
			isSidebarCollapsed: false
		});

		expect(action).toBe('collapse');
	});

	it('expands when swiping right from the leading edge on a collapsed sidebar', () => {
		const action = resolveSidebarSwipeAction({
			startX: 24,
			endX: 130,
			startY: 260,
			endY: 262,
			durationMs: 220,
			startedNearLeadingEdge: true,
			isSidebarCollapsed: true
		});

		expect(action).toBe('expand');
	});

	it('ignores swipe-right gestures that do not start from the leading edge', () => {
		const action = resolveSidebarSwipeAction({
			startX: 100,
			endX: 200,
			startY: 220,
			endY: 228,
			durationMs: 170,
			startedNearLeadingEdge: false,
			isSidebarCollapsed: true
		});

		expect(action).toBe('none');
	});

	it('ignores gestures with excessive vertical movement', () => {
		const action = resolveSidebarSwipeAction({
			startX: 320,
			endX: 200,
			startY: 100,
			endY: 180,
			durationMs: 140,
			startedNearLeadingEdge: true,
			isSidebarCollapsed: false
		});

		expect(action).toBe('none');
	});

	it('ignores gestures that take too long', () => {
		const action = resolveSidebarSwipeAction({
			startX: 320,
			endX: 160,
			startY: 100,
			endY: 105,
			durationMs: SIDEBAR_SWIPE_CONFIG.maxDurationMs + 1,
			startedNearLeadingEdge: true,
			isSidebarCollapsed: false
		});

		expect(action).toBe('none');
	});
});

describe('supportsSidebarSwipeGestures', () => {
	it('enables gestures for touch tablet viewport sizes', () => {
		expect(supportsSidebarSwipeGestures(1024, 5)).toBe(true);
	});

	it('disables gestures when viewport is not tablet-sized', () => {
		expect(supportsSidebarSwipeGestures(600, 5)).toBe(false);
		expect(supportsSidebarSwipeGestures(1440, 5)).toBe(false);
	});

	it('disables gestures on non-touch devices', () => {
		expect(supportsSidebarSwipeGestures(1024, 0)).toBe(false);
	});
});
