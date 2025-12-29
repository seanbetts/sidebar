<script lang="ts">
  import { Collapsible as CollapsiblePrimitive } from "bits-ui";

  let { children, ...restProps }: CollapsiblePrimitive.ContentProps & {
    children?: () => unknown;
  } = $props();
</script>

<CollapsiblePrimitive.Content {...restProps}>
  {@render children?.()}
</CollapsiblePrimitive.Content>
