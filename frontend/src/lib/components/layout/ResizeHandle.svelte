<script lang="ts">
	import { onDestroy } from 'svelte';

	export let onResize: (width: number) => void;
	export let onReset: (() => void) | null = null;
	export let containerRef: HTMLElement;
	export let side: 'left' | 'right' = 'right';

	let isDragging = false;
	let startX = 0;
	let startWidth = 0;
	let activePointerId: number | null = null;

	function handlePointerDown(event: PointerEvent) {
		if (typeof window === 'undefined' || typeof document === 'undefined') {
			return;
		}
		if (!containerRef) return;
		isDragging = true;
		startX = event.clientX;
		startWidth = containerRef.getBoundingClientRect().width;
		activePointerId = event.pointerId;

		const target = event.currentTarget as HTMLElement | null;
		target?.setPointerCapture?.(event.pointerId);

		document.body.style.cursor = 'col-resize';
		document.body.style.userSelect = 'none';

		window.addEventListener('pointermove', handlePointerMove);
		window.addEventListener('pointerup', handlePointerUp);
	}

	function handleDoubleClick() {
		onReset?.();
	}

	function handlePointerMove(event: PointerEvent) {
		if (!isDragging) return;
		if (activePointerId !== null && event.pointerId !== activePointerId) return;

		const delta = side === 'right' ? startX - event.clientX : event.clientX - startX;
		const newWidth = startWidth + delta;
		onResize(newWidth);
	}

	function handlePointerUp(event: PointerEvent) {
		if (activePointerId !== null && event.pointerId !== activePointerId) return;
		isDragging = false;
		activePointerId = null;
		if (typeof window !== 'undefined' && typeof document !== 'undefined') {
			document.body.style.cursor = '';
			document.body.style.userSelect = '';
			window.removeEventListener('pointermove', handlePointerMove);
			window.removeEventListener('pointerup', handlePointerUp);
		}
	}

	onDestroy(() => {
		if (typeof window !== 'undefined') {
			window.removeEventListener('pointermove', handlePointerMove);
			window.removeEventListener('pointerup', handlePointerUp);
		}
	});
</script>

<div
	class="resize-handle"
	class:dragging={isDragging}
	on:pointerdown|preventDefault={handlePointerDown}
	on:dblclick={handleDoubleClick}
	role="separator"
	aria-orientation="vertical"
	aria-label="Resize sidebar"
></div>

<style>
	.resize-handle {
		position: relative;
		width: 8px;
		cursor: col-resize;
		flex-shrink: 0;
		display: flex;
		align-items: center;
		justify-content: center;
		background: transparent;
		transition: background-color 0.15s ease;
		border-right: 1px solid var(--color-border);
	}

	.resize-handle::after {
		content: '';
		width: 2px;
		height: 40px;
		background-color: var(--color-border);
		border-radius: 1px;
		transition: background-color 0.15s ease;
	}

	.resize-handle:hover {
		background-color: var(--color-accent);
	}

	.resize-handle:hover::after,
	.resize-handle.dragging::after {
		background-color: var(--color-primary);
	}

	.resize-handle.dragging {
		background-color: var(--color-primary);
	}
</style>
