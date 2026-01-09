<script lang="ts">
	import { onDestroy, onMount } from 'svelte';
	import { Plus, Folder, FileVideoCamera } from 'lucide-svelte';
	import { conversationListStore } from '$lib/stores/conversations';
	import { chatStore } from '$lib/stores/chat';
	import { editorStore, currentNoteId } from '$lib/stores/editor';
	import { treeStore } from '$lib/stores/tree';
	import { thingsStore } from '$lib/stores/things';
	import { websitesStore } from '$lib/stores/websites';
	import { dispatchCacheEvent } from '$lib/utils/cacheEvents';
	import { ingestionViewerStore } from '$lib/stores/ingestion-viewer';
	import ConversationList from './ConversationList.svelte';
	import NotesPanel from '$lib/components/left-sidebar/NotesPanel.svelte';
	import FilesPanel from '$lib/components/left-sidebar/FilesPanel.svelte';
	import SidebarWebsitesSection from '$lib/components/left-sidebar/SidebarWebsitesSection.svelte';
	import ThingsPanel from '$lib/components/left-sidebar/ThingsPanel.svelte';
	import { useSidebarSectionLoader, type SidebarSection } from '$lib/hooks/useSidebarSectionLoader';
	import { useIngestionUploads } from '$lib/hooks/useIngestionUploads';
	import SidebarRail from '$lib/components/left-sidebar/SidebarRail.svelte';
	import SidebarSectionHeader from '$lib/components/left-sidebar/SidebarSectionHeader.svelte';
	import SidebarDialogs from '$lib/components/left-sidebar/SidebarDialogs.svelte';
	import { Button } from '$lib/components/ui/button';
	import { Tooltip, TooltipContent, TooltipTrigger } from '$lib/components/ui/tooltip';
	import { TOOLTIP_COPY } from '$lib/constants/tooltips';
	import { sidebarSectionStore } from '$lib/stores/sidebar-section';
	import { logError } from '$lib/utils/errorHandling';
	import { canShowTooltips } from '$lib/utils/tooltip';

	let isCollapsed = false;
	let isErrorDialogOpen = false;
	let errorTitle = 'Unable to complete action';
	let errorMessage = 'Failed to create note. Please try again.';
	let isNewNoteDialogOpen = false;
	let newNoteName = '';
	let isNewFolderDialogOpen = false;
	let newFolderName = '';
	let isSettingsOpen = false;
	let isNewWebsiteDialogOpen = false;
	let newWebsiteUrl = '';
	let isSavingWebsite = false;
	let isCreatingNote = false;
	let isCreatingFolder = false;
	let isSaveChangesDialogOpen = false;
	let pendingNotePath: string | null = null;
	let settingsDialog: { handleProfileImageError: () => void } | null = null;
	let profileImageSrc = '';
	let isUploadingFile = false;
	let pendingUploadId: string | null = null;
	let isYouTubeDialogOpen = false;
	let youtubeUrl = '';
	let isAddingYoutube = false;
	let fileInput: HTMLInputElement | null = null;
	const sidebarLogoSrc = '/images/logo.svg';
	let isMounted = false;
	let tooltipsEnabled = false;
	let lastConversationId: string | null = null;
	let lastMessageCount = 0;
	const { loadSectionData } = useSidebarSectionLoader();
	const {
		handleUploadFileClick,
		handleFileSelected,
		handleAddYouTube,
		confirmAddYouTube,
		handlePendingUpload
	} = useIngestionUploads({
		getIsUploadingFile: () => isUploadingFile,
		setIsUploadingFile: (value) => {
			isUploadingFile = value;
		},
		getIsAddingYoutube: () => isAddingYoutube,
		setIsAddingYoutube: (value) => {
			isAddingYoutube = value;
		},
		getYouTubeUrl: () => youtubeUrl,
		setYouTubeUrl: (value) => {
			youtubeUrl = value;
		},
		setYouTubeDialogOpen: (value) => {
			isYouTubeDialogOpen = value;
		},
		setPendingUploadId: (value) => {
			pendingUploadId = value;
		},
		onError: (title, message) => {
			errorTitle = title;
			errorMessage = message;
			isErrorDialogOpen = true;
		}
	});
	$: isBlankChat = (() => {
		const currentId = $chatStore.conversationId;
		if (!currentId) return true;
		const current = $conversationListStore.conversations.find(
			(conversation) => conversation.id === currentId
		);
		return current ? current.messageCount === 0 : false;
	})();
	$: showNewChatButton = !isBlankChat;
	$: if ($chatStore.conversationId) {
		if (lastConversationId !== $chatStore.conversationId) {
			lastConversationId = $chatStore.conversationId;
			lastMessageCount = $chatStore.messages.length;
		} else if ($chatStore.messages.length !== lastMessageCount) {
			if (lastMessageCount === 0 && $chatStore.messages.length > 0 && activeSection !== 'history') {
				openSection('history');
			}
			lastMessageCount = $chatStore.messages.length;
		}
	}

	onMount(() => {
		// Mark as mounted to enable reactive data loading
		isMounted = true;
		sidebarSectionStore.set(activeSection);
		tooltipsEnabled = canShowTooltips();

		if (typeof window !== 'undefined') {
			window.addEventListener('keydown', handleSectionShortcut);
		}
	});

	onDestroy(() => {
		// Clean up event listener
		if (typeof window !== 'undefined') {
			window.removeEventListener('keydown', handleSectionShortcut);
		}
		chatStore.cleanup?.();
	});

	function handleSectionShortcut(event: KeyboardEvent) {
		const isModifier = event.metaKey || event.ctrlKey;
		if (!isModifier || event.shiftKey || event.altKey) {
			return;
		}

		if (event.key === '1') {
			event.preventDefault();
			openSection('notes');
		} else if (event.key === '2') {
			event.preventDefault();
			openSection('things');
		} else if (event.key === '3') {
			event.preventDefault();
			openSection('websites');
		} else if (event.key === '4') {
			event.preventDefault();
			openSection('workspace');
		} else if (event.key === '5') {
			event.preventDefault();
			openSection('history');
		}
	}

	async function handleNewChat() {
		await chatStore.startNewConversation();
	}

	function toggleSidebar() {
		isCollapsed = !isCollapsed;
	}

	let activeSection: SidebarSection = 'notes';

	function openSection(section: SidebarSection) {
		activeSection = section;
		sidebarSectionStore.set(section);
		isCollapsed = false;
	}

	// Lazy load section data when switching sections (only after mount to ensure stores are ready)
	$: if (isMounted && activeSection) {
		loadSectionData(activeSection);
	}

	async function handleNoteClick(path: string) {
		// Check if current note has unsaved changes
		if ($editorStore.isDirty && $editorStore.currentNoteId) {
			pendingNotePath = path;
			isSaveChangesDialogOpen = true;
			return;
		}

		// Load the new note
		websitesStore.clearActive();
		ingestionViewerStore.clearActive();
		currentNoteId.set(path);
		await editorStore.loadNote('notes', path, { source: 'user' });
	}

	async function confirmSaveAndSwitch() {
		if ($editorStore.currentNoteId) {
			await editorStore.saveNote();
		}
		isSaveChangesDialogOpen = false;
		if (pendingNotePath) {
			websitesStore.clearActive();
			ingestionViewerStore.clearActive();
			currentNoteId.set(pendingNotePath);
			await editorStore.loadNote('notes', pendingNotePath, { source: 'user' });
			pendingNotePath = null;
		}
	}

	async function discardAndSwitch() {
		isSaveChangesDialogOpen = false;
		if (pendingNotePath) {
			websitesStore.clearActive();
			ingestionViewerStore.clearActive();
			currentNoteId.set(pendingNotePath);
			await editorStore.loadNote('notes', pendingNotePath, { source: 'user' });
			pendingNotePath = null;
		}
	}

	async function handleNewNote() {
		websitesStore.clearActive();
		ingestionViewerStore.clearActive();
		newNoteName = '';
		isNewNoteDialogOpen = true;
	}

	function handleNewFolder() {
		websitesStore.clearActive();
		ingestionViewerStore.clearActive();
		newFolderName = '';
		isNewFolderDialogOpen = true;
	}
	$: if (pendingUploadId) {
		handlePendingUpload(pendingUploadId, (value) => {
			pendingUploadId = value;
		});
	}

	function handleNewWebsite() {
		newWebsiteUrl = '';
		isNewWebsiteDialogOpen = true;
	}

	async function saveWebsiteFromDialog() {
		const url = newWebsiteUrl.trim();
		if (!url || isSavingWebsite) return;

		isSavingWebsite = true;
		try {
			const response = await fetch('/api/v1/websites/save', {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({ url })
			});

			const data = await response.json();
			if (!response.ok) {
				const detail = data?.error;
				const message = typeof detail === 'string' ? detail : detail?.message;
				throw new Error(message || 'Failed to save website');
			}

			const websiteId = data?.data?.id;

			dispatchCacheEvent('website.saved');
			if (websiteId) {
				ingestionViewerStore.clearActive();
				editorStore.reset();
				currentNoteId.set(null);
				await websitesStore.loadById(websiteId);
			}
			isNewWebsiteDialogOpen = false;
		} catch (error) {
			logError('Failed to save website', error, { scope: 'Sidebar' });
			errorTitle = 'Unable to save website';
			errorMessage =
				error instanceof Error && error.message
					? error.message
					: 'Failed to save website. Please try again.';
			isErrorDialogOpen = true;
		} finally {
			isSavingWebsite = false;
		}
	}

	async function createNoteFromDialog() {
		const name = newNoteName.trim();
		if (!name || isCreatingNote) return;
		const filename = name.endsWith('.md') ? name : `${name}.md`;

		isCreatingNote = true;
		try {
			const response = await fetch('/api/v1/notes', {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({
					path: filename,
					content: `# ${name}\n\n`
				})
			});

			if (!response.ok) throw new Error('Failed to create note');
			const data = await response.json();
			const noteId = data?.id || filename;

			const folder = filename.includes('/') ? filename.split('/').slice(0, -1).join('/') : '';
			treeStore.addNoteNode?.({
				id: noteId,
				name: filename,
				folder,
				modified: data?.modified
			});
			dispatchCacheEvent('note.created');
			websitesStore.clearActive();
			ingestionViewerStore.clearActive();
			currentNoteId.set(noteId);
			await editorStore.loadNote('notes', noteId, { source: 'user' });
			isNewNoteDialogOpen = false;
		} catch (error) {
			logError('Failed to create note', error, { scope: 'Sidebar', noteName: filename });
			errorTitle = 'Unable to create note';
			errorMessage = 'Failed to create note. Please try again.';
			isErrorDialogOpen = true;
		} finally {
			isCreatingNote = false;
		}
	}

	async function createFolderFromDialog() {
		const name = newFolderName.trim().replace(/^\/+|\/+$/g, '');
		if (!name || isCreatingFolder) return;

		isCreatingFolder = true;
		try {
			const response = await fetch('/api/v1/notes/folders', {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({ path: name })
			});

			if (!response.ok) throw new Error('Failed to create folder');
			treeStore.addFolderNode?.(name);
			dispatchCacheEvent('note.created');
			isNewFolderDialogOpen = false;
		} catch (error) {
			logError('Failed to create folder', error, { scope: 'Sidebar', folderName: name });
			errorTitle = 'Unable to create folder';
			errorMessage = 'Failed to create folder. Please try again.';
			isErrorDialogOpen = true;
		} finally {
			isCreatingFolder = false;
		}
	}
