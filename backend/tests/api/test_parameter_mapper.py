import json

from api.services.notes_document_types import note_document_from_plain_text
from api.services.tools import parameter_mapper


def test_derive_title_from_content_prefers_first_non_empty_line():
    content = "\n\n  First line  \nSecond line"
    assert parameter_mapper.derive_title_from_content(content) == "First line"


def test_derive_title_from_content_strips_markdown_heading_prefix():
    content = "\n# Heading Title\nBody"
    assert parameter_mapper.derive_title_from_content(content) == "# Heading Title"


def test_derive_title_from_content_truncates_long_line():
    content = "a" * 200
    title = parameter_mapper.derive_title_from_content(content)
    assert len(title) == 120
    assert title == "a" * 120


def test_derive_title_from_content_fallbacks():
    assert parameter_mapper.derive_title_from_content("") == "New Note"
    assert parameter_mapper.derive_title_from_content(None) == "New Note"


def test_build_fs_list_args_includes_recursive_and_user():
    args = parameter_mapper.build_fs_list_args(
        {"path": "/docs", "pattern": "*.md", "recursive": True, "user_id": "user-1"}
    )
    assert args == ["/docs", "--pattern", "*.md", "--recursive", "--user-id", "user-1"]


def test_build_fs_search_args_optional_flags():
    args = parameter_mapper.build_fs_search_args(
        {
            "directory": "/docs",
            "name_pattern": "*.py",
            "content_pattern": "TODO",
            "case_sensitive": True,
        }
    )
    assert args == [
        "--directory",
        "/docs",
        "--name",
        "*.py",
        "--content",
        "TODO",
        "--case-sensitive",
    ]


def test_build_fs_delete_args_recursive_and_user():
    args = parameter_mapper.build_fs_delete_args(
        {"path": "/docs/archive", "recursive": True, "user_id": "user-1"}
    )
    assert args == ["/docs/archive", "--recursive", "--user-id", "user-1"]


def test_build_fs_rename_args_with_dry_run():
    args = parameter_mapper.build_fs_rename_args(
        {
            "path": "/docs/old.txt",
            "new_name": "new.txt",
            "dry_run": True,
            "user_id": "user-1",
        }
    )
    assert args == ["/docs/old.txt", "new.txt", "--dry-run", "--user-id", "user-1"]


def test_build_fs_pin_args_false():
    args = parameter_mapper.build_fs_pin_args(
        {"path": "/docs/file.txt", "pinned": False, "user_id": "user-1"}
    )
    assert args == ["/docs/file.txt", "--pinned", "false", "--user-id", "user-1"]


def test_build_notes_create_args_use_document_and_tags():
    document = note_document_from_plain_text("My title\nBody")
    args = parameter_mapper.build_notes_create_args(
        {
            "document": document,
            "user_id": "user-1",
            "folder": "Inbox",
            "tags": ["a", "b"],
        }
    )
    assert args == [
        "--document",
        json.dumps(document),
        "--mode",
        "create",
        "--database",
        "--user-id",
        "user-1",
        "--folder",
        "Inbox",
        "--tags",
        "a,b",
    ]


def test_build_notes_update_args_use_document():
    document = note_document_from_plain_text("Body")
    args = parameter_mapper.build_notes_update_args(
        {
            "document": document,
            "note_id": "note-1",
        }
    )
    assert args == [
        "--document",
        json.dumps(document),
        "--mode",
        "update",
        "--note-id",
        "note-1",
        "--database",
    ]


def test_build_notes_edit_args_use_expected_updated_at_and_operations():
    build_args = getattr(parameter_mapper, "build_notes_edit_args", None)
    assert callable(build_args)

    operations = [
        {
            "type": "rename_note_title",
            "text": "Renamed title",
        },
        {
            "type": "delete_block",
            "index": 2,
        },
    ]

    args = build_args(
        {
            "note_id": "note-1",
            "expected_updated_at": "2026-03-29T10:30:00+00:00",
            "operations": operations,
            "user_id": "user-1",
        }
    )

    assert args == [
        "--note-id",
        "note-1",
        "--expected-updated-at",
        "2026-03-29T10:30:00+00:00",
        "--operations",
        json.dumps(operations),
        "--database",
        "--user-id",
        "user-1",
    ]


def test_build_notes_list_args_includes_false_values():
    args = parameter_mapper.build_notes_list_args(
        {"user_id": "user-1", "pinned": False, "archived": False}
    )
    assert args == [
        "--database",
        "--user-id",
        "user-1",
        "--pinned",
        "False",
        "--archived",
        "False",
    ]


def test_build_notes_archive_args_false():
    args = parameter_mapper.build_notes_archive_args(
        {"note_id": "note-1", "archived": False, "user_id": "user-1"}
    )
    assert args == [
        "note-1",
        "--archived",
        "false",
        "--database",
        "--user-id",
        "user-1",
    ]


def test_build_notes_download_args():
    args = parameter_mapper.build_notes_download_args(
        {"note_id": "note-1", "user_id": "user-1"}
    )
    assert args == ["note-1", "--database", "--user-id", "user-1"]


