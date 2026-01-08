<script lang="ts">
	import { Collapsible as CollapsiblePrimitive } from 'bits-ui';

	let { children, ...restProps }: CollapsiblePrimitive.TriggerProps = $props();
</script>

<CollapsiblePrimitive.Trigger {...restProps}>
	{@render children?.()}
</CollapsiblePrimitive.Trigger>
