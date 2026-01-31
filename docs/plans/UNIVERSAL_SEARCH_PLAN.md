---
title: "Universal Search API Implementation Plan"
description: "Plan for the universal search API."
---

# Universal Search API Implementation Plan

## Overview

Implement a comprehensive universal search system for local content (notes, websites, files, conversations, memories) with PostgreSQL Full-Text Search, pgvector semantic search, AI assistant integration, and MCP server interface for OpenAI Deep Research compatibility.

## Key Principles

- **Separation of Concerns**: Local search and web search are separate tools with different use cases
- **Unified Backend**: Shared infrastructure (providers, service layer) powers all search interfaces
- **Consistent Citations**: All searches return standardized citation metadata for provenance tracking
- **Risk-Based Security**: Security overhead only where needed (web + deep research)
- **Deep Research Ready**: MCP-compatible interface for OpenAI o3-deep-research model from day one

## Requirements

- **Full MVP**: All local content types, both keyword and semantic search
- **PostgreSQL FTS**: Full-text search with tsvector columns and GIN indexes
- **Vector/Semantic Search**: pgvector embeddings for semantic similarity
- **MCP Interface**: Search + Fetch endpoints compatible with OpenAI deep research API
- **Citations & Annotations**: Standardized citation tracking across all sources
- **Backward Compatible**: Keep existing search endpoints alongside universal endpoint

## Existing Infrastructure

**Already Built:**
- ✅ Web search via Anthropic's `web_search_20250305` tool
- ✅ Individual search endpoints: `/notes/search`, `/websites/search`, `/conversations/search`
- ✅ Search implementation using ILIKE queries (will upgrade to FTS)
- ✅ Comprehensive CRUD tools for notes, websites, files
- ✅ Background task infrastructure (FastAPI BackgroundTasks)

**To Be Built:**
- ❌ PostgreSQL Full-Text Search (upgrade from ILIKE)
- ❌ pgvector semantic search
- ❌ Unified search across all content types
- ❌ Search as a tool for AI assistant
- ❌ MCP-compatible interface
- ❌ Citation and annotation tracking

## Architecture

### System Overview

```
┌─────────────────────────────────────────────────────────────┐
│                      API Layer                               │
├─────────────────────────────────────────────────────────────┤
│  AI Tools:                        HTTP Endpoints:            │
│  • search_local_knowledge (NEW)   • POST /api/v1/search     │
│  • web_search (EXISTS)            • POST /api/v1/mcp/search │
│                                   • POST /api/v1/mcp/fetch  │
├─────────────────────────────────────────────────────────────┤
│              Universal Search Service                        │
│  • Orchestrates parallel provider execution                 │
│  • Aggregates and ranks results                             │
│  • Generates citation metadata                              │
│  • Handles mode switching (basic/deep_research)             │
├─────────────────────────────────────────────────────────────┤
│  Search Providers:                                          │
│  • NotesProvider        • WebsitesProvider                  │
│  • FilesProvider        • ConversationsProvider             │
│  • MemoriesProvider                                         │
│  (Each implements: FTS keyword search + vector semantic)    │
├─────────────────────────────────────────────────────────────┤
│  Supporting Services:                                       │
│  • EmbeddingService     • SecurityValidator                 │
│  • BackgroundJobService • CitationExtractor                 │
└─────────────────────────────────────────────────────────────┘
```

### Database Schema Changes

**Migration** (`backend/api/alembic/versions/20260119_HHMM_add_universal_search.py`):

```sql
-- Enable pgvector extension
CREATE EXTENSION IF NOT EXISTS vector;

-- 1. Add tsvector columns for full-text search
ALTER TABLE notes ADD COLUMN search_vector tsvector;
ALTER TABLE websites ADD COLUMN search_vector tsvector;
ALTER TABLE user_memories ADD COLUMN search_vector tsvector;
ALTER TABLE conversations ADD COLUMN search_vector tsvector;

-- 2. Add vector columns for semantic search (1536 dimensions for OpenAI/Anthropic)
ALTER TABLE notes ADD COLUMN embedding vector(1536);
ALTER TABLE websites ADD COLUMN embedding vector(1536);
ALTER TABLE user_memories ADD COLUMN embedding vector(1536);
-- Files use ai_md derivatives, embeddings generated on-demand

-- 3. Create GIN indexes for FTS
CREATE INDEX idx_notes_search_vector ON notes USING gin(search_vector);
CREATE INDEX idx_websites_search_vector ON websites USING gin(search_vector);
CREATE INDEX idx_user_memories_search_vector ON user_memories USING gin(search_vector);
CREATE INDEX idx_conversations_search_vector ON conversations USING gin(search_vector);

-- 4. Create IVFFlat indexes for vector search
CREATE INDEX idx_notes_embedding ON notes USING ivfflat (embedding vector_cosine_ops)
    WITH (lists = 100);
CREATE INDEX idx_websites_embedding ON websites USING ivfflat (embedding vector_cosine_ops)
    WITH (lists = 100);
CREATE INDEX idx_user_memories_embedding ON user_memories USING ivfflat (embedding vector_cosine_ops)
    WITH (lists = 100);

-- 5. Create triggers to maintain search vectors
CREATE TRIGGER notes_search_vector_update
    BEFORE INSERT OR UPDATE ON notes
    FOR EACH ROW EXECUTE FUNCTION
    tsvector_update_trigger(search_vector, 'pg_catalog.english', title, content);

CREATE TRIGGER websites_search_vector_update
    BEFORE INSERT OR UPDATE ON websites
    FOR EACH ROW EXECUTE FUNCTION
    tsvector_update_trigger(search_vector, 'pg_catalog.english', title, content);

CREATE TRIGGER user_memories_search_vector_update
    BEFORE INSERT OR UPDATE ON user_memories
    FOR EACH ROW EXECUTE FUNCTION
    tsvector_update_trigger(search_vector, 'pg_catalog.english', content);

CREATE TRIGGER conversations_search_vector_update
    BEFORE INSERT OR UPDATE ON conversations
    FOR EACH ROW EXECUTE FUNCTION
    tsvector_update_trigger(search_vector, 'pg_catalog.english', title, first_message);

-- 6. Backfill existing data
UPDATE notes SET search_vector = to_tsvector('english',
    coalesce(title, '') || ' ' || coalesce(content, ''));
UPDATE websites SET search_vector = to_tsvector('english',
    coalesce(title, '') || ' ' || coalesce(content, ''));
UPDATE user_memories SET search_vector = to_tsvector('english',
    coalesce(content, ''));
UPDATE conversations SET search_vector = to_tsvector('english',
    coalesce(title, '') || ' ' || coalesce(first_message, ''));

-- 7. Search operations tracking table (for deep research mode)
CREATE TABLE search_operations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id TEXT NOT NULL,
    session_id UUID NULL,              -- Groups related operations
    parent_operation_id UUID NULL,      -- For chained searches

    -- Operation details
    operation_type TEXT NOT NULL,       -- 'search', 'fetch', 'refine'
    query TEXT NOT NULL,
    sources TEXT[] NOT NULL,            -- ['local'], ['web'], or both
    content_types TEXT[],               -- Filter for local searches
    mode TEXT NOT NULL,                 -- 'basic' or 'deep_research'

    -- Results
    result_count INTEGER NOT NULL,
    result_ids TEXT[],                  -- IDs of returned items
    execution_time_ms FLOAT NOT NULL,

    -- Metadata
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Indexes
    CONSTRAINT fk_parent_operation FOREIGN KEY (parent_operation_id)
        REFERENCES search_operations(id) ON DELETE CASCADE
);

CREATE INDEX idx_search_operations_user_id ON search_operations(user_id);
CREATE INDEX idx_search_operations_session_id ON search_operations(session_id);
CREATE INDEX idx_search_operations_parent ON search_operations(parent_operation_id);
CREATE INDEX idx_search_operations_created_at ON search_operations(created_at);

-- 8. Background search jobs table
CREATE TABLE search_jobs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id TEXT NOT NULL,

    -- Job details
    status TEXT NOT NULL DEFAULT 'pending',  -- 'pending', 'running', 'completed', 'failed'
    request_payload JSONB NOT NULL,          -- Full search request
    result_payload JSONB NULL,               -- Search results when completed
    error_message TEXT NULL,

    -- Webhook (optional)
    webhook_url TEXT NULL,
    webhook_called_at TIMESTAMPTZ NULL,

    -- Timing
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    started_at TIMESTAMPTZ NULL,
    completed_at TIMESTAMPTZ NULL,

    -- Indexes
    CONSTRAINT check_status CHECK (status IN ('pending', 'running', 'completed', 'failed'))
);

CREATE INDEX idx_search_jobs_user_id ON search_jobs(user_id);
CREATE INDEX idx_search_jobs_status ON search_jobs(status);
CREATE INDEX idx_search_jobs_created_at ON search_jobs(created_at);
```

