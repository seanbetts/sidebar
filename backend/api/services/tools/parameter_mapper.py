"""Build CLI arguments for tool execution."""
from __future__ import annotations


def derive_title_from_content(content: str) -> str:
    """Derive a note title from content.

    Args:
        content: Markdown or plain text to scan for a title.

    Returns:
        A non-empty title capped at 120 characters.
    """
    if not isinstance(content, str):
        return "Untitled Note"
    for line in content.splitlines():
        stripped = line.strip()
        if stripped:
            return stripped[:120]
    return "Untitled Note"


def build_fs_list_args(params: dict) -> list:
    """Build CLI arguments for the fs list tool.

    Args:
        params: Tool parameters including path, pattern, recursive, user_id.

    Returns:
        CLI arguments list for fs list.
    """
    path = params.get("path", ".")
    pattern = params.get("pattern", "*")
    recursive = params.get("recursive", False)

    args = [path, "--pattern", pattern]
    if recursive:
        args.append("--recursive")
    if params.get("user_id"):
        args.extend(["--user-id", params["user_id"]])
    return args


def build_fs_read_args(params: dict) -> list:
    """Build CLI arguments for the fs read tool.

    Args:
        params: Tool parameters including path, start_line, end_line, user_id.

    Returns:
        CLI arguments list for fs read.
    """
    args = [params["path"]]
    if "start_line" in params:
        args.extend(["--start-line", str(params["start_line"])])
    if "end_line" in params:
        args.extend(["--end-line", str(params["end_line"])])
    if params.get("user_id"):
        args.extend(["--user-id", params["user_id"]])
    return args


def build_fs_write_args(params: dict) -> list:
    """Build CLI arguments for the fs write tool.

    Args:
        params: Tool parameters including path, content, dry_run, user_id.

    Returns:
        CLI arguments list for fs write.
    """
    args = [params["path"], "--content", params["content"]]
    if params.get("dry_run"):
        args.append("--dry-run")
    if params.get("user_id"):
        args.extend(["--user-id", params["user_id"]])
    return args


def build_fs_search_args(params: dict) -> list:
    """Build CLI arguments for the fs search tool.

    Args:
        params: Tool parameters including directory, name_pattern, content_pattern,
            case_sensitive, user_id.

    Returns:
        CLI arguments list for fs search.
    """
    directory = params.get("directory", ".")
    name_pattern = params.get("name_pattern")
    content_pattern = params.get("content_pattern")
    case_sensitive = params.get("case_sensitive", False)

    args = ["--directory", directory]
    if name_pattern:
        args.extend(["--name", name_pattern])
    if content_pattern:
        args.extend(["--content", content_pattern])
    if case_sensitive:
        args.append("--case-sensitive")
    if params.get("user_id"):
        args.extend(["--user-id", params["user_id"]])
    return args


def build_notes_create_args(params: dict) -> list:
    """Build CLI arguments for notes create.

    Args:
        params: Tool parameters including content, title, folder, tags, user_id.

    Returns:
        CLI arguments list for notes create.
    """
    title = params.get("title") or derive_title_from_content(params.get("content", ""))
    user_id = params.get("user_id", "")
    args = [
        title,
        "--content",
        params["content"],
        "--mode",
        "create",
        "--database",
    ]
    if user_id:
        args.extend(["--user-id", user_id])
    if "folder" in params:
        args.extend(["--folder", params["folder"]])
    if "tags" in params:
        args.extend(["--tags", ",".join(params["tags"])])
    return args


def build_notes_update_args(params: dict) -> list:
    """Build CLI arguments for notes update.

    Args:
        params: Tool parameters including note_id, content, title, user_id.

    Returns:
        CLI arguments list for notes update.
    """
    title = params.get("title") or derive_title_from_content(params.get("content", ""))
    user_id = params.get("user_id", "")
    args = [
        title,
        "--content",
        params["content"],
        "--mode",
        "update",
        "--note-id",
        params["note_id"],
        "--database",
    ]
    if user_id:
        args.extend(["--user-id", user_id])
    return args


def build_notes_delete_args(params: dict) -> list:
    """Build CLI arguments for notes delete.

    Args:
        params: Tool parameters including note_id and user_id.

    Returns:
        CLI arguments list for notes delete.
    """
    return [params["note_id"], "--database", "--user-id", params["user_id"]]


