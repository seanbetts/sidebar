import { getCachedData, setCachedData } from '$lib/utils/cache';

export const NOTES_TREE_CACHE_KEY = 'notes.tree';
export const WORKSPACE_TREE_CACHE_PREFIX = 'files.tree';
export const TREE_CACHE_TTL = 30 * 60 * 1000;
export const TREE_CACHE_VERSION = '1.1';
export const EXPANDED_CACHE_PREFIX = 'files.expanded';
export const EXPANDED_TTL = 7 * 24 * 60 * 60 * 1000;

export const normalizeBasePath = (basePath: string) => (basePath === '.' ? 'workspace' : basePath);
export const getTreeCacheKey = (basePath: string) =>
  basePath === 'notes' ? NOTES_TREE_CACHE_KEY : `${WORKSPACE_TREE_CACHE_PREFIX}.${normalizeBasePath(basePath)}`;
export const getExpandedCacheKey = (basePath: string) =>
  `${EXPANDED_CACHE_PREFIX}.${normalizeBasePath(basePath)}`;

export const getExpandedCache = (basePath: string) =>
  getCachedData<string[]>(getExpandedCacheKey(basePath), {
    ttl: EXPANDED_TTL,
    version: TREE_CACHE_VERSION
  });

export const cacheTree = (basePath: string, children: unknown) => {
  setCachedData(getTreeCacheKey(basePath), children, {
    ttl: TREE_CACHE_TTL,
    version: TREE_CACHE_VERSION
  });
};

export const cacheExpanded = (basePath: string, expandedPaths: Set<string>) => {
  setCachedData(getExpandedCacheKey(basePath), Array.from(expandedPaths), {
    ttl: EXPANDED_TTL,
    version: TREE_CACHE_VERSION
  });
};