### Core Schemas

**Request/Response Models** (`backend/api/schemas/search.py`):

```python
from dataclasses import dataclass
from datetime import datetime
from enum import Enum
from typing import Literal


class SearchMode(str, Enum):
    """Search execution mode."""
    BASIC = "basic"              # Fast keyword/semantic search
    DEEP_RESEARCH = "deep_research"  # Multi-step research with tracking


class SearchType(str, Enum):
    """Type of search algorithm."""
    KEYWORD = "keyword"          # PostgreSQL FTS only
    SEMANTIC = "semantic"        # Vector similarity only
    HYBRID = "hybrid"            # Combined FTS + vector


class ContentType(str, Enum):
    """Types of searchable content."""
    NOTE = "note"
    WEBSITE = "website"
    FILE = "file"
    CONVERSATION = "conversation"
    MEMORY = "memory"


class SecurityLevel(str, Enum):
    """Security validation level."""
    TRUSTED = "trusted"          # No overhead (local only)
    BASIC = "basic"              # Rate limiting only
    STRICT = "strict"            # Full validation (web involved)


@dataclass
class UniversalSearchRequest:
    """Universal search request for local content."""
    query: str

    # Content filtering
    content_types: list[ContentType] | None = None  # None = all types

    # Search configuration
    mode: SearchMode = SearchMode.BASIC
    search_type: SearchType = SearchType.KEYWORD
    limit: int = 50
    offset: int = 0

    # Date filters
    created_after: datetime | None = None
    created_before: datetime | None = None
    updated_after: datetime | None = None
    updated_before: datetime | None = None

    # Content-specific filters
    folder: str | None = None           # Notes only
    domain: str | None = None           # Websites only
    archived: bool | None = None        # Notes/websites

    # Result options
    include_snippets: bool = True
    snippet_length: int = 200
    full_content: bool = False          # Return complete content

    # Deep research options (only used when mode=DEEP_RESEARCH)
    session_id: str | None = None       # Groups related searches
    parent_operation_id: str | None = None  # Links to previous search
    max_operations: int = 10            # Limit search chain length

    # Background execution (only for deep research)
    background: bool = False
    webhook_url: str | None = None


@dataclass
class CitationMetadata:
    """Standardized citation information for all sources."""
    source_id: str                      # UUID for local content
    source_type: ContentType
    source_title: str
    url: str | None = None              # For websites
    author: str | None = None
    published_date: datetime | None = None
    created_date: datetime | None = None
    last_accessed: datetime | None = None

    # Additional context
    folder: str | None = None           # Notes
    domain: str | None = None           # Websites


@dataclass
class Annotation:
    """Text span annotation for citations (deep research mode)."""
    text: str                           # The cited text
    start_index: int                    # Character position in response
    end_index: int
    source_id: str
    highlight: str | None = None        # Highlighted context around citation


@dataclass
class SearchResultItem:
    """Single search result with citation metadata."""
    id: str                             # Unique identifier (UUID for local)
    content_type: ContentType
    source: Literal["local", "web"]     # Always "local" for this system
    title: str
    snippet: str | None
    relevance_score: float              # 0.0-1.0

    # Timestamps
    created_at: datetime
    updated_at: datetime | None
    last_opened_at: datetime | None

    # Citation (always included)
    citation: CitationMetadata

    # Metadata
    metadata: dict                      # Content-specific fields
    match_fields: list[str]             # ["title", "content"]

    # Conditional fields
    full_content: str | None = None     # Only when full_content=True
    annotations: list[Annotation] | None = None  # Deep research only


@dataclass
class SearchOperation:
    """Record of a single search operation (deep research mode)."""
    id: str
    operation_type: str                 # "search", "fetch", "refine"
    query: str
    sources: list[str]
    content_types: list[ContentType] | None
    result_count: int
    execution_time_ms: float
    created_at: datetime


@dataclass
class UniversalSearchResponse:
    """Universal search response."""
    items: list[SearchResultItem]
    total_count: int
    counts_by_type: dict[str, int]      # {"note": 10, "website": 5}
    query: str
    execution_time_ms: float

    # Deep research mode only
    operations: list[SearchOperation] | None = None
    session_id: str | None = None

    # Background job (if background=True)
    job_id: str | None = None


@dataclass
class MCPSearchRequest:
    """MCP-compatible search request (lightweight)."""
    query: str
    content_types: list[ContentType] | None = None
    limit: int = 20


@dataclass
class MCPSearchResult:
    """Lightweight search result for MCP search endpoint."""
    id: str                             # Prefixed: "local:note:uuid"
    title: str
    snippet: str
    relevance_score: float
    source: Literal["local"]
    content_type: ContentType


@dataclass
class MCPSearchResponse:
    """MCP search response (lightweight)."""
    results: list[MCPSearchResult]
    total_count: int


@dataclass
class MCPFetchRequest:
    """MCP fetch request for full document."""
    id: str                             # Format: "local:note:uuid"


@dataclass
class MCPFetchResponse:
    """MCP fetch response with full content."""
    id: str
    content: str                        # Full markdown content
    citation: CitationMetadata
    metadata: dict
```

