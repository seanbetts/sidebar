<script lang="ts">
  import ChatWindow from './ChatWindow.svelte';
</script>

<div class="chat-sidebar">
  <ChatWindow />
</div>

<style>
  .chat-sidebar {
    width: 400px;
    height: 100vh;
    border-left: 1px solid var(--color-border);
    background-color: var(--color-background);
    overflow: hidden;
  }
</style>
