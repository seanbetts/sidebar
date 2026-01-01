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
  const minimumRowHeight = 32;
  let baseRowsPerView = 1;
  let loadMorePages = 0;
  let lastPageResetKey = '';
  let tableWrapper: HTMLDivElement | null = null;
  let tableViewport: HTMLDivElement | null = null;
  let headerRef: HTMLTableSectionElement | null = null;
  let bodyRef: HTMLTableSectionElement | null = null;
  let resizeObserver: ResizeObserver | null = null;

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
  $: columnLabels =
    headerRowIndex !== null && headerRow.some((value) => value && value.trim())
      ? headerRow.map((value) => value?.trim() || '')
      : Array.from({ length: columnCount }, () => '');
  $: columnAriaLabels = Array.from({ length: columnCount }, (_, index) => {
    const label = columnLabels[index]?.trim();
    return label ? label : `Column ${index + 1}`;
  });
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

  $: {
    const key = `${activeSheetIndex}-${filterText}-${sortColumn}-${sortDirection}-${sortedRows.length}`;
    if (key !== lastPageResetKey) {
      lastPageResetKey = key;
      loadMorePages = 0;
    }
  }
  $: totalRows = sortedRows.length;
  $: rowsToShow = Math.min(
    totalRows,
    baseRowsPerView * Math.max(1, loadMorePages + 1)
  );
  $: visibleRows = sortedRows.slice(0, rowsToShow);

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
      loadMorePages = 0;
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
    loadMorePages = 0;
  }

  function toggleSort(columnIndex: number) {
    if (sortColumn === columnIndex) {
      sortDirection = sortDirection === 'asc' ? 'desc' : 'asc';
    } else {
      sortColumn = columnIndex;
      sortDirection = 'asc';
    }
    loadMorePages = 0;
  }

  function updateRowsPerPage() {
    if (!tableWrapper) return;
    const availableHeight = tableWrapper.clientHeight;
    if (!availableHeight) return;
    const headerHeight = headerRef?.getBoundingClientRect().height ?? 0;
    const usableHeight = Math.max(0, availableHeight - headerHeight);
    const nextRows = Math.max(1, Math.floor(usableHeight / minimumRowHeight));
    if (nextRows !== baseRowsPerView) {
      baseRowsPerView = nextRows;
      loadMorePages = 0;
    }
  }

  function buildExportRows(): string[][] {
    if (!activeSheet) return [];
    if (headerRowIndex !== null) {
      return rawRows;
    }
    return [columnLabels, ...dataRows];
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

  $: if (browser && tableWrapper && !resizeObserver) {
    resizeObserver = new ResizeObserver(() => updateRowsPerPage());
    resizeObserver.observe(tableWrapper);
  }

  $: if (browser && tableWrapper) {
    activeSheetIndex;
    filterText;
    sortColumn;
    sortDirection;
    updateRowsPerPage();
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
    <div class="sheet-pagination">
      <span>Rows 1-{rowsToShow} of {totalRows}</span>
      {#if rowsToShow < totalRows}
        <button class="sheet-page-button" onclick={() => loadMorePages += 1}>
          Load more
        </button>
      {/if}
    </div>
    <div class="sheet-table-wrapper" bind:this={tableWrapper}>
      <div class="sheet-table" style={`--column-count: ${Math.max(columnLabels.length, 1)};`}>
        <div class="sheet-table-scroll" bind:this={tableViewport}>
          <table class="sheet-table-inner">
          <thead bind:this={headerRef}>
            <tr>
              {#each columnLabels as column, index}
                <th>
                  <button
                    class="sheet-header-cell"
                    class:sorted={sortColumn === index}
                    onclick={() => toggleSort(index)}
                    aria-label={`Sort by ${columnAriaLabels[index]}`}
                  >
                    <span>{column}</span>
                    {#if sortColumn === index}
                      <span class="sort-indicator">{sortDirection === 'asc' ? '▲' : '▼'}</span>
                    {/if}
                  </button>
                </th>
              {/each}
            </tr>
          </thead>
          <tbody bind:this={bodyRef}>
            {#if visibleRows.length === 0}
              <tr>
                <td class="sheet-empty" colspan={Math.max(columnLabels.length, 1)}>
                  No rows to display.
                </td>
              </tr>
            {:else}
              {#each visibleRows as row}
                <tr>
                  {#each columnLabels as _column, columnIndex}
                    <td>{row[columnIndex] ?? ''}</td>
                  {/each}
                </tr>
              {/each}
            {/if}
          </tbody>
          </table>
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

  .sheet-pagination {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 0.75rem;
    font-size: 0.75rem;
    color: var(--color-muted-foreground);
  }

  .sheet-page-button {
    border: 1px solid var(--color-border);
    background: var(--color-sidebar-accent);
    border-radius: 0.5rem;
    padding: 0.25rem 0.6rem;
    font-size: 0.75rem;
    cursor: pointer;
  }

  .sheet-page-button:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .sheet-table {
    display: flex;
    flex-direction: column;
    border: 1px solid var(--color-border);
    border-radius: 0.5rem;
    overflow: hidden;
    min-height: 0;
    flex: 1 1 auto;
    height: 100%;
  }

  .sheet-table-wrapper {
    flex: 1 1 auto;
    min-height: 0;
  }

  .sheet-table-scroll {
    overflow-x: auto;
    overflow-y: auto;
    min-height: 0;
    height: 100%;
  }

  .sheet-table-inner {
    width: max(100%, calc(var(--column-count) * 140px));
    border-collapse: collapse;
    table-layout: fixed;
  }

  .sheet-table-inner th,
  .sheet-table-inner td {
    border-right: 1px solid var(--color-border);
    border-bottom: 1px solid var(--color-border);
    padding: 0.35rem 0.6rem;
    font-size: 0.75rem;
    vertical-align: middle;
    white-space: normal;
    word-break: break-word;
  }

  .sheet-table-inner tbody tr {
    height: 32px;
  }

  .sheet-table-inner th:last-child,
  .sheet-table-inner td:last-child {
    border-right: none;
  }

  .sheet-table-inner thead th {
    position: sticky;
    top: 0;
    background: var(--color-sidebar-accent);
    z-index: 1;
  }

  .sheet-header-cell {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 0.4rem;
    width: 100%;
    background: transparent;
    border: none;
    padding: 0;
    font-size: 0.75rem;
    cursor: pointer;
    text-align: left;
  }

  .sheet-header-cell.sorted {
    color: var(--color-sidebar-primary);
  }

  .sort-indicator {
    font-size: 0.6rem;
  }

  .sheet-empty {
    text-align: center;
    padding: 1rem;
    color: var(--color-muted-foreground);
  }
</style>