### Search Provider Protocol

**Base Protocol** (`backend/api/services/search_providers/base.py`):

```python
from typing import Protocol
from sqlalchemy.orm import Session
from api.schemas.search import (
    SearchResultItem,
    SearchType,
    CitationMetadata,
)


class SearchProvider(Protocol):
    """Protocol for content-specific search providers."""

    def search(
        self,
        db: Session,
        user_id: str,
        query: str,
        *,
        search_type: SearchType = SearchType.KEYWORD,
        limit: int = 50,
        offset: int = 0,
        **filters,
    ) -> list[SearchResultItem]:
        """Search for content matching query.

        Args:
            db: Database session
            user_id: Current user ID
            query: Search query
            search_type: Type of search (keyword/semantic/hybrid)
            limit: Max results
            offset: Pagination offset
            **filters: Content-specific filters

        Returns:
            List of search results with citations
        """
        ...

    def count(
        self,
        db: Session,
        user_id: str,
        query: str,
        *,
        search_type: SearchType = SearchType.KEYWORD,
        **filters,
    ) -> int:
        """Count matching results.

        Args:
            db: Database session
            user_id: Current user ID
            query: Search query
            search_type: Type of search
            **filters: Content-specific filters

        Returns:
            Total count
        """
        ...

    def fetch_by_id(
        self,
        db: Session,
        user_id: str,
        item_id: str,
    ) -> SearchResultItem | None:
        """Fetch full content by ID (for MCP fetch).

        Args:
            db: Database session
            user_id: Current user ID
            item_id: Item identifier

        Returns:
            Full search result or None
        """
        ...

    def build_citation(
        self,
        item: Any,
    ) -> CitationMetadata:
        """Build citation metadata for an item.

        Args:
            item: Database model instance

        Returns:
            Citation metadata
        """
        ...
```

### Universal Search Service

**Core Orchestration** (`backend/api/services/universal_search_service.py`):

```python
import asyncio
import logging
import time
from uuid import uuid4
from sqlalchemy.orm import Session
from api.schemas.search import (
    UniversalSearchRequest,
    UniversalSearchResponse,
    SearchResultItem,
    SearchOperation,
    SearchMode,
    SecurityLevel,
)
from api.services.search_providers import (
    NotesProvider,
    WebsitesProvider,
    FilesProvider,
    ConversationsProvider,
    MemoriesProvider,
)
from api.services.security_validator import SearchSecurityValidator
from api.models import SearchOperationModel

logger = logging.getLogger(__name__)


class UniversalSearchService:
    """Orchestrates search across all content providers."""

    def __init__(self, db: Session, user_id: str):
        self.db = db
        self.user_id = user_id
        self.providers = {
            "note": NotesProvider(),
            "website": WebsitesProvider(),
            "file": FilesProvider(),
            "conversation": ConversationsProvider(),
            "memory": MemoriesProvider(),
        }

    async def search(
        self,
        request: UniversalSearchRequest,
    ) -> UniversalSearchResponse:
        """Execute universal search across content types.

        Args:
            request: Search request

        Returns:
            Aggregated search results
        """
        start_time = time.time()

        # Validate security
        security_level = self._get_security_level(request)
        if security_level == SecurityLevel.STRICT:
            SearchSecurityValidator.validate_query(request.query)

        # Check rate limiting
        if security_level in (SecurityLevel.BASIC, SecurityLevel.STRICT):
            SearchSecurityValidator.check_rate_limit(self.user_id, request.mode)

        # Determine which providers to use
        content_types = request.content_types or [
            "note", "website", "file", "conversation", "memory"
        ]

        # Execute searches in parallel
        search_tasks = []
        for content_type in content_types:
            if content_type in self.providers:
                provider = self.providers[content_type]
                task = self._search_provider(
                    provider,
                    request.query,
                    request.search_type,
                    request.limit,
                    request.offset,
                    **self._extract_filters(request, content_type),
                )
                search_tasks.append(task)

        # Gather results
        results_by_provider = await asyncio.gather(*search_tasks)

        # Aggregate and rank
        all_items = []
        for results in results_by_provider:
            all_items.extend(results)

        # Sort by relevance
        all_items.sort(key=lambda x: x.relevance_score, reverse=True)

        # Apply global limit
        items = all_items[request.offset:request.offset + request.limit]

        # Enrich with full content if requested
        if request.full_content:
            for item in items:
                item.full_content = await self._fetch_full_content(item)

        # Count by type
        counts_by_type = {}
        for item in all_items:
            counts_by_type[item.content_type] = (
                counts_by_type.get(item.content_type, 0) + 1
            )

        execution_time = (time.time() - start_time) * 1000

        # Track operation if deep research mode
        operations = None
        session_id = request.session_id
        if request.mode == SearchMode.DEEP_RESEARCH:
            session_id = session_id or str(uuid4())
            operation = await self._record_operation(
                session_id=session_id,
                parent_operation_id=request.parent_operation_id,
                operation_type="search",
                query=request.query,
                sources=["local"],
                content_types=content_types,
                result_count=len(items),
                result_ids=[item.id for item in items],
                execution_time_ms=execution_time,
            )
            operations = [operation]

        return UniversalSearchResponse(
            items=items,
            total_count=len(all_items),
            counts_by_type=counts_by_type,
            query=request.query,
            execution_time_ms=execution_time,
            operations=operations,
            session_id=session_id,
        )

    async def _search_provider(
        self,
        provider,
        query: str,
        search_type,
        limit: int,
        offset: int,
        **filters,
    ) -> list[SearchResultItem]:
        """Execute search for a single provider."""
        try:
            # Run in thread pool to avoid blocking
            loop = asyncio.get_event_loop()
            return await loop.run_in_executor(
                None,
                provider.search,
                self.db,
                self.user_id,
                query,
                search_type,
                limit,
                offset,
                filters,
            )
        except Exception as e:
            logger.error(f"Provider search failed: {e}")
            return []

    async def _fetch_full_content(self, item: SearchResultItem) -> str:
        """Fetch full content for an item."""
        provider = self.providers.get(item.content_type)
        if not provider:
            return ""

        try:
            full_item = provider.fetch_by_id(self.db, self.user_id, item.id)
            return full_item.full_content if full_item else ""
        except Exception as e:
            logger.error(f"Failed to fetch full content: {e}")
            return ""

    def _get_security_level(self, request: UniversalSearchRequest) -> SecurityLevel:
        """Determine security level for request."""
        # Local-only searches are trusted
        return SecurityLevel.TRUSTED

    def _extract_filters(self, request: UniversalSearchRequest, content_type: str) -> dict:
        """Extract content-type-specific filters."""
        filters = {
            "created_after": request.created_after,
            "created_before": request.created_before,
            "updated_after": request.updated_after,
            "updated_before": request.updated_before,
            "archived": request.archived,
        }

        if content_type == "note":
            filters["folder"] = request.folder
        elif content_type == "website":
            filters["domain"] = request.domain

        return {k: v for k, v in filters.items() if v is not None}

    async def _record_operation(
        self,
        *,
        session_id: str,
        parent_operation_id: str | None,
        operation_type: str,
        query: str,
        sources: list[str],
        content_types: list[str],
        result_count: int,
        result_ids: list[str],
        execution_time_ms: float,
    ) -> SearchOperation:
        """Record search operation in database."""
        operation = SearchOperationModel(
            user_id=self.user_id,
            session_id=session_id,
            parent_operation_id=parent_operation_id,
            operation_type=operation_type,
            query=query,
            sources=sources,
            content_types=content_types,
            result_count=result_count,
            result_ids=result_ids,
            execution_time_ms=execution_time_ms,
        )
        self.db.add(operation)
        self.db.commit()

        return SearchOperation(
            id=str(operation.id),
            operation_type=operation_type,
            query=query,
            sources=sources,
            content_types=content_types,
            result_count=result_count,
            execution_time_ms=execution_time_ms,
            created_at=operation.created_at,
        )
```

