import { browser } from '$app/environment';
import { clearCaches, clearInFlight, clearMemoryCache, invalidateCaches } from '$lib/utils/cache';

type CacheEventType =
  | 'conversation.created'
  | 'conversation.deleted'
  | 'conversation.updated'
  | 'conversation.title_updated'
  | 'conversation.archived'
  | 'conversation.unarchived'
  | 'website.saved'
  | 'website.deleted'
  | 'website.renamed'
  | 'website.pinned'
  | 'website.archived'
  | 'note.created'
  | 'note.deleted'
  | 'note.updated'
  | 'note.moved'
  | 'note.renamed'
  | 'note.pinned'
  | 'note.archived'
  | 'file.uploaded'
  | 'file.deleted'
  | 'file.moved'
  | 'file.renamed'
  | 'memory.created'
  | 'memory.updated'
  | 'memory.deleted'
  | 'user.logout';

const INVALIDATION_MAP: Record<CacheEventType, string[]> = {
  'conversation.created': ['conversations.list'],
  'conversation.deleted': ['conversations.list'],
  'conversation.updated': ['conversations.list'],
  'conversation.title_updated': ['conversations.list'],
  'conversation.archived': ['conversations.list'],
  'conversation.unarchived': ['conversations.list'],
  'website.saved': ['websites.list'],
  'website.deleted': ['websites.list'],
  'website.renamed': ['websites.list'],
  'website.pinned': ['websites.list'],
  'website.archived': ['websites.list'],
  'note.created': ['notes.tree'],
  'note.deleted': ['notes.tree'],
  'note.updated': ['notes.tree'],
  'note.moved': ['notes.tree'],
  'note.renamed': ['notes.tree'],
  'note.pinned': ['notes.tree'],
  'note.archived': ['notes.tree'],
  'file.uploaded': ['files.tree.documents', 'files.tree.workspace', 'ingestion.list'],
  'file.deleted': ['files.tree.documents', 'files.tree.workspace', 'ingestion.list'],
  'file.moved': ['files.tree.documents', 'files.tree.workspace'],
  'file.renamed': ['files.tree.documents', 'files.tree.workspace', 'ingestion.list'],
  'memory.created': ['memories.list'],
  'memory.updated': ['memories.list'],
  'memory.deleted': ['memories.list'],
  'user.logout': ['*']
};

export function dispatchCacheEvent(eventType: CacheEventType): void {
  const cacheKeys = INVALIDATION_MAP[eventType] || [];

  if (cacheKeys.includes('*')) {
    clearCaches();
    clearMemoryCache();
    clearInFlight();
  } else {
    invalidateCaches(cacheKeys);
    clearMemoryCache(cacheKeys);
  }

  if (browser) {
    window.dispatchEvent(
      new CustomEvent('cache:invalidate', {
        detail: { eventType, cacheKeys }
      })
    );
  }
}

export function onCacheInvalidate(
  callback: (detail: { eventType: CacheEventType; cacheKeys: string[] }) => void
): () => void {
  if (!browser) return () => undefined;

  const handler = ((event: CustomEvent) => {
    callback(event.detail);
  }) as EventListener;

  window.addEventListener('cache:invalidate', handler);
  return () => window.removeEventListener('cache:invalidate', handler);
}