def build_notes_pin_args(params: dict) -> list:
    """Build CLI arguments for notes pin/unpin.

    Args:
        params: Tool parameters including note_id, pinned, user_id.

    Returns:
        CLI arguments list for notes pin.
    """
    return [
        params["note_id"],
        "--pinned",
        str(params["pinned"]).lower(),
        "--database",
        "--user-id",
        params["user_id"],
    ]


def build_notes_move_args(params: dict) -> list:
    """Build CLI arguments for notes move.

    Args:
        params: Tool parameters including note_id, folder, user_id.

    Returns:
        CLI arguments list for notes move.
    """
    return [
        params["note_id"],
        "--folder",
        params["folder"],
        "--database",
        "--user-id",
        params["user_id"],
    ]


def build_notes_read_args(params: dict) -> list:
    """Build CLI arguments for notes read.

    Args:
        params: Tool parameters including note_id and user_id.

    Returns:
        CLI arguments list for notes read.
    """
    return [params["note_id"], "--database", "--user-id", params["user_id"]]


def build_notes_list_args(params: dict) -> list:
    """Build CLI arguments for notes list.

    Args:
        params: Tool parameters including filters and user_id.

    Returns:
        CLI arguments list for notes list.
    """
    args = ["--database"]
    user_id = params.get("user_id")
    if user_id:
        args.extend(["--user-id", user_id])
    for key, flag in [
        ("folder", "--folder"),
        ("pinned", "--pinned"),
        ("archived", "--archived"),
        ("created_after", "--created-after"),
        ("created_before", "--created-before"),
        ("updated_after", "--updated-after"),
        ("updated_before", "--updated-before"),
        ("opened_after", "--opened-after"),
        ("opened_before", "--opened-before"),
        ("title", "--title"),
    ]:
        value = params.get(key)
        if value is not None:
            args.extend([flag, str(value)])
    return args


def build_scratchpad_get_args(params: dict) -> list:
    """Build CLI arguments for scratchpad get.

    Args:
        params: Tool parameters including user_id.

    Returns:
        CLI arguments list for scratchpad get.
    """
    return ["--database", "--user-id", params["user_id"]]


def build_scratchpad_update_args(params: dict) -> list:
    """Build CLI arguments for scratchpad update.

    Args:
        params: Tool parameters including content and user_id.

    Returns:
        CLI arguments list for scratchpad update.
    """
    return [
        "--content",
        params["content"],
        "--database",
        "--user-id",
        params["user_id"],
    ]


def build_scratchpad_clear_args(params: dict) -> list:
    """Build CLI arguments for scratchpad clear.

    Args:
        params: Tool parameters including user_id.

    Returns:
        CLI arguments list for scratchpad clear.
    """
    return ["--database", "--user-id", params["user_id"]]


def build_website_save_args(params: dict) -> list:
    """Build CLI arguments for website save.

    Args:
        params: Tool parameters including url and user_id.

    Returns:
        CLI arguments list for website save.
    """
    return [params["url"], "--database", "--user-id", params["user_id"]]


def build_website_delete_args(params: dict) -> list:
    """Build CLI arguments for website delete.

    Args:
        params: Tool parameters including website_id and user_id.

    Returns:
        CLI arguments list for website delete.
    """
    return [params["website_id"], "--database", "--user-id", params["user_id"]]


def build_website_pin_args(params: dict) -> list:
    """Build CLI arguments for website pin/unpin.

    Args:
        params: Tool parameters including website_id, pinned, user_id.

    Returns:
        CLI arguments list for website pin.
    """
    return [
        params["website_id"],
        "--pinned",
        str(params["pinned"]).lower(),
        "--database",
        "--user-id",
        params["user_id"],
    ]


def build_website_archive_args(params: dict) -> list:
    """Build CLI arguments for website archive/unarchive.

    Args:
        params: Tool parameters including website_id, archived, user_id.

    Returns:
        CLI arguments list for website archive.
    """
    return [
        params["website_id"],
        "--archived",
        str(params["archived"]).lower(),
        "--database",
        "--user-id",
        params["user_id"],
    ]


def build_website_read_args(params: dict) -> list:
    """Build CLI arguments for website read.

    Args:
        params: Tool parameters including website_id and user_id.

    Returns:
        CLI arguments list for website read.
    """
    return [params["website_id"], "--database", "--user-id", params["user_id"]]


