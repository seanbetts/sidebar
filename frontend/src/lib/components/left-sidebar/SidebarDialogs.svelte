<script lang="ts">
	import NewNoteDialog from '$lib/components/left-sidebar/dialogs/NewNoteDialog.svelte';
	import NewFolderDialog from '$lib/components/left-sidebar/dialogs/NewFolderDialog.svelte';
	import NewWebsiteDialog from '$lib/components/left-sidebar/dialogs/NewWebsiteDialog.svelte';
	import SaveChangesDialog from '$lib/components/left-sidebar/dialogs/SaveChangesDialog.svelte';
	import SidebarErrorDialog from '$lib/components/left-sidebar/dialogs/SidebarErrorDialog.svelte';
	import TextInputDialog from '$lib/components/left-sidebar/dialogs/TextInputDialog.svelte';
	import NewTaskProjectDialog from '$lib/components/left-sidebar/dialogs/NewTaskProjectDialog.svelte';
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

	export let isNewTaskGroupDialogOpen = false;
	export let newTaskGroupName = '';
	export let isCreatingTaskGroup = false;
	export let createTaskGroupFromDialog: () => void | Promise<void>;

	export let isNewTaskProjectDialogOpen = false;
	export let newTaskProjectName = '';
	export let newTaskProjectGroupId = '';
	export let taskGroups: Array<{ id: string; title: string }> = [];
	export let isCreatingTaskProject = false;
	export let createTaskProjectFromDialog: () => void | Promise<void>;

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

<TextInputDialog
	bind:open={isNewTaskGroupDialogOpen}
	title="New group"
	description="Add a new group to organize your tasks."
	placeholder="Group name"
	bind:value={newTaskGroupName}
	confirmLabel="Create group"
	cancelLabel="Cancel"
	busyLabel="Creating..."
	isBusy={isCreatingTaskGroup}
	onConfirm={createTaskGroupFromDialog}
	onCancel={() => (isNewTaskGroupDialogOpen = false)}
/>

<NewTaskProjectDialog
	bind:open={isNewTaskProjectDialogOpen}
	bind:value={newTaskProjectName}
	bind:groupId={newTaskProjectGroupId}
	groups={taskGroups}
	isBusy={isCreatingTaskProject}
	onConfirm={createTaskProjectFromDialog}
	onCancel={() => (isNewTaskProjectDialogOpen = false)}
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