def test_build_notes_folder_args():
    assert parameter_mapper.build_notes_create_folder_args(
        {"path": "Projects/Alpha", "user_id": "user-1"}
    ) == ["Projects/Alpha", "--database", "--user-id", "user-1"]
    assert parameter_mapper.build_notes_rename_folder_args(
        {"old_path": "Projects/Alpha", "new_name": "Beta", "user_id": "user-1"}
    ) == [
        "Projects/Alpha",
        "--new-name",
        "Beta",
        "--database",
        "--user-id",
        "user-1",
    ]
    assert parameter_mapper.build_notes_move_folder_args(
        {"old_path": "Projects/Beta", "new_parent": "Archive", "user_id": "user-1"}
    ) == [
        "Projects/Beta",
        "--database",
        "--user-id",
        "user-1",
        "--new-parent",
        "Archive",
    ]
    assert parameter_mapper.build_notes_delete_folder_args(
        {"path": "Archive", "user_id": "user-1"}
    ) == ["Archive", "--database", "--user-id", "user-1"]


def test_build_website_add_args():
    args = parameter_mapper.build_website_add_args(
        {"url": "https://example.com/post", "user_id": "user-1"}
    )
    assert args == ["https://example.com/post", "--database", "--user-id", "user-1"]


def test_build_website_rename_args():
    args = parameter_mapper.build_website_rename_args(
        {"website_id": "web-1", "new_name": "Renamed Website", "user_id": "user-1"}
    )
    assert args == [
        "web-1",
        "--new-name",
        "Renamed Website",
        "--database",
        "--user-id",
        "user-1",
    ]


def test_build_conversations_search_args():
    args = parameter_mapper.build_conversations_search_args(
        {"query": "Lisbon", "limit": 5, "user_id": "user-1"}
    )
    assert args == ["Lisbon", "--user-id", "user-1", "--limit", "5"]


def test_build_conversations_rename_args():
    args = parameter_mapper.build_conversations_rename_args(
        {
            "conversation_id": "conv-1",
            "new_name": "Renamed Conversation",
            "user_id": "user-1",
        }
    )
    assert args == [
        "conv-1",
        "--user-id",
        "user-1",
        "--new-name",
        "Renamed Conversation",
    ]


def test_build_website_download_args():
    args = parameter_mapper.build_website_download_args(
        {"website_id": "web-1", "user_id": "user-1"}
    )
    assert args == ["web-1", "--database", "--user-id", "user-1"]


def test_build_youtube_transcribe_args_optional_fields():
    args = parameter_mapper.build_youtube_transcribe_args(
        {
            "url": "https://youtube.com/watch?v=123",
            "user_id": "user-1",
            "language": "en",
            "model": "tiny",
            "output_dir": "/tmp/out",
            "audio_dir": "/tmp/audio",
            "keep_audio": True,
            "folder": "Transcripts",
        }
    )
    assert args == [
        "https://youtube.com/watch?v=123",
        "--json",
        "--user-id",
        "user-1",
        "--language",
        "en",
        "--model",
        "tiny",
        "--output-dir",
        "/tmp/out",
        "--output-name",
        "ai.md",
        "--audio-dir",
        "/tmp/audio",
        "--keep-audio",
        "--folder",
        "Transcripts",
    ]


def test_build_assistant_identity_get_args():
    args = parameter_mapper.build_assistant_identity_get_args({"user_id": "user-1"})
    assert args == ["--user-id", "user-1"]


def test_build_assistant_identity_update_args_supports_partial_and_empty():
    args = parameter_mapper.build_assistant_identity_update_args(
        {
            "user_id": "user-1",
            "name": "Navigator",
            "tone": "",
            "reason": "User requested more direct responses.",
        }
    )
    assert args == [
        "--user-id",
        "user-1",
        "--name",
        "Navigator",
        "--tone",
        "",
        "--reason",
        "User requested more direct responses.",
    ]


def test_build_assistant_identity_reset_args():
    args = parameter_mapper.build_assistant_identity_reset_args(
        {"user_id": "user-1", "reason": "Resetting to baseline."}
    )
    assert args == ["--user-id", "user-1", "--reason", "Resetting to baseline."]


def test_build_assistant_soul_get_args():
    args = parameter_mapper.build_assistant_soul_get_args({"user_id": "user-1"})
    assert args == ["--user-id", "user-1"]


def test_build_assistant_soul_update_args_supports_partial_and_reason():
    args = parameter_mapper.build_assistant_soul_update_args(
        {
            "user_id": "user-1",
            "purpose": "Help me ship faster with fewer mistakes.",
            "reason": "Observed repeated planning requests.",
        }
    )
    assert args == [
        "--user-id",
        "user-1",
        "--purpose",
        "Help me ship faster with fewer mistakes.",
        "--reason",
        "Observed repeated planning requests.",
    ]


def test_build_assistant_soul_update_args_uses_kebab_case_for_all_fields():
    args = parameter_mapper.build_assistant_soul_update_args(
        {
            "user_id": "user-1",
            "purpose": "Purpose",
            "operating_principles": "Operating principles",
            "adaptation_policy": "Adaptation policy",
            "success_signals": "Success signals",
            "reason": "Bulk update",
        }
    )
    assert args == [
        "--user-id",
        "user-1",
        "--purpose",
        "Purpose",
        "--operating-principles",
        "Operating principles",
        "--adaptation-policy",
        "Adaptation policy",
        "--success-signals",
        "Success signals",
        "--reason",
        "Bulk update",
    ]


def test_build_assistant_soul_reset_args():
    args = parameter_mapper.build_assistant_soul_reset_args({"user_id": "user-1"})
    assert args == ["--user-id", "user-1"]
