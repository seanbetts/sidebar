<script lang="ts">
  let { error, status } = $props();
</script>

<svelte:head>
  <title>Something went wrong</title>
</svelte:head>

<div class="flex min-h-screen items-center justify-center bg-slate-50 px-6">
  <div class="w-full max-w-xl rounded-2xl border border-slate-200 bg-white p-8 shadow-sm">
    <p class="text-sm font-semibold uppercase tracking-wide text-slate-500">Error</p>
    <h1 class="mt-3 text-2xl font-semibold text-slate-900">
      {status ?? 500} — Something went wrong
    </h1>
    <p class="mt-3 text-sm text-slate-600">
      {error?.message ?? 'We hit an unexpected error. Please refresh and try again.'}
    </p>
  </div>
</div>