</script>

<SidebarDialogs
	bind:isNewNoteDialogOpen
	bind:newNoteName
	{isCreatingNote}
	{createNoteFromDialog}
	bind:isNewFolderDialogOpen
	bind:newFolderName
	{isCreatingFolder}
	{createFolderFromDialog}
	bind:isNewWebsiteDialogOpen
	bind:newWebsiteUrl
	{isSavingWebsite}
	{saveWebsiteFromDialog}
	bind:isErrorDialogOpen
	{errorTitle}
	{errorMessage}
	bind:isYouTubeDialogOpen
	bind:youtubeUrl
	{isAddingYoutube}
	{confirmAddYouTube}
	bind:isSaveChangesDialogOpen
	{confirmSaveAndSwitch}
	{discardAndSwitch}
	bind:isSettingsOpen
	bind:profileImageSrc
	bind:settingsDialog
/>

<div class="sidebar-shell" class:collapsed={isCollapsed}>
	<SidebarRail
		{isCollapsed}
		{activeSection}
		{profileImageSrc}
		{sidebarLogoSrc}
		onToggle={toggleSidebar}
		onOpenSection={openSection}
		onOpenSettings={() => (isSettingsOpen = true)}
		onProfileImageError={() => settingsDialog?.handleProfileImageError()}
	/>

	<div class="sidebar-panel" aria-hidden={isCollapsed}>
		<div class="panel-body">
			<!-- Notes Section -->
			<div class="panel-section" class:hidden={activeSection !== 'notes'}>
				<SidebarSectionHeader
					title="Notes"
					searchPlaceholder="Search notes..."
					onSearch={(query) => treeStore.searchNotes(query)}
					onClear={() => treeStore.load('notes', true)}
				>
					<svelte:fragment slot="actions">
						<Tooltip disabled={!tooltipsEnabled}>
							<TooltipTrigger>
								{#snippet child({ props })}
									<Button
										size="icon"
										variant="ghost"
										class="panel-action"
										{...props}
										onclick={(event) => {
											props.onclick?.(event);
											handleNewFolder(event);
										}}
										aria-label="New folder"
									>
										<Folder size={16} />
									</Button>
								{/snippet}
							</TooltipTrigger>
							<TooltipContent side="right">{TOOLTIP_COPY.newFolder}</TooltipContent>
						</Tooltip>
						<Tooltip disabled={!tooltipsEnabled}>
							<TooltipTrigger>
								{#snippet child({ props })}
									<Button
										size="icon"
										variant="ghost"
										class="panel-action"
										{...props}
										onclick={(event) => {
											props.onclick?.(event);
											handleNewNote(event);
										}}
										aria-label="New note"
									>
										<Plus size={16} />
									</Button>
								{/snippet}
							</TooltipTrigger>
							<TooltipContent side="right">{TOOLTIP_COPY.newNote}</TooltipContent>
						</Tooltip>
					</svelte:fragment>
				</SidebarSectionHeader>
				<div class="notes-content">
					<NotesPanel
						basePath="notes"
						emptyMessage="No notes found"
						hideExtensions={true}
						onFileClick={handleNoteClick}
					/>
				</div>
			</div>

			<SidebarWebsitesSection
				active={activeSection === 'websites'}
				onNewWebsite={handleNewWebsite}
			/>

			<!-- Things Section -->
			<div class="panel-section" class:hidden={activeSection !== 'things'}>
				<SidebarSectionHeader
					title="Tasks"
					searchPlaceholder="Search tasks..."
					onSearch={(query) => thingsStore.search(query)}
					onClear={() => thingsStore.clearSearch()}
				>
					<svelte:fragment slot="actions">
						<Tooltip disabled={!tooltipsEnabled}>
							<TooltipTrigger>
								{#snippet child({ props })}
									<Button
										size="icon"
										variant="ghost"
										class="panel-action"
										{...props}
										onclick={(event) => {
											props.onclick?.(event);
											thingsStore.startNewTask();
										}}
										aria-label="New task"
									>
										<Plus size={16} />
									</Button>
								{/snippet}
							</TooltipTrigger>
							<TooltipContent side="right">{TOOLTIP_COPY.newTask}</TooltipContent>
						</Tooltip>
					</svelte:fragment>
				</SidebarSectionHeader>
				<div class="things-content">
					<ThingsPanel />
				</div>
			</div>

			<!-- Workspace Section -->
			<div class="panel-section" class:hidden={activeSection !== 'workspace'}>
				<SidebarSectionHeader
					title="Files"
					searchPlaceholder="Search files..."
					onSearch={(query) => treeStore.searchFiles('documents', query)}
					onClear={() => treeStore.load('documents', true)}
				>
					<svelte:fragment slot="actions">
						<input
							type="file"
							bind:this={fileInput}
							onchange={handleFileSelected}
							class="file-upload-input"
						/>
						<Tooltip disabled={!tooltipsEnabled}>
							<TooltipTrigger>
								{#snippet child({ props })}
									<Button
										size="icon"
										variant="ghost"
										class="panel-action"
										{...props}
										onclick={(event) => {
											props.onclick?.(event);
											handleAddYouTube(event);
										}}
										aria-label="Add YouTube video"
										disabled={isAddingYoutube}
									>
										<FileVideoCamera size={16} />
									</Button>
								{/snippet}
							</TooltipTrigger>
							<TooltipContent side="right">{TOOLTIP_COPY.addYouTube}</TooltipContent>
						</Tooltip>
						<Tooltip disabled={!tooltipsEnabled}>
							<TooltipTrigger>
								{#snippet child({ props })}
									<Button
										size="icon"
										variant="ghost"
										class="panel-action"
										{...props}
										onclick={(event) => {
											props.onclick?.(event);
											handleUploadFileClick(fileInput);
										}}
										aria-label="Upload file"
										disabled={isUploadingFile}
									>
										<Plus size={16} />
									</Button>
								{/snippet}
							</TooltipTrigger>
							<TooltipContent side="right">{TOOLTIP_COPY.uploadFile}</TooltipContent>
						</Tooltip>
					</svelte:fragment>
				</SidebarSectionHeader>
				<div class="files-content">
					<FilesPanel />
				</div>
			</div>

			<!-- History Section -->
			<div class="panel-section" class:hidden={activeSection !== 'history'}>
				<SidebarSectionHeader
					title="Chat"
					searchPlaceholder="Search conversations..."
					onSearch={(query) => conversationListStore.search(query)}
					onClear={() => conversationListStore.load(true)}
				>
					<svelte:fragment slot="actions">
						{#if showNewChatButton}
							<Tooltip disabled={!tooltipsEnabled}>
								<TooltipTrigger>
									{#snippet child({ props })}
										<Button
											size="icon"
											variant="ghost"
											class="panel-action"
											{...props}
											onclick={(event) => {
												props.onclick?.(event);
												handleNewChat(event);
											}}
											aria-label="New chat"
										>
											<Plus size={16} />
										</Button>
									{/snippet}
								</TooltipTrigger>
								<TooltipContent side="right">{TOOLTIP_COPY.newChat}</TooltipContent>
							</Tooltip>
						{/if}
					</svelte:fragment>
				</SidebarSectionHeader>
				<div class="history-content">
					<ConversationList />
				</div>
			</div>
		</div>
	</div>
</div>

<style>
	.sidebar-shell {
		display: flex;
		height: 100%;
		min-height: 0;
		background-color: var(--color-sidebar);
		border-right: 1px solid var(--color-sidebar-border);
	}

	.sidebar-panel {
		width: 280px;
		display: flex;
		flex-direction: column;
		background-color: var(--color-sidebar);
		transition:
			width 0.2s ease,
			opacity 0.2s ease;
		overflow: hidden;
	}

	.sidebar-shell.collapsed .sidebar-panel {
		width: 0;
		opacity: 0;
		pointer-events: none;
	}

	.panel-body {
		display: flex;
		flex-direction: column;
		flex: 1;
		overflow: hidden;
	}

	:global(.panel-section) {
		display: flex;
		flex-direction: column;
		flex: 1;
		min-height: 0;
	}

	:global(.panel-section.hidden) {
		display: none;
	}

	.file-upload-input {
		display: none;
	}

	:global(.history-content) {
		display: flex;
		flex-direction: column;
		flex: 1;
		overflow-y: auto;
	}

	:global(.notes-content) {
		display: flex;
		flex-direction: column;
		flex: 1;
		overflow-y: auto;
	}

	:global(.files-content) {
		display: flex;
		flex-direction: column;
		flex: 1;
		overflow-y: auto;
	}

	:global(.things-content) {
		display: flex;
		flex-direction: column;
		flex: 1;
		overflow-y: auto;
	}
</style>
