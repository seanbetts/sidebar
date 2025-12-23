<script lang="ts">
  import { Collapsible as CollapsiblePrimitive } from "bits-ui";

  let { ...restProps }: CollapsiblePrimitive.ContentProps = $props();
</script>

<CollapsiblePrimitive.Content {...restProps}>
  <slot />
</CollapsiblePrimitive.Content>
