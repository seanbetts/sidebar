<script lang="ts">
	import {
		AlertDialog,
		AlertDialogAction,
		AlertDialogContent,
		AlertDialogDescription,
		AlertDialogFooter,
		AlertDialogHeader,
		AlertDialogTitle
	} from '$lib/components/ui/alert-dialog';
	import type { TaskSyncConflict } from '$lib/types/tasks';

	export let conflict: TaskSyncConflict | null = null;
	export let onKeepLocal: (conflict: TaskSyncConflict) => void;

	$: open = conflict !== null;

	function formatTimestamp(value?: string | null): string {
		if (!value) return 'Unknown';
		try {
			return new Intl.DateTimeFormat(undefined, {
				dateStyle: 'medium',
				timeStyle: 'short'
			}).format(new Date(value));
		} catch {
			return value;
		}
	}
</script>

<AlertDialog bind:open>
	<AlertDialogContent class="task-conflict-dialog">
		{#if conflict}
			<AlertDialogHeader>
				<AlertDialogTitle>Task conflict</AlertDialogTitle>
				<AlertDialogDescription>
					"{conflict.serverTask?.title ?? 'This task'}" was changed in another location. Your most
					recent edit on this device will be kept automatically.
				</AlertDialogDescription>
			</AlertDialogHeader>

			<div class="conflict-versions">
				<div class="conflict-version">
					<div class="conflict-version-label">Their version</div>
					<div class="conflict-version-title">{conflict.serverTask?.title ?? '—'}</div>
					{#if conflict.serverUpdatedAt}
						<div class="conflict-version-time">
							Updated {formatTimestamp(conflict.serverUpdatedAt)}
						</div>
					{/if}
				</div>
				<div class="conflict-divider">vs</div>
				<div class="conflict-version">
					<div class="conflict-version-label">Your version</div>
					<div class="conflict-version-title conflict-version-local">
						{conflict.serverTask?.title ?? '—'}
					</div>
					{#if conflict.clientUpdatedAt}
						<div class="conflict-version-time">
							Updated {formatTimestamp(conflict.clientUpdatedAt)}
						</div>
					{/if}
				</div>
			</div>

			<AlertDialogFooter>
				<AlertDialogAction onclick={() => conflict && onKeepLocal(conflict)}>
					Keep my version
				</AlertDialogAction>
			</AlertDialogFooter>
		{/if}
	</AlertDialogContent>
</AlertDialog>

<style>
	:global(.task-conflict-dialog) {
		max-width: 480px;
	}

	.conflict-versions {
		display: flex;
		align-items: center;
		gap: 0.75rem;
		margin-top: 1rem;
	}

	.conflict-version {
		flex: 1;
		display: flex;
		flex-direction: column;
		gap: 0.25rem;
		padding: 0.75rem;
		border: 1px solid var(--color-border);
		border-radius: 0.75rem;
		background: var(--color-sidebar-accent);
		min-width: 0;
	}

	.conflict-version-label {
		font-size: 0.7rem;
		font-weight: 600;
		text-transform: uppercase;
		letter-spacing: 0.06em;
		color: var(--color-muted-foreground);
	}

	.conflict-version-title {
		font-size: 0.85rem;
		font-weight: 500;
		color: var(--color-foreground);
		word-break: break-word;
	}

	.conflict-version-local {
		color: var(--color-primary);
	}

	.conflict-version-time {
		font-size: 0.72rem;
		color: var(--color-muted-foreground);
	}

	.conflict-divider {
		font-size: 0.75rem;
		font-weight: 600;
		color: var(--color-muted-foreground);
		text-transform: uppercase;
		flex-shrink: 0;
	}
</style>