### API Endpoints

**Universal Search Router** (`backend/api/routers/search.py`):

```python
from fastapi import APIRouter, Depends, BackgroundTasks
from sqlalchemy.orm import Session

from api.auth import verify_bearer_token
from api.db.dependencies import get_current_user_id
from api.db.session import get_db
from api.schemas.search import (
    UniversalSearchRequest,
    UniversalSearchResponse,
    MCPSearchRequest,
    MCPSearchResponse,
    MCPFetchRequest,
    MCPFetchResponse,
)
from api.services.universal_search_service import UniversalSearchService
from api.services.mcp_search_service import MCPSearchService

router = APIRouter(prefix="/search", tags=["search"])
mcp_router = APIRouter(prefix="/mcp", tags=["mcp"])


@router.post("", response_model=UniversalSearchResponse)
async def universal_search(
    request: UniversalSearchRequest,
    background_tasks: BackgroundTasks,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Universal search across all local content.

    Supports:
    - Multiple content types (notes, websites, files, conversations, memories)
    - Search modes (basic, deep_research)
    - Search types (keyword, semantic, hybrid)
    - Date and metadata filtering
    - Full content retrieval
    - Background execution for long searches
    """
    service = UniversalSearchService(db, user_id)

    if request.background:
        # Execute in background, return job ID
        job = await service.create_background_job(request)
        background_tasks.add_task(service.execute_background_search, job.id)
        return UniversalSearchResponse(
            items=[],
            total_count=0,
            counts_by_type={},
            query=request.query,
            execution_time_ms=0.0,
            job_id=str(job.id),
        )
    else:
        # Execute immediately
        return await service.search(request)


@router.get("/jobs/{job_id}")
async def get_search_job(
    job_id: str,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Get status and results of a background search job."""
    service = UniversalSearchService(db, user_id)
    return await service.get_job_status(job_id)


# MCP-compatible endpoints for OpenAI Deep Research
@mcp_router.post("/search", response_model=MCPSearchResponse)
async def mcp_search(
    request: MCPSearchRequest,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """MCP-compatible search endpoint (lightweight results).

    Returns search results with IDs and snippets only.
    Use /mcp/fetch to retrieve full content.

    Compatible with OpenAI o3-deep-research model.
    """
    service = MCPSearchService(db, user_id)
    return await service.search(request)


@mcp_router.post("/fetch", response_model=MCPFetchResponse)
async def mcp_fetch(
    request: MCPFetchRequest,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """MCP-compatible fetch endpoint (full document).

    Retrieves complete content for a specific document by ID.

    Compatible with OpenAI o3-deep-research model.
    """
    service = MCPSearchService(db, user_id)
    return await service.fetch(request)
```

### AI Tool Integration

**Tool Definition** (`backend/api/services/tools/definitions_search.py`):

```python
"""Search tool definitions for AI assistant."""


def get_search_definitions() -> dict:
    """Return search tool definitions."""
    return {
        "Search Local Knowledge": {
            "description": (
                "Search across user's local knowledge base including notes, "
                "saved websites, files, conversations, and memories. "
                "Supports both keyword and semantic search. "
                "Use for finding information in user's personal content."
            ),
            "input_schema": {
                "type": "object",
                "properties": {
                    "query": {
                        "type": "string",
                        "description": "Search query"
                    },
                    "content_types": {
                        "type": "array",
                        "items": {
                            "type": "string",
                            "enum": ["note", "website", "file", "conversation", "memory"]
                        },
                        "description": "Limit to specific content types (optional)"
                    },
                    "search_type": {
                        "type": "string",
                        "enum": ["keyword", "semantic", "hybrid"],
                        "description": "Type of search (default: keyword)",
                        "default": "keyword"
                    },
                    "mode": {
                        "type": "string",
                        "enum": ["basic", "deep_research"],
                        "description": "Search mode (default: basic)",
                        "default": "basic"
                    },
                    "limit": {
                        "type": "integer",
                        "description": "Max results (default: 20)",
                        "default": 20
                    },
                    "created_after": {
                        "type": "string",
                        "format": "date-time",
                        "description": "Filter by creation date"
                    },
                    "updated_after": {
                        "type": "string",
                        "format": "date-time",
                        "description": "Filter by update date"
                    },
                    "folder": {
                        "type": "string",
                        "description": "Filter notes by folder"
                    },
                    "domain": {
                        "type": "string",
                        "description": "Filter websites by domain"
                    },
                    "full_content": {
                        "type": "boolean",
                        "description": "Return full content (default: true for AI)",
                        "default": True
                    },
                    "session_id": {
                        "type": "string",
                        "description": "Session ID for linking related searches (deep research)"
                    },
                    "parent_operation_id": {
                        "type": "string",
                        "description": "Parent operation ID for search chains (deep research)"
                    }
                },
                "required": ["query"]
            },
            "skill": None,  # Native service, not a skill
            "script": None,
            "build_args": None,
        }
    }
```

