export interface Memory {
  id: string;
  path: string;
  content: string;
  created_at: string;
  updated_at: string;
}

export interface MemoryCreate {
  path: string;
  content: string;
}

export interface MemoryUpdate {
  path?: string;
  content?: string;
}
