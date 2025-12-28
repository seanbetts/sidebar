<script lang="ts">
  import ChatWindow from './ChatWindow.svelte';
</script>

<div class="chat-sidebar">
  <ChatWindow />
</div>

<style>
  .chat-sidebar {
    width: 100%;
    height: 100%;
    background-color: var(--color-background);
    overflow: hidden;
    min-height: 0;
  }
</style>
