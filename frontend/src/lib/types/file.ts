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
  archived?: boolean;
}

export interface SingleFileTree {
  children: FileNode[];
  loading: boolean;
  expandedPaths: Set<string>;
}

export interface FileTreeState {
  trees: Record<string, SingleFileTree>;
}
