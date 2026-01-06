<script lang="ts">
  import { Plus } from 'lucide-svelte';
  import { websitesStore } from '$lib/stores/websites';
  import SidebarSectionHeader from '$lib/components/left-sidebar/SidebarSectionHeader.svelte';
  import WebsitesPanel from '$lib/components/websites/WebsitesPanel.svelte';
  import { Button } from '$lib/components/ui/button';

  export let active = false;
  export let onNewWebsite: () => void;
</script>

<div class="panel-section" class:hidden={!active}>
  <SidebarSectionHeader
    title="Websites"
    searchPlaceholder="Search websites..."
    onSearch={(query) => websitesStore.search(query)}
    onClear={() => websitesStore.load(true)}
  >
    <svelte:fragment slot="actions">
      <Button
        size="icon"
        variant="ghost"
        class="panel-action"
        onclick={onNewWebsite}
        aria-label="Save website"
        title="Save website"
      >
        <Plus size={16} />
      </Button>
    </svelte:fragment>
  </SidebarSectionHeader>
  <div class="files-content websites-content">
    <WebsitesPanel />
  </div>
</div>

<style>
  .websites-content {
    overflow: hidden;
    flex: 1;
    min-height: 0;
    display: flex;
    flex-direction: column;
    height: 100%;
  }
</style>
