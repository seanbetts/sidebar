/**
 * Invoke an `onclick` handler from snippet trigger props when present.
 * @param props Snippet props object from a trigger slot.
 * @param event Native click event to forward.
 */
export function invokeSnippetClick(props: unknown, event: Event): void {
	if (!props || typeof props !== 'object') return;
	const onclick = (props as { onclick?: unknown }).onclick;
	if (typeof onclick === 'function') {
		(onclick as (event: Event) => void)(event);
	}
}