**Tool Execution Handler** (add to `backend/api/services/tools/execution_handlers.py`):

```python
async def execute_search_local_knowledge(
    params: dict,
    context: ToolContext,
) -> dict:
    """Execute local knowledge base search for AI assistant.

    Args:
        params: Tool parameters
        context: Execution context with db, user_id, etc.

    Returns:
        Search results formatted for AI consumption
    """
    from api.schemas.search import UniversalSearchRequest, SearchMode, SearchType
    from api.services.universal_search_service import UniversalSearchService

    # Build request
    request = UniversalSearchRequest(
        query=params["query"],
        content_types=params.get("content_types"),
        search_type=SearchType(params.get("search_type", "keyword")),
        mode=SearchMode(params.get("mode", "basic")),
        limit=params.get("limit", 20),
        created_after=params.get("created_after"),
        updated_after=params.get("updated_after"),
        folder=params.get("folder"),
        domain=params.get("domain"),
        full_content=params.get("full_content", True),  # Default True for AI
        session_id=params.get("session_id"),
        parent_operation_id=params.get("parent_operation_id"),
    )

    # Execute search
    service = UniversalSearchService(context.db, context.user_id)
    response = await service.search(request)

    # Format for AI consumption
    return {
        "results": [
            {
                "id": item.id,
                "type": item.content_type,
                "title": item.title,
                "content": item.full_content or item.snippet,
                "relevance_score": item.relevance_score,
                "citation": {
                    "source_id": item.citation.source_id,
                    "source_type": item.citation.source_type,
                    "source_title": item.citation.source_title,
                    "created_date": item.citation.created_date.isoformat() if item.citation.created_date else None,
                    "url": item.citation.url,
                },
                "created_at": item.created_at.isoformat(),
                "updated_at": item.updated_at.isoformat() if item.updated_at else None,
            }
            for item in response.items
        ],
        "total_count": response.total_count,
        "counts_by_type": response.counts_by_type,
        "session_id": response.session_id,
    }
```

## Implementation Phases

### Phase 1: Foundation (Week 1)

**Goals**: Database schema, FTS, basic providers

1. **Database Migration** (Day 1-2)
   - Create migration with tsvector columns, GIN indexes
   - Add pgvector extension and vector columns
   - Create search_operations and search_jobs tables
   - Add triggers for auto-updating search vectors
   - Backfill existing data
   - Test on development database

2. **Core Schemas** (Day 2)
   - Create `backend/api/schemas/search.py`
   - Define all request/response models
   - Add Pydantic validation
   - Create enums for modes, types, etc.

3. **Base Provider Protocol** (Day 3)
   - Create `backend/api/services/search_providers/base.py`
   - Define SearchProvider protocol
   - Add helper functions for citation building

4. **Notes Provider** (Day 3-4)
   - Create `backend/api/services/search_providers/notes_provider.py`
   - Implement FTS keyword search
   - Add citation metadata generation
   - Add fetch_by_id for MCP support
   - Test thoroughly

5. **Websites Provider** (Day 4)
   - Create `backend/api/services/search_providers/websites_provider.py`
   - Implement FTS keyword search
   - Add citation with URL metadata
   - Test with various domains

6. **Update Database Models** (Day 5)
   - Add search_vector column to models
   - Add embedding column to models
   - Create SearchOperation model
   - Create SearchJob model

### Phase 2: Universal Search Service (Week 2)

**Goals**: Orchestration, parallel execution, basic endpoint

7. **Universal Search Service** (Day 6-7)
   - Create `backend/api/services/universal_search_service.py`
   - Implement parallel provider execution
   - Add result aggregation and ranking
   - Add citation generation
   - Add security level determination
   - Add operation tracking (deep research mode)

8. **Additional Providers** (Day 8-9)
   - Create `backend/api/services/search_providers/files_provider.py`
   - Create `backend/api/services/search_providers/conversations_provider.py`
   - Create `backend/api/services/search_providers/memories_provider.py`
   - Implement FTS for each
   - Add proper citation metadata

9. **API Endpoint** (Day 10)
   - Create `backend/api/routers/search.py`
   - Implement POST /api/v1/search
   - Add authentication and validation
   - Register router in main.py
   - Test with Postman/curl

10. **Security Validator** (Day 10)
    - Create `backend/api/services/security_validator.py`
    - Add query validation (regex-based)
    - Add rate limiting logic
    - Test edge cases

### Phase 3: AI Integration (Week 3)

**Goals**: Tool for AI assistant, deep research features

11. **Search Tool Definition** (Day 11)
    - Add definitions to `backend/api/services/tools/definitions_search.py`
    - Register in `definitions.py`
    - Test tool schema

12. **Tool Execution Handler** (Day 11-12)
    - Add handler to `execution_handlers.py`
    - Implement parameter mapping
    - Add result formatting for AI
    - Test from Claude chat interface

13. **Deep Research Features** (Day 12-13)
    - Implement operation tracking
    - Add session management
    - Add search chain linking
    - Test multi-step research flows

14. **Background Execution** (Day 13-14)
    - Implement background job creation
    - Add job status polling endpoint
    - Add webhook notifications (optional)
    - Test long-running searches

### Phase 4: MCP Interface (Week 4)

**Goals**: OpenAI deep research compatibility

15. **MCP Service** (Day 15-16)
    - Create `backend/api/services/mcp_search_service.py`
    - Implement lightweight search
    - Implement fetch by ID
    - Add ID prefixing for routing