def build_website_list_args(params: dict) -> list:
    """Build CLI arguments for website list.

    Args:
        params: Tool parameters including filters and user_id.

    Returns:
        CLI arguments list for website list.
    """
    args = ["--database"]
    user_id = params.get("user_id")
    if user_id:
        args.extend(["--user-id", user_id])
    for key, flag in [
        ("domain", "--domain"),
        ("pinned", "--pinned"),
        ("archived", "--archived"),
        ("created_after", "--created-after"),
        ("created_before", "--created-before"),
        ("updated_after", "--updated-after"),
        ("updated_before", "--updated-before"),
        ("opened_after", "--opened-after"),
        ("opened_before", "--opened-before"),
        ("published_after", "--published-after"),
        ("published_before", "--published-before"),
        ("title", "--title"),
    ]:
        value = params.get(key)
        if value is not None:
            args.extend([flag, str(value)])
    return args


def build_audio_transcribe_args(params: dict) -> list:
    """Build CLI arguments for audio transcription.

    Args:
        params: Tool parameters including file_path, language, model, output_dir,
            folder, user_id.

    Returns:
        CLI arguments list for audio transcription.
    """
    file_path = params["file_path"]
    args = [
        file_path,
        "--json",
    ]
    if params.get("user_id"):
        args.extend(["--user-id", params["user_id"]])
    if params.get("language"):
        args.extend(["--language", params["language"]])
    if params.get("model"):
        args.extend(["--model", params["model"]])
    output_dir = params.get("output_dir")
    output_name = params.get("output_name") or "ai.md"
    if not output_dir:
        parts = str(file_path).strip("/").split("/")
        if len(parts) >= 2 and parts[0] == "files":
            output_dir = f"files/{parts[1]}/ai"
        else:
            output_dir = "files/transcripts"
    if output_dir:
        args.extend(["--output-dir", output_dir])
    if output_name:
        args.extend(["--output-name", output_name])
    if params.get("folder"):
        args.extend(["--folder", params["folder"]])
    return args


def build_youtube_download_args(params: dict) -> list:
    """Build CLI arguments for YouTube download.

    Args:
        params: Tool parameters including url, audio_only, playlist, output_dir,
            user_id.

    Returns:
        CLI arguments list for YouTube download.
    """
    args = [
        params["url"],
        "--json",
    ]
    if params.get("user_id"):
        args.extend(["--user-id", params["user_id"]])
    if params.get("audio_only"):
        args.append("--audio")
    if params.get("playlist"):
        args.append("--playlist")
    if params.get("output_dir"):
        args.extend(["--output", params["output_dir"]])
    return args


def build_youtube_transcribe_args(params: dict) -> list:
    """Build CLI arguments for YouTube transcription.

    Args:
        params: Tool parameters including url, language, model, output_dir,
            audio_dir, keep_audio, folder, user_id.

    Returns:
        CLI arguments list for YouTube transcription.
    """
    args = [
        params["url"],
        "--json",
    ]
    if params.get("user_id"):
        args.extend(["--user-id", params["user_id"]])
    if params.get("language"):
        args.extend(["--language", params["language"]])
    if params.get("model"):
        args.extend(["--model", params["model"]])
    output_dir = params.get("output_dir")
    output_name = params.get("output_name") or "ai.md"
    if output_dir:
        args.extend(["--output-dir", output_dir])
    if output_name:
        args.extend(["--output-name", output_name])
    if params.get("audio_dir"):
        args.extend(["--audio-dir", params["audio_dir"]])
    if params.get("keep_audio"):
        args.append("--keep-audio")
    if params.get("folder"):
        args.extend(["--folder", params["folder"]])
    return args


def build_subdomain_discover_args(params: dict) -> list:
    """Build CLI arguments for subdomain discovery.

    Args:
        params: Tool parameters including domain and optional flags.

    Returns:
        CLI arguments list for subdomain discovery.
    """
    args = [
        params["domain"],
        "--json",
    ]
    if params.get("wordlist"):
        args.extend(["--wordlist", params["wordlist"]])
    if params.get("timeout") is not None:
        args.extend(["--timeout", str(params["timeout"])])
    if params.get("dns_timeout") is not None:
        args.extend(["--dns-timeout", str(params["dns_timeout"])])
    if params.get("no_filter"):
        args.append("--no-filter")
    if params.get("verbose"):
        args.append("--verbose")
    return args


