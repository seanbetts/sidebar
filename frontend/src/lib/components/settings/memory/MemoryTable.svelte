<script lang="ts">
  import {
    Table,
    TableBody,
    TableCell,
    TableHead,
    TableHeader,
    TableRow
  } from '$lib/components/ui/table';
  import { Pencil, Trash2 } from 'lucide-svelte';
  import type { Memory } from '$lib/types/memory';

  export let memories: Memory[] = [];
  export let draftById: Record<string, { name: string } | undefined> = {};
  export let displayName: (path: string) => string;
  export let onEdit: (memory: Memory) => void;
  export let onDelete: (memory: Memory) => void;
</script>

<div class="memory-table-wrapper">
  <Table class="memory-table">
    <colgroup>
      <col />
      <col style="width: 96px" />
      <col style="width: 64px" />
      <col style="width: 64px" />
    </colgroup>
    <TableHeader>
      <TableRow>
        <TableHead>Name</TableHead>
        <TableHead class="memory-col-updated">Updated</TableHead>
        <TableHead class="memory-col-action memory-col-action-head">Edit</TableHead>
        <TableHead class="memory-col-action memory-col-action-head">Delete</TableHead>
      </TableRow>
    </TableHeader>
    <TableBody>
      {#each memories as memory (memory.id)}
        <TableRow class="memory-row">
          <TableCell class="memory-name-cell">
            {draftById[memory.id]?.name ?? displayName(memory.path)}
          </TableCell>
          <TableCell class="memory-updated">
            {new Date(memory.updated_at).toLocaleDateString()}
          </TableCell>
          <TableCell class="memory-action-cell memory-col-action-cell">
            <button class="settings-button ghost icon" on:click={() => onEdit(memory)} aria-label="Edit memory">
              <Pencil size={14} />
            </button>
          </TableCell>
          <TableCell class="memory-action-cell memory-col-action-cell">
            <button class="settings-button ghost icon" on:click={() => onDelete(memory)} aria-label="Delete memory">
              <Trash2 size={14} />
            </button>
          </TableCell>
        </TableRow>
      {/each}
    </TableBody>
  </Table>
</div>

<style>
  .memory-table-wrapper {
    border: 1px solid var(--color-border);
    border-radius: 0.9rem;
    overflow: hidden;
    background: var(--color-card);
  }

  .memory-table {
    table-layout: fixed;
  }

  .memory-row {
    height: 68px;
  }

  .memory-name-cell {
    font-weight: 600;
    color: var(--color-foreground);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .memory-action-cell {
    display: flex;
    align-items: center;
    justify-content: center;
  }

  .memory-updated {
    color: var(--color-muted-foreground);
    font-size: 0.78rem;
    white-space: nowrap;
  }

  .memory-col-updated {
    width: 96px;
  }

  :global(.memory-col-action) {
    width: 64px;
    min-width: 64px;
    padding: 0.2rem 0.2rem !important;
    text-align: center;
  }

  :global(.memory-col-action-head) {
    text-align: center;
    padding: 0.2rem 0.2rem !important;
  }

  :global(.memory-action-cell),
  :global(.memory-col-action-cell) {
    text-align: center;
    padding: 0.2rem 0.2rem !important;
    min-width: 64px;
  }

  :global(.memory-action-cell .settings-button.icon) {
    padding: 0.2rem;
    width: 28px;
    height: 28px;
  }

  :global(.memory-action-cell .settings-button.ghost) {
    padding: 0.2rem;
  }

  @media (max-width: 720px) {
    :global(.memory-table th:nth-child(2)),
    :global(.memory-table td:nth-child(2)) {
      display: none;
    }
  }
</style>