16. **MCP Endpoints** (Day 16)
    - Add POST /api/v1/mcp/search
    - Add POST /api/v1/mcp/fetch
    - Test with MCP client
    - Document for OpenAI integration

17. **MCP Documentation** (Day 17)
    - Create MCP server documentation
    - Add OpenAI deep research examples
    - Document search/fetch schemas
    - Add troubleshooting guide

### Phase 5: Vector/Semantic Search (Week 5)

**Goals**: Embeddings, semantic search, hybrid mode

18. **Embedding Service** (Day 18-19)
    - Create `backend/api/services/embedding_service.py`
    - Add OpenAI/Anthropic embeddings API integration
    - Add batch embedding generation
    - Add caching strategy

19. **Vector Search Implementation** (Day 19-20)
    - Update all providers with vector search
    - Implement cosine similarity queries
    - Add semantic search mode
    - Test similarity results

20. **Hybrid Search** (Day 20-21)
    - Implement hybrid scoring (FTS + vector)
    - Add alpha parameter for weighting
    - Test and tune ranking
    - Document hybrid search behavior

21. **Backfill Embeddings** (Day 21-22)
    - Create backfill script
    - Generate embeddings for existing content
    - Monitor progress and errors
    - Verify vector indexes

### Phase 6: Polish & Testing (Week 6)

**Goals**: iOS integration, comprehensive testing, documentation

22. **iOS Integration** (Day 23-24)
    - Create `ios/sideBar/sideBar/Services/Network/SearchAPI.swift`
    - Add Swift models for request/response
    - Add universal search method
    - Add MCP search methods
    - Test from iOS app

23. **Comprehensive Testing** (Day 24-25)
    - Unit tests for all providers
    - Integration tests for universal search
    - Test deep research flows
    - Test MCP compatibility
    - Performance tests (< 500ms target)

24. **Documentation** (Day 26)
    - OpenAPI schema documentation
    - AI tool usage guide
    - Deep research workflow examples
    - MCP integration guide
    - Performance tuning guide

25. **Final QA & Deployment** (Day 27-28)
    - End-to-end testing
    - Load testing
    - Security review
    - Deploy to production
    - Monitor metrics

## Critical Files

### New Files

**Backend - Core:**
1. `backend/api/schemas/search.py` - All request/response models
2. `backend/api/services/universal_search_service.py` - Main orchestration
3. `backend/api/services/mcp_search_service.py` - MCP-compatible interface
4. `backend/api/services/embedding_service.py` - Embeddings generation
5. `backend/api/services/security_validator.py` - Query validation & rate limiting
6. `backend/api/routers/search.py` - HTTP endpoints (universal + MCP)

**Backend - Providers:**
7. `backend/api/services/search_providers/__init__.py` - Provider registry
8. `backend/api/services/search_providers/base.py` - Protocol definition
9. `backend/api/services/search_providers/notes_provider.py` - Notes search
10. `backend/api/services/search_providers/websites_provider.py` - Websites search
11. `backend/api/services/search_providers/files_provider.py` - Files search
12. `backend/api/services/search_providers/conversations_provider.py` - Conversations search
13. `backend/api/services/search_providers/memories_provider.py` - Memories search

**Backend - Database:**
14. `backend/api/alembic/versions/20260119_HHMM_add_universal_search.py` - Migration
15. `backend/api/models/search_operation.py` - SearchOperation model
16. `backend/api/models/search_job.py` - SearchJob model

**Frontend:**
17. `ios/sideBar/sideBar/Services/Network/SearchAPI.swift` - iOS client
18. `ios/sideBar/sideBar/Models/Search/` - Swift models

**Documentation:**
19. `docs/api/UNIVERSAL_SEARCH.md` - API documentation
20. `docs/api/MCP_INTERFACE.md` - MCP integration guide
21. `docs/guides/DEEP_RESEARCH.md` - Deep research workflows

### Modified Files

1. `backend/api/main.py` - Register search router
2. `backend/api/services/tools/definitions.py` - Import search definitions
3. `backend/api/services/tools/definitions_search.py` - New search tool definitions
4. `backend/api/services/tools/execution_handlers.py` - Add search execution handler
5. `backend/api/models/note.py` - Add search_vector and embedding columns
6. `backend/api/models/website.py` - Add search_vector and embedding columns
7. `backend/api/models/user_memory.py` - Add search_vector and embedding columns
8. `backend/api/models/conversation.py` - Add search_vector column

## Feature Comparison Matrix

### Search Modes

| Feature | Basic Search | Deep Research |
|---------|-------------|---------------|
| **Speed** | < 500ms | Minutes (background recommended) |
| **FTS Keyword** | ✅ | ✅ |
| **Vector Semantic** | ✅ Optional | ✅ Default |
| **Full Content** | ❌ Snippets only | ✅ Full text |
| **Citations** | ✅ Basic metadata | ✅ Detailed + annotations |
| **Operation Tracking** | ❌ In-memory only | ✅ Database logged |
| **Search Chains** | ❌ | ✅ Linked searches |
| **Background Execution** | ❌ | ✅ Optional |
| **Cost** | Free (local compute) | Embeddings API cost |

### Content Types

| Type | FTS | Vector | Metadata | Special Features |
|------|-----|--------|----------|------------------|
| **Notes** | ✅ | ✅ | Folder | Scratchpad excluded by default |
| **Websites** | ✅ | ✅ | Domain, URL | Published date in citation |
| **Files** | ✅ | ❌ | Path, type | Search ai_md derivatives |
| **Conversations** | ✅ | ❌ | Message count | Search in JSONB messages |
| **Memories** | ✅ | ✅ | Path | Always included |

### Search Types

| Type | Algorithm | Use Case | Performance |
|------|-----------|----------|-------------|
| **Keyword** | PostgreSQL FTS | Exact term matching | Fast (< 100ms) |
| **Semantic** | pgvector cosine | Conceptual similarity | Medium (< 300ms) |
| **Hybrid** | Combined scoring | Best of both worlds | Medium (< 400ms) |

## Security Considerations

### Risk-Based Security Levels

| Level | Triggers | Measures |
|-------|----------|----------|
| **TRUSTED** | Local content only | • No validation<br>• Minimal logging<br>• No overhead |
| **BASIC** | Future: Web search in basic mode | • Rate limiting (100 req/hour)<br>• Standard logging |
| **STRICT** | Future: Web + deep research | • Query validation (regex)<br>• Rate limiting (10 deep research/hour)<br>• Detailed database logging<br>• Phased execution |

