"""Generated chat stream sync protocol constants."""

from __future__ import annotations

from dataclasses import dataclass

SYNC_PROTOCOL_VERSION = 1
CUSTOM_CHAT_STREAM_EVENT_TYPES = frozenset(
    {
        "collection_invalidated",
        "entity_changed",
        "entity_deleted",
        "prompt_preview",
        "tool_status",
        "workspace_patch",
    }
)
CHAT_STREAM_ENTITY_TYPES = frozenset(
    {
        "assistant_settings",
        "conversation",
        "ingestion",
        "memory",
        "note",
        "onboarding_state",
        "preferences",
        "profile",
        "scratchpad",
        "website",
        "workspace",
    }
)
CHAT_STREAM_CHANGE_TYPES = frozenset(
    {
        "archived",
        "cleared",
        "completed",
        "created",
        "deleted",
        "moved",
        "pinned",
        "renamed",
        "unarchived",
        "unpinned",
        "updated",
    }
)
CHAT_STREAM_EVENT_PAYLOAD_TYPES = {
    "collection_invalidated": "collection_invalidation",
    "entity_changed": "entity_change",
    "entity_deleted": "entity_delete",
    "prompt_preview": "prompt_preview",
    "tool_status": "tool_status",
    "workspace_patch": "workspace_patch",
}
CHAT_STREAM_EVENT_CLIENT_ACTIONS = {
    "collection_invalidated": "invalidate",
    "entity_changed": "patch_then_invalidate",
    "entity_deleted": "remove_then_invalidate",
    "prompt_preview": "replace",
    "tool_status": "status_only",
    "workspace_patch": "apply_patch",
}


@dataclass(frozen=True)
class ChatStreamSyncEventContract:
    """Generated payload metadata for one custom sync event."""

    payload: str
    client_action: str


@dataclass(frozen=True)
class ChatStreamSyncProtocol:
    """Generated chat stream sync protocol registry."""

    version: int
    custom_events: dict[str, ChatStreamSyncEventContract]
    entity_types: frozenset[str]
    change_types: frozenset[str]


def load_chat_stream_sync_protocol() -> ChatStreamSyncProtocol:
    """Return the generated chat stream sync protocol contract."""
    return ChatStreamSyncProtocol(
        version=SYNC_PROTOCOL_VERSION,
        custom_events={
            "collection_invalidated": ChatStreamSyncEventContract(
                payload="collection_invalidation",
                client_action="invalidate",
            ),
            "entity_changed": ChatStreamSyncEventContract(
                payload="entity_change",
                client_action="patch_then_invalidate",
            ),
            "entity_deleted": ChatStreamSyncEventContract(
                payload="entity_delete",
                client_action="remove_then_invalidate",
            ),
            "prompt_preview": ChatStreamSyncEventContract(
                payload="prompt_preview",
                client_action="replace",
            ),
            "tool_status": ChatStreamSyncEventContract(
                payload="tool_status",
                client_action="status_only",
            ),
            "workspace_patch": ChatStreamSyncEventContract(
                payload="workspace_patch",
                client_action="apply_patch",
            ),
        },
        entity_types=CHAT_STREAM_ENTITY_TYPES,
        change_types=CHAT_STREAM_CHANGE_TYPES,
    )
