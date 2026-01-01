export interface IngestedFileMeta {
  id: string;
  filename_original: string;
  path?: string | null;
  mime_original: string;
  size_bytes: number;
  sha256?: string | null;
  pinned?: boolean;
  pinned_order?: number | null;
  category?: string | null;
  source_url?: string | null;
  source_metadata?: Record<string, unknown> | null;
  created_at: string;
}

export interface IngestionJob {
  status: string | null;
  stage: string | null;
  error_code?: string | null;
  error_message?: string | null;
  user_message?: string | null;
  progress?: number | null;
  attempts: number;
  updated_at?: string | null;
}

export interface IngestionListItem {
  file: IngestedFileMeta;
  job: IngestionJob;
  recommended_viewer?: string | null;
}

export interface IngestionListResponse {
  items: IngestionListItem[];
}

export interface IngestionMetaResponse {
  file: IngestedFileMeta;
  job: IngestionJob;
  derivatives: Array<{
    id: string;
    kind: string;
    storage_key: string;
    mime: string;
    size_bytes: number;
  }>;
  recommended_viewer: string | null;
}