def build_crawler_policy_args(params: dict) -> list:
    """Build CLI arguments for crawler policy analysis.

    Args:
        params: Tool parameters including domain and optional flags.

    Returns:
        CLI arguments list for crawler policy analysis.
    """
    args = [
        params["domain"],
        "--json",
    ]
    if params.get("user_id"):
        args.extend(["--user-id", params["user_id"]])
    if params.get("no_discover"):
        args.append("--no-discover")
    if params.get("wordlist"):
        args.extend(["--wordlist", params["wordlist"]])
    if params.get("timeout") is not None:
        args.extend(["--timeout", str(params["timeout"])])
    if params.get("dns_timeout") is not None:
        args.extend(["--dns-timeout", str(params["dns_timeout"])])
    if params.get("no_llms"):
        args.append("--no-llms")
    return args


def build_docx_unpack_args(params: dict) -> list:
    """Build CLI arguments for docx unpack.

    Args:
        params: Tool parameters including input_file and output_dir.

    Returns:
        CLI arguments list for docx unpack.
    """
    return [params["input_file"], params["output_dir"]]


def build_docx_pack_args(params: dict) -> list:
    """Build CLI arguments for docx pack.

    Args:
        params: Tool parameters including input_dir and output_file.

    Returns:
        CLI arguments list for docx pack.
    """
    return [params["input_dir"], params["output_file"]]


def build_docx_validate_args(params: dict) -> list:
    """Build CLI arguments for docx validation.

    Args:
        params: Tool parameters including unpacked_dir, original_file, verbose.

    Returns:
        CLI arguments list for docx validation.
    """
    args = [
        params["unpacked_dir"],
        "--original",
        params["original_file"],
    ]
    if params.get("verbose"):
        args.append("--verbose")
    return args


def build_pptx_inventory_args(params: dict) -> list:
    """Build CLI arguments for pptx inventory.

    Args:
        params: Tool parameters including input_pptx, output_json, issues_only.

    Returns:
        CLI arguments list for pptx inventory.
    """
    args = [
        params["input_pptx"],
        params["output_json"],
    ]
    if params.get("issues_only"):
        args.append("--issues-only")
    return args


def build_pptx_thumbnail_args(params: dict) -> list:
    """Build CLI arguments for pptx thumbnail generation.

    Args:
        params: Tool parameters including input_pptx, output_prefix, cols,
            outline_placeholders.

    Returns:
        CLI arguments list for pptx thumbnail generation.
    """
    args = [params["input_pptx"]]
    if params.get("output_prefix"):
        args.append(params["output_prefix"])
    if params.get("cols") is not None:
        args.extend(["--cols", str(params["cols"])])
    if params.get("outline_placeholders"):
        args.append("--outline-placeholders")
    return args


def build_xlsx_recalc_args(params: dict) -> list:
    """Build CLI arguments for xlsx recalc.

    Args:
        params: Tool parameters including file_path and timeout_seconds.

    Returns:
        CLI arguments list for xlsx recalc.
    """
    args = [params["file_path"]]
    if params.get("timeout_seconds") is not None:
        args.append(str(params["timeout_seconds"]))
    return args


def build_skill_package_args(params: dict) -> list:
    """Build CLI arguments for skill packaging.

    Args:
        params: Tool parameters including skill_dir and output_dir.

    Returns:
        CLI arguments list for skill packaging.
    """
    args = [params["skill_dir"]]
    if params.get("output_dir"):
        args.append(params["output_dir"])
    return args


def build_mcp_evaluation_args(params: dict) -> list:
    """Build CLI arguments for MCP evaluation runs.

    Args:
        params: Tool parameters including eval_file and optional flags.

    Returns:
        CLI arguments list for MCP evaluation.
    """
    args = [params["eval_file"]]
    if params.get("transport"):
        args.extend(["--transport", params["transport"]])
    if params.get("model"):
        args.extend(["--model", params["model"]])
    if params.get("command"):
        args.extend(["--command", params["command"]])
    if params.get("args"):
        args.extend(["--args", *params["args"]])
    if params.get("env"):
        args.extend(["--env", *params["env"]])
    if params.get("url"):
        args.extend(["--url", params["url"]])
    if params.get("headers"):
        args.extend(["--header", *params["headers"]])
    if params.get("output"):
        args.extend(["--output", params["output"]])
    return args
