<script lang="ts">
	import NewNoteDialog from '$lib/components/left-sidebar/dialogs/NewNoteDialog.svelte';
	import NewFolderDialog from '$lib/components/left-sidebar/dialogs/NewFolderDialog.svelte';
	import NewWebsiteDialog from '$lib/components/left-sidebar/dialogs/NewWebsiteDialog.svelte';
	import SaveChangesDialog from '$lib/components/left-sidebar/dialogs/SaveChangesDialog.svelte';
	import SidebarErrorDialog from '$lib/components/left-sidebar/dialogs/SidebarErrorDialog.svelte';
	import TextInputDialog from '$lib/components/left-sidebar/dialogs/TextInputDialog.svelte';
	import SettingsDialogContainer from '$lib/components/left-sidebar/panels/SettingsDialogContainer.svelte';

	export let isNewNoteDialogOpen = false;
	export let newNoteName = '';
	export let isCreatingNote = false;
	export let createNoteFromDialog: () => void | Promise<void>;

	export let isNewFolderDialogOpen = false;
	export let newFolderName = '';
	export let isCreatingFolder = false;
	export let createFolderFromDialog: () => void | Promise<void>;

	export let isNewWebsiteDialogOpen = false;
	export let newWebsiteUrl = '';
	export let isSavingWebsite = false;
	export let saveWebsiteFromDialog: () => void | Promise<void>;

	export let isErrorDialogOpen = false;
	export let errorTitle = 'Unable to complete action';
	export let errorMessage = 'Failed to create note. Please try again.';

	export let isYouTubeDialogOpen = false;
	export let youtubeUrl = '';
	export let isAddingYoutube = false;
	export let confirmAddYouTube: () => void | Promise<void>;

	export let isSaveChangesDialogOpen = false;
	export let confirmSaveAndSwitch: () => void | Promise<void>;
	export let discardAndSwitch: () => void | Promise<void>;

	export let isSettingsOpen = false;
	export let profileImageSrc = '';
	export let settingsDialog: { handleProfileImageError: () => void } | null = null;
</script>

<NewNoteDialog
	bind:open={isNewNoteDialogOpen}
	bind:value={newNoteName}
	isBusy={isCreatingNote}
	onConfirm={createNoteFromDialog}
	onCancel={() => (isNewNoteDialogOpen = false)}
/>

<NewFolderDialog
	bind:open={isNewFolderDialogOpen}
	bind:value={newFolderName}
	isBusy={isCreatingFolder}
	onConfirm={createFolderFromDialog}
	onCancel={() => (isNewFolderDialogOpen = false)}
/>

<NewWebsiteDialog
	bind:open={isNewWebsiteDialogOpen}
	bind:value={newWebsiteUrl}
	isBusy={isSavingWebsite}
	onConfirm={saveWebsiteFromDialog}
	onCancel={() => (isNewWebsiteDialogOpen = false)}
/>

<SidebarErrorDialog
	bind:open={isErrorDialogOpen}
	title={errorTitle}
	message={errorMessage}
	onConfirm={() => (isErrorDialogOpen = false)}
/>

<TextInputDialog
	bind:open={isYouTubeDialogOpen}
	title="Add YouTube video"
	description="Paste a YouTube URL to generate a transcript."
	placeholder="https://www.youtube.com/watch?v=..."
	bind:value={youtubeUrl}
	confirmLabel="Add video"
	cancelLabel="Cancel"
	busyLabel="Adding..."
	isBusy={isAddingYoutube}
	onConfirm={confirmAddYouTube}
	onCancel={() => (isYouTubeDialogOpen = false)}
/>

<SaveChangesDialog
	bind:open={isSaveChangesDialogOpen}
	onConfirm={confirmSaveAndSwitch}
	onCancel={discardAndSwitch}
/>

<SettingsDialogContainer
	bind:open={isSettingsOpen}
	bind:profileImageSrc
	bind:this={settingsDialog}
/>