### Query Validation (Strict Mode Only)

**Regex-Based Injection Detection**:
```python
# Example patterns to detect
SUSPICIOUS_PATTERNS = [
    r'ignore\s+(previous|all|above)',    # Prompt injection
    r'system\s+prompt',                   # Prompt leaking
    r'<script|javascript:|onclick=',      # XSS attempts
    r'\$\{.*\}',                         # Template injection
    r'UNION\s+SELECT|DROP\s+TABLE',      # SQL injection
]
```

**Note**: No LLM-based validation to avoid API costs.

### Rate Limiting

```python
# Per-user limits
RATE_LIMITS = {
    "basic_search_local": 100,      # per hour
    "deep_research_local": 50,      # per hour
    "background_jobs": 10,           # concurrent
}
```

### Data Privacy

- All searches scoped to `user_id`
- RLS policies on all tables
- Operation logs include only user's own data
- Background jobs auto-expire after 24 hours

## Performance Targets

### Latency Targets

| Operation | Target | Notes |
|-----------|--------|-------|
| Basic search (1 type, keyword) | < 100ms | Single provider, FTS only |
| Basic search (all types, keyword) | < 500ms | Parallel execution |
| Semantic search | < 300ms | Vector similarity |
| Hybrid search | < 400ms | Combined FTS + vector |
| Deep research (background) | Minutes | User-initiated, webhook notification |
| MCP search | < 200ms | Lightweight results only |
| MCP fetch | < 50ms | Single document lookup |

### Scalability

- **GIN Indexes**: Fast FTS even with millions of documents
- **IVFFlat Indexes**: Vector search scales to ~1M embeddings per table
- **Parallel Providers**: All content types searched concurrently
- **Background Jobs**: Long searches don't block API
- **Rate Limiting**: Prevents abuse and cost overruns

### Optimization Strategies

1. **Index Tuning**: Monitor with EXPLAIN ANALYZE, adjust index parameters
2. **Vector Lists**: Tune IVFFlat lists parameter based on data size
3. **Result Caching**: Cache popular queries (future enhancement)
4. **Embeddings Batch**: Generate embeddings in batches during backfill
5. **Connection Pool**: Ensure adequate database connections for parallel searches

## Testing Strategy

### Unit Tests

```bash
# Provider tests
pytest tests/services/search_providers/test_notes_provider.py -v
pytest tests/services/search_providers/test_websites_provider.py -v
pytest tests/services/search_providers/test_files_provider.py -v
pytest tests/services/search_providers/test_conversations_provider.py -v
pytest tests/services/search_providers/test_memories_provider.py -v

# Service tests
pytest tests/services/test_universal_search_service.py -v
pytest tests/services/test_mcp_search_service.py -v
pytest tests/services/test_embedding_service.py -v

# Security tests
pytest tests/services/test_security_validator.py -v
```

### Integration Tests

```bash
# API endpoint tests
pytest tests/api/test_search_endpoint.py -v
pytest tests/api/test_mcp_endpoints.py -v

# Deep research flow tests
pytest tests/integration/test_deep_research_flows.py -v

# Citation tracking tests
pytest tests/integration/test_citation_tracking.py -v
```

### Performance Tests

```bash
# Latency benchmarks
pytest tests/performance/test_search_performance.py -v

# Parallel execution tests
pytest tests/performance/test_parallel_search.py -v

# Index effectiveness tests
pytest tests/performance/test_index_usage.py -v
```

### Manual Testing Checklist

- [ ] Run migration successfully
- [ ] Verify search vectors populated
- [ ] Verify embeddings generated (if in MVP)
- [ ] Test keyword search across all content types
- [ ] Test semantic search (if in MVP)
- [ ] Test hybrid search (if in MVP)
- [ ] Test filters (dates, folders, domains)
- [ ] Test AI tool from chat interface
- [ ] Test MCP search endpoint
- [ ] Test MCP fetch endpoint
- [ ] Test deep research mode with operation tracking
- [ ] Test background job execution
- [ ] Test rate limiting
- [ ] Test search chains (multi-step)
- [ ] Test citations in results
- [ ] Test iOS app integration
- [ ] Verify backward compatibility of existing endpoints

## Verification

### Database Verification

```sql
-- Check search vectors populated
SELECT
    (SELECT COUNT(*) FROM notes WHERE search_vector IS NOT NULL) as notes_fts,
    (SELECT COUNT(*) FROM websites WHERE search_vector IS NOT NULL) as websites_fts,
    (SELECT COUNT(*) FROM user_memories WHERE search_vector IS NOT NULL) as memories_fts,
    (SELECT COUNT(*) FROM conversations WHERE search_vector IS NOT NULL) as conversations_fts;

-- Check embeddings generated (if in MVP)
SELECT
    (SELECT COUNT(*) FROM notes WHERE embedding IS NOT NULL) as notes_vectors,
    (SELECT COUNT(*) FROM websites WHERE embedding IS NOT NULL) as websites_vectors,
    (SELECT COUNT(*) FROM user_memories WHERE embedding IS NOT NULL) as memories_vectors;

-- Check indexes exist
SELECT schemaname, tablename, indexname
FROM pg_indexes
WHERE indexname LIKE '%search_vector%' OR indexname LIKE '%embedding%';

-- Test FTS query performance
EXPLAIN ANALYZE
SELECT id, title, ts_rank(search_vector, plainto_tsquery('english', 'test')) as rank
FROM notes
WHERE search_vector @@ plainto_tsquery('english', 'test')
ORDER BY rank DESC
LIMIT 10;
```

### API Testing

```bash
# Test universal search
curl -X POST http://localhost:8000/api/v1/search \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "query": "machine learning",
    "content_types": ["note", "website"],
    "search_type": "keyword",
    "limit": 10
  }'

# Test MCP search
curl -X POST http://localhost:8000/api/v1/mcp/search \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "query": "machine learning",
    "limit": 5
  }'

# Test MCP fetch
curl -X POST http://localhost:8000/api/v1/mcp/fetch \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "id": "local:note:abc-123-def-456"
  }'

# Test deep research mode
curl -X POST http://localhost:8000/api/v1/search \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "query": "research topic",
    "mode": "deep_research",
    "search_type": "hybrid"
  }'
```

### AI Tool Testing

From the Claude chat interface:
```
Use the Search Local Knowledge tool to find all my notes about machine learning
from the last month. Show me the titles and creation dates.
```

Expected: Tool call with proper parameters, results with citations.

