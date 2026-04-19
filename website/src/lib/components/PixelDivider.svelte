<script lang="ts">
  import { onMount } from 'svelte';

  type Props = {
    position?: 'top' | 'bottom';
    size?: number;
    gap?: number;
    opacity?: number;
  };

  let { position = 'top', size = 4, gap = 2, opacity }: Props = $props();

  let width = $state(0);

  onMount(() => {
    const updateWidth = () => {
      width = window.innerWidth;
    };

    updateWidth();
    window.addEventListener('resize', updateWidth);

    return () => {
      window.removeEventListener('resize', updateWidth);
    };
  });

  const stride = $derived(size + gap);
  const count = $derived(width > 0 ? Math.max(1, Math.floor((width + gap) / stride)) : 0);
</script>

<div
  class={`pixel-divider pixel-divider--${position}`}
  style={`--pixel-divider-size: ${size}px; --pixel-divider-gap: ${gap}px; --pixel-divider-opacity: ${
    opacity ?? 'var(--pixel-divider-opacity)'
  };`}
  aria-hidden="true"
>
  <div class="pixel-divider__track">
    {#each Array.from({ length: count }) as _}
      <span class="pixel-divider__pixel"></span>
    {/each}
  </div>
</div>

<style>
  .pixel-divider {
    position: absolute;
    left: 50%;
    z-index: 1;
    width: 100vw;
    transform: translateX(-50%);
    pointer-events: none;
    opacity: var(--pixel-divider-opacity);
  }

  .pixel-divider--top {
    top: 0;
  }

  .pixel-divider--bottom {
    bottom: 0;
  }

  .pixel-divider__track {
    display: flex;
    justify-content: center;
    gap: var(--pixel-divider-gap);
    width: 100%;
    height: var(--pixel-divider-size);
    overflow: hidden;
  }

  .pixel-divider__pixel {
    flex: 0 0 var(--pixel-divider-size);
    width: var(--pixel-divider-size);
    height: var(--pixel-divider-size);
    background: var(--color-foreground);
  }
</style>
