/**
 * File system types for file browser
 */

export type FileType = 'file' | 'directory';

export interface FileNode {
	name: string;
	path: string;
	type: FileType;
	size?: number;
	modified?: string;
	children?: FileNode[];
	expanded?: boolean;
	pinned?: boolean;
	pinned_order?: number | null;
	archived?: boolean;
	folderMarker?: boolean;
}

export interface SingleFileTree {
	children: FileNode[];
	loading: boolean;
	expandedPaths: Set<string>;
	error?: string | null;
	searchQuery?: string;
	loaded?: boolean;
	archivedLoading?: boolean;
	archivedLoaded?: boolean;
}

export interface FileTreeState {
	trees: Record<string, SingleFileTree>;
}
