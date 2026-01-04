from api.services.tools import parameter_mapper


def test_derive_title_from_content_prefers_first_non_empty_line():
    content = "\n\n  First line  \nSecond line"
    assert parameter_mapper.derive_title_from_content(content) == "First line"


def test_derive_title_from_content_truncates_long_line():
    content = "a" * 200
    title = parameter_mapper.derive_title_from_content(content)
    assert len(title) == 120
    assert title == "a" * 120


def test_derive_title_from_content_fallbacks():
    assert parameter_mapper.derive_title_from_content("") == "Untitled Note"
    assert parameter_mapper.derive_title_from_content(None) == "Untitled Note"


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


def test_build_notes_create_args_derives_title_and_tags():
    args = parameter_mapper.build_notes_create_args(
        {
            "content": "My title\nBody",
            "user_id": "user-1",
            "folder": "Inbox",
            "tags": ["a", "b"],
        }
    )
    assert args == [
        "My title",
        "--content",
        "My title\nBody",
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


def test_build_notes_update_args_uses_explicit_title():
    args = parameter_mapper.build_notes_update_args(
        {
            "title": "Custom",
            "content": "Body",
            "note_id": "note-1",
        }
    )
    assert args == [
        "Custom",
        "--content",
        "Body",
        "--mode",
        "update",
        "--note-id",
        "note-1",
        "--database",
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