### Success Criteria

- ✅ All migrations run without errors
- ✅ Search vectors auto-update on insert/update
- ✅ FTS queries use GIN indexes (verify with EXPLAIN)
- ✅ Basic search completes in < 500ms
- ✅ Semantic search completes in < 300ms (if in MVP)
- ✅ AI tool accessible from chat
- ✅ Citations included in all results
- ✅ MCP endpoints return proper format
- ✅ Deep research mode tracks operations
- ✅ Background jobs execute successfully
- ✅ Rate limiting enforces limits
- ✅ iOS app can search and display results
- ✅ Existing search endpoints still work

## Future Enhancements

### Phase 7: Advanced Features (Post-MVP)

1. **Web Search Integration**
   - Add web search to MCP interface
   - Combine local + web results
   - Add source deduplication
   - Implement phased execution (local first, then web)

2. **Advanced Query Syntax**
   - Boolean operators (AND, OR, NOT)
   - Phrase matching ("exact phrase")
   - Field-specific search (title:foo content:bar)
   - Wildcards and fuzzy matching

3. **Saved Searches**
   - Save frequently used queries
   - Schedule periodic search execution
   - Email/notification on new results

4. **Search Analytics**
   - Track popular queries
   - Identify zero-result searches
   - Usage metrics dashboard
   - Query performance monitoring

5. **Autocomplete & Suggestions**
   - Query suggestions based on history
   - Autocomplete from content
   - Related searches
   - Spelling correction

6. **Enhanced Citations**
   - Return exact match positions for highlighting
   - Generate excerpts with match context
   - Citation formatting (APA, MLA, Chicago)
   - Export citations to reference managers

7. **Multi-Language Support**
   - Language-specific FTS configurations
   - Multilingual embeddings
   - Automatic language detection
   - Cross-language search

8. **Search Scopes**
   - Predefined collections ("Work", "Personal")
   - User-defined scopes
   - Scope-based access control
   - Share searches with team

9. **Advanced Ranking**
   - Learning-to-rank models
   - Personalized ranking based on usage
   - Boost recent/frequently accessed items
   - Custom ranking functions

10. **Export & Integration**
    - Export results to CSV/JSON
    - Integration with external tools (Notion, Obsidian)
    - Webhook notifications for new matches
    - API for third-party apps

## Migration Path

### From Existing Search Endpoints

**Current State** (`/notes/search`, `/websites/search`):
- Uses ILIKE queries
- Returns simple lists
- No citations
- No semantic search

**Migration Strategy**:
1. Keep existing endpoints for backward compatibility
2. Gradually migrate iOS app to universal endpoint
3. Add deprecation notices to old endpoints
4. Remove old endpoints in 6 months

**Deprecation Notice** (add to existing endpoints):
```python
@router.post("/search")
@deprecated(
    reason="Use /api/v1/search for improved search with citations",
    version="2.0",
    removal_version="3.0",
)
async def search_notes(...):
    # existing implementation
```

### For Existing Users

**Data Migration**:
- Migration automatically adds search vectors and embeddings columns
- Triggers ensure new content gets indexed automatically
- Backfill script generates embeddings for existing content
- No user action required

**API Changes**:
- New universal endpoint available immediately
- Old endpoints continue to work
- iOS app updated to use new endpoint in next release
- Web app (if exists) updated to use new endpoint

## Cost Estimation

### Development Time

- **Phase 1-2** (Foundation + Service): 2 weeks, 1 developer
- **Phase 3** (AI Integration): 1 week, 1 developer
- **Phase 4** (MCP Interface): 1 week, 1 developer
- **Phase 5** (Vector Search): 1 week, 1 developer
- **Phase 6** (Polish & Testing): 1 week, 1 developer

**Total**: 6 weeks, 1 full-time developer

### Infrastructure Costs

**Database**:
- PostgreSQL with pgvector: No additional cost (extension)
- Storage for embeddings: ~6KB per document (1536 dims × 4 bytes)
- 10K documents = ~60MB embeddings storage

**Embeddings API** (if using OpenAI/Anthropic):
- OpenAI: $0.00002 per 1K tokens for text-embedding-3-small
- 10K documents × 500 tokens avg = 5M tokens = $0.10 one-time
- Ongoing: New documents only

**Compute**:
- Search queries: Minimal CPU (< 100ms per query)
- Embedding generation: Can be batched, run off-peak

**Total Ongoing Cost**: < $10/month for 100K documents

## Documentation Deliverables

1. **API Reference** (`docs/api/UNIVERSAL_SEARCH.md`)
   - All endpoints with examples
   - Request/response schemas
   - Error codes and handling
   - Rate limits and quotas

2. **MCP Integration Guide** (`docs/api/MCP_INTERFACE.md`)
   - MCP server setup
   - OpenAI deep research integration
   - Search/fetch protocol details
   - Troubleshooting

3. **AI Tool Guide** (`docs/guides/DEEP_RESEARCH.md`)
   - How to use Search Local Knowledge tool
   - Deep research workflows
   - Multi-step search examples
   - Citation and provenance tracking

4. **Developer Guide** (`docs/guides/SEARCH_DEVELOPMENT.md`)
   - Architecture overview
   - Adding new content types
   - Customizing ranking
   - Performance tuning

5. **User Guide** (`docs/user/SEARCH_FEATURES.md`)
   - Search syntax and tips
   - Filtering and refinement
   - Understanding results
   - Citation usage

## Appendix

### Glossary

- **FTS**: Full-Text Search (PostgreSQL built-in feature)
- **GIN Index**: Generalized Inverted Index (for FTS)
- **pgvector**: PostgreSQL extension for vector similarity search
- **IVFFlat**: Inverted File with Flat compression (vector index type)
- **MCP**: Model Context Protocol (OpenAI's standard for tool integration)
- **Deep Research**: OpenAI's o3-deep-research model capability
- **tsvector**: PostgreSQL data type for tokenized text
- **tsquery**: PostgreSQL query type for text search

### References

- [PostgreSQL Full-Text Search](https://www.postgresql.org/docs/current/textsearch.html)
- [pgvector Documentation](https://github.com/pgvector/pgvector)
- [OpenAI Deep Research API](https://platform.openai.com/docs/guides/deep-research)
- [Model Context Protocol](https://modelcontextprotocol.io/)
- [FastAPI Background Tasks](https://fastapi.tiangolo.com/tutorial/background-tasks/)

### Contact

For questions or issues during implementation, contact the development team.
