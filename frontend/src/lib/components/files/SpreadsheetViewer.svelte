<script lang="ts">
  import { onDestroy } from 'svelte';
  import { browser } from '$app/environment';

  export let src: string | null = null;
  export let filename = 'sheet';
  export let registerActions:
    | ((actions: { copy: () => void; download: () => void }) => void)
    | null = null;

  type SheetPayload = {
    name: string;
    rows: string[][];
    header_row: number | null;
  };

  type SpreadsheetPayload = {
    sheets: SheetPayload[];
  };

  let data: SpreadsheetPayload | null = null;
  let loading = false;
  let error = '';
  let lastSrc: string | null = null;
  let activeSheetIndex = 0;
  let filterText = '';
  let sortColumn: number | null = null;
  let sortDirection: 'asc' | 'desc' = 'asc';
  let scrollElement: HTMLDivElement | null = null;
  let resizeObserver: ResizeObserver | null = null;
  let scrollTop = 0;
  let scrollLeft = 0;
  let viewportHeight = 0;
  const rowHeight = 32;
  const overscan = 8;

  $: sheets = data?.sheets ?? [];
  $: if (activeSheetIndex >= sheets.length) {
    activeSheetIndex = 0;
  }
  $: activeSheet = sheets[activeSheetIndex];
  $: rawRows = activeSheet?.rows ?? [];
  $: headerRowIndex = activeSheet?.header_row ?? null;
  $: headerRow =
    headerRowIndex !== null && rawRows[headerRowIndex] ? rawRows[headerRowIndex] : [];
  $: columnCount = rawRows.reduce((max, row) => Math.max(max, row.length), headerRow.length);
  $: columns =
    headerRowIndex !== null && headerRow.some((value) => value && value.trim())
      ? headerRow.map((value, index) => value?.trim() || `Column ${index + 1}`)
      : Array.from({ length: columnCount }, (_, index) => `Column ${index + 1}`);
  $: dataRows = rawRows.filter((_, index) => index !== headerRowIndex);
  $: filteredRows =
    filterText.trim().length === 0
      ? dataRows
      : dataRows.filter((row) =>
          row.join(' ').toLowerCase().includes(filterText.trim().toLowerCase())
        );
  $: sortedRows =
    sortColumn === null
      ? filteredRows
      : [...filteredRows].sort((a, b) => {
          const left = (a[sortColumn] ?? '').toString();
          const right = (b[sortColumn] ?? '').toString();
          const comparison = left.localeCompare(right, undefined, { numeric: true });
          return sortDirection === 'asc' ? comparison : -comparison;
        });

  $: if (browser && src && src !== lastSrc) {
    lastSrc = src;
    loadData(src);
  }

  $: if (browser && scrollElement && !resizeObserver) {
    resizeObserver = new ResizeObserver(() => updateViewport());
    resizeObserver.observe(scrollElement);
    updateViewport();
  }

  $: totalSize = sortedRows.length * rowHeight;
  $: startIndex = Math.max(0, Math.floor(scrollTop / rowHeight) - overscan);
  $: endIndex = Math.min(
    sortedRows.length,
    Math.ceil((scrollTop + viewportHeight) / rowHeight) + overscan
  );
  $: visibleRows = sortedRows
    .slice(startIndex, endIndex)
    .map((row, offset) => ({ row, index: startIndex + offset }));

  function updateViewport() {
    if (!scrollElement) return;
    viewportHeight = scrollElement.clientHeight;
  }

  function handleScroll() {
    if (!scrollElement) return;
    scrollTop = scrollElement.scrollTop;
    scrollLeft = scrollElement.scrollLeft;
    viewportHeight = scrollElement.clientHeight;
  }

  $: if (scrollElement) {
    filterText;
    scrollTop = 0;
    scrollLeft = 0;
    scrollElement.scrollTop = 0;
    scrollElement.scrollLeft = 0;
  }

  async function loadData(url: string) {
    loading = true;
    error = '';
    data = null;
    try {
      const response = await fetch(url, { credentials: 'include' });
      if (!response.ok) {
        throw new Error('Failed to load spreadsheet');
      }
      const payload = (await response.json()) as SpreadsheetPayload;
      data = payload;
      activeSheetIndex = 0;
      sortColumn = null;
      sortDirection = 'asc';
      scrollTop = 0;
      scrollLeft = 0;
      if (scrollElement) {
        scrollElement.scrollTop = 0;
        scrollElement.scrollLeft = 0;
      }
    } catch (err) {
      console.error('Failed to load spreadsheet data:', err);
      error = 'Failed to load spreadsheet data.';
    } finally {
      loading = false;
    }
  }

  function selectSheet(index: number) {
    activeSheetIndex = index;
    sortColumn = null;
    sortDirection = 'asc';
    scrollTop = 0;
    scrollLeft = 0;
    if (scrollElement) {
      scrollElement.scrollTop = 0;
      scrollElement.scrollLeft = 0;
    }
  }

  function toggleSort(columnIndex: number) {
    if (sortColumn === columnIndex) {
      sortDirection = sortDirection === 'asc' ? 'desc' : 'asc';
    } else {
      sortColumn = columnIndex;
      sortDirection = 'asc';
    }
    scrollTop = 0;
    scrollLeft = 0;
    if (scrollElement) {
      scrollElement.scrollTop = 0;
      scrollElement.scrollLeft = 0;
    }
  }

  function buildExportRows(): string[][] {
    if (!activeSheet) return [];
    if (headerRowIndex !== null) {
      return rawRows;
    }
    return [columns, ...dataRows];
  }

  function toCsv(rows: string[][]): string {
    return rows
      .map((row) =>
        row
          .map((cell) => {
            const value = cell ?? '';
            if (value.includes('"') || value.includes(',') || value.includes('\n')) {
              return `"${value.replace(/"/g, '""')}"`;
            }
            return value;
          })
          .join(',')
      )
      .join('\n');
  }

  function downloadCsv() {
    const rows = buildExportRows();
    if (!rows.length) return;
    const sheetName = activeSheet?.name || 'Sheet1';
    const csv = toCsv(rows);
    const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = `${filename}-${sheetName}.csv`;
    link.click();
    URL.revokeObjectURL(url);
  }

  async function copyCsv() {
    const rows = buildExportRows();
    if (!rows.length) return;
    const csv = toCsv(rows);
    try {
      await navigator.clipboard.writeText(csv);
    } catch (err) {
      console.error('Failed to copy CSV:', err);
    }
  }

  $: if (registerActions) {
    registerActions({ copy: copyCsv, download: downloadCsv });
  }

  onDestroy(() => {
    resizeObserver?.disconnect();
    resizeObserver = null;
  });
