<script lang="ts">
  import SidebarSectionHeader from '$lib/components/left-sidebar/SidebarSectionHeader.svelte';

  const onSearch = () => undefined;
  const onClear = () => undefined;
</script>

<SidebarSectionHeader
  title="Notes"
  searchPlaceholder="Search notes..."
  {onSearch}
  {onClear}
>
  <button slot="actions" class="panel-action">Add</button>
</SidebarSectionHeader>
