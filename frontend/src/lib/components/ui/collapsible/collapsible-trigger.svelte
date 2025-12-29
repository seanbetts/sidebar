<script lang="ts">
  import { Collapsible as CollapsiblePrimitive } from "bits-ui";

  let { children, ...restProps }: CollapsiblePrimitive.TriggerProps & {
    children?: () => unknown;
  } = $props();
</script>

<CollapsiblePrimitive.Trigger {...restProps}>
  {@render children?.()}
</CollapsiblePrimitive.Trigger>