</script>

<div class="spreadsheet-viewer">
  {#if loading}
    <div class="spreadsheet-placeholder">Loading spreadsheet…</div>
  {:else if error}
    <div class="spreadsheet-placeholder">{error}</div>
  {:else if !activeSheet}
    <div class="spreadsheet-placeholder">No spreadsheet data available.</div>
  {:else}
    <div class="spreadsheet-controls">
      {#if sheets.length > 1}
        <div class="sheet-tabs">
          {#each sheets as sheet, index}
            <button
              class="sheet-tab"
              class:active={index === activeSheetIndex}
              onclick={() => selectSheet(index)}
            >
              {sheet.name || `Sheet ${index + 1}`}
            </button>
          {/each}
        </div>
      {/if}
      <div class="sheet-filter">
        <input
          type="text"
          placeholder="Filter rows…"
          bind:value={filterText}
        />
        <span>{sortedRows.length} rows</span>
      </div>
    </div>
    <div class="sheet-table" style={`--column-count: ${Math.max(columns.length, 1)};`}>
      <div class="sheet-header">
        <div class="sheet-header-row" style={`transform: translateX(${-scrollLeft}px);`}>
          {#each columns as column, index}
            <button
              class="sheet-header-cell"
              class:sorted={sortColumn === index}
              onclick={() => toggleSort(index)}
              aria-label={`Sort by ${column}`}
            >
              <span>{column}</span>
              {#if sortColumn === index}
                <span class="sort-indicator">{sortDirection === 'asc' ? '▲' : '▼'}</span>
              {/if}
            </button>
          {/each}
        </div>
      </div>
      <div class="sheet-body" bind:this={scrollElement} onscroll={handleScroll}>
        <div class="sheet-spacer" style={`height: ${totalSize}px;`}>
          {#each visibleRows as item}
            <div
              class="sheet-row"
              style={`transform: translateY(${item.index * rowHeight}px);`}
            >
              {#each columns as _column, columnIndex}
                <div class="sheet-cell">
                  {item.row[columnIndex] ?? ''}
                </div>
              {/each}
            </div>
          {/each}
        </div>
      </div>
    </div>
  {/if}
</div>

<style>
  .spreadsheet-viewer {
    display: flex;
    flex-direction: column;
    height: 100%;
    gap: 0.75rem;
  }

  .spreadsheet-placeholder {
    color: var(--color-muted-foreground);
    font-size: 0.9rem;
    padding: 1rem;
  }

  .spreadsheet-controls {
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
  }

  .sheet-tabs {
    display: flex;
    gap: 0.4rem;
    flex-wrap: wrap;
  }

  .sheet-tab {
    padding: 0.3rem 0.6rem;
    border-radius: 999px;
    border: 1px solid var(--color-border);
    background: var(--color-sidebar-accent);
    font-size: 0.75rem;
    cursor: pointer;
  }

  .sheet-tab.active {
    border-color: var(--color-sidebar-primary);
    color: var(--color-sidebar-primary);
    background: var(--color-sidebar);
  }

  .sheet-filter {
    display: flex;
    align-items: center;
    gap: 0.75rem;
    flex-wrap: wrap;
  }

  .sheet-filter input {
    flex: 1;
    background: var(--color-background);
    border: 1px solid var(--color-border);
    border-radius: 0.5rem;
    padding: 0.35rem 0.6rem;
    font-size: 0.8rem;
  }

  .sheet-filter span {
    font-size: 0.75rem;
    color: var(--color-muted-foreground);
  }


  .sheet-table {
    display: flex;
    flex-direction: column;
    border: 1px solid var(--color-border);
    border-radius: 0.75rem;
    overflow: hidden;
    min-height: 0;
    flex: 0 1 auto;
    max-height: 60vh;
  }

  .sheet-header {
    display: grid;
    background: var(--color-sidebar-accent);
    border-bottom: 1px solid var(--color-border);
    position: sticky;
    top: 0;
    z-index: 1;
    overflow: hidden;
  }

  .sheet-header-row {
    display: grid;
    grid-template-columns: repeat(var(--column-count), minmax(140px, 1fr));
    min-width: 100%;
    width: max-content;
  }

  .sheet-header-cell {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 0.4rem;
    padding: 0.4rem 0.6rem;
    font-size: 0.75rem;
    border-right: 1px solid var(--color-border);
    background: transparent;
    cursor: pointer;
  }

  .sheet-header-cell:last-child {
    border-right: none;
  }

  .sheet-header-cell.sorted {
    color: var(--color-sidebar-primary);
  }

  .sort-indicator {
    font-size: 0.6rem;
  }

  .sheet-body {
    flex: 1;
    overflow: auto;
    position: relative;
    min-height: 0;
    max-height: 60vh;
  }

  .sheet-spacer {
    position: relative;
    width: 100%;
    min-width: 100%;
  }

  .sheet-row {
    position: absolute;
    left: 0;
    right: 0;
    display: grid;
    grid-template-columns: repeat(var(--column-count), minmax(140px, 1fr));
    border-bottom: 1px solid var(--color-border);
    background: var(--color-background);
    min-height: 32px;
    min-width: 100%;
    width: max-content;
  }

  .sheet-cell {
    padding: 0.35rem 0.6rem;
    font-size: 0.75rem;
    border-right: 1px solid var(--color-border);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .sheet-cell:last-child {
    border-right: none;
  }
</style>
