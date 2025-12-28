<script lang="ts">
  import { MessageSquare, FileText, Globe, Menu, FolderOpen } from 'lucide-svelte';
  import type { SidebarSection } from '$lib/hooks/useSidebarSectionLoader';

  export let isCollapsed = false;
  export let profileImageSrc = '';
  export let sidebarLogoSrc = '/images/logo.svg';
  export let onToggle: (() => void) | undefined;
  export let onOpenSection: ((section: SidebarSection) => void) | undefined;
  export let onOpenSettings: (() => void) | undefined;
  export let onProfileImageError: (() => void) | undefined;
</script>

<div class="sidebar-rail">
  <button
    class="rail-toggle"
    on:click={onToggle}
    aria-label={isCollapsed ? 'Expand sidebar' : 'Collapse sidebar'}
    title={isCollapsed ? 'Expand sidebar' : 'Collapse sidebar'}
  >
    <Menu size={20} />
  </button>

  <div class="rail-actions">
    <button
      on:click={() => onOpenSection?.('notes')}
      class="rail-btn"
      aria-label="Notes"
      title="Notes"
    >
      <FileText size={18} />
    </button>
    <button
      on:click={() => onOpenSection?.('websites')}
      class="rail-btn"
      aria-label="Websites"
      title="Websites"
    >
      <Globe size={18} />
    </button>
    <button
      on:click={() => onOpenSection?.('workspace')}
      class="rail-btn"
      aria-label="Files"
      title="Files"
    >
      <FolderOpen size={18} />
    </button>
    <button
      on:click={() => onOpenSection?.('history')}
      class="rail-btn"
      aria-label="Chat"
      title="Chat"
    >
      <MessageSquare size={18} />
    </button>
  </div>

  <div class="rail-footer">
    <button
      on:click={onOpenSettings}
      class="rail-btn rail-btn-avatar"
      aria-label="Open settings"
      title="Settings"
    >
      {#if profileImageSrc}
        <img
          class="rail-avatar"
          src={profileImageSrc}
          alt="Profile"
          on:error={onProfileImageError}
        />
      {:else}
        <img class="rail-avatar rail-avatar-logo" src={sidebarLogoSrc} alt="App logo" />
      {/if}
    </button>
  </div>
</div>

<style>
  .sidebar-rail {
    width: 56px;
    display: flex;
    flex-direction: column;
    align-items: center;
    padding: 0.75rem 0.5rem;
    border-right: 1px solid var(--color-sidebar-border);
    background-color: var(--color-sidebar);
    gap: 0.75rem;
  }

  .rail-toggle {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 40px;
    height: 40px;
    border-radius: 0.5rem;
    border: 1px solid var(--color-sidebar-border);
    background-color: transparent;
    color: var(--color-sidebar-foreground);
    cursor: pointer;
    transition: background-color 0.2s ease, border-color 0.2s ease;
  }

  .rail-toggle:hover {
    background-color: var(--color-sidebar-accent);
  }

  .rail-actions {
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
    align-items: center;
    flex: 1;
    width: 100%;
  }

  .rail-btn {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 40px;
    height: 40px;
    border-radius: 0.5rem;
    border: 1px solid transparent;
    background-color: transparent;
    color: var(--color-sidebar-foreground);
    cursor: pointer;
    transition: background-color 0.2s ease, border-color 0.2s ease;
  }

  .rail-btn:hover {
    background-color: var(--color-sidebar-accent);
  }

  .rail-footer {
    display: flex;
    justify-content: center;
  }

  .rail-btn-avatar {
    padding: 0.35rem;
  }

  .rail-avatar {
    width: 24px;
    height: 24px;
    border-radius: 50%;
    object-fit: cover;
  }

  .rail-avatar-logo {
    padding: 3px;
    object-fit: contain;
  }

  :global(.dark) .rail-avatar-logo {
    filter: invert(1);
  }
</style>
