"""Build CLI arguments for tool execution."""
from __future__ import annotations


def derive_title_from_content(content: str) -> str:
    if not isinstance(content, str):
        return "Untitled Note"
    for line in content.splitlines():
        stripped = line.strip()
        if stripped:
            return stripped[:120]
    return "Untitled Note"


def build_fs_list_args(params: dict) -> list:
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
    args = [params["path"]]
    if "start_line" in params:
        args.extend(["--start-line", str(params["start_line"])])
    if "end_line" in params:
        args.extend(["--end-line", str(params["end_line"])])
    if params.get("user_id"):
        args.extend(["--user-id", params["user_id"]])
    return args


def build_fs_write_args(params: dict) -> list:
    args = [params["path"], "--content", params["content"]]
    if params.get("dry_run"):
        args.append("--dry-run")
    if params.get("user_id"):
        args.extend(["--user-id", params["user_id"]])
    return args


def build_fs_search_args(params: dict) -> list:
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
    return [params["note_id"], "--database", "--user-id", params["user_id"]]


def build_notes_pin_args(params: dict) -> list:
    return [
        params["note_id"],
        "--pinned",
        str(params["pinned"]).lower(),
        "--database",
        "--user-id",
        params["user_id"],
    ]


def build_notes_move_args(params: dict) -> list:
    return [
        params["note_id"],
        "--folder",
        params["folder"],
        "--database",
        "--user-id",
        params["user_id"],
    ]


def build_notes_read_args(params: dict) -> list:
    return [params["note_id"], "--database", "--user-id", params["user_id"]]


def build_notes_list_args(params: dict) -> list:
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
    return ["--database", "--user-id", params["user_id"]]


def build_scratchpad_update_args(params: dict) -> list:
    return [
        "--content",
        params["content"],
        "--database",
        "--user-id",
        params["user_id"],
    ]


def build_scratchpad_clear_args(params: dict) -> list:
    return ["--database", "--user-id", params["user_id"]]


def build_website_save_args(params: dict) -> list:
    return [params["url"], "--database", "--user-id", params["user_id"]]


def build_website_delete_args(params: dict) -> list:
    return [params["website_id"], "--database", "--user-id", params["user_id"]]


def build_website_pin_args(params: dict) -> list:
    return [
        params["website_id"],
        "--pinned",
        str(params["pinned"]).lower(),
        "--database",
        "--user-id",
        params["user_id"],
    ]


def build_website_archive_args(params: dict) -> list:
    return [
        params["website_id"],
        "--archived",
        str(params["archived"]).lower(),
        "--database",
        "--user-id",
        params["user_id"],
    ]


def build_website_read_args(params: dict) -> list:
    return [params["website_id"], "--database", "--user-id", params["user_id"]]


def build_website_list_args(params: dict) -> list:
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
    args = [
        params["file_path"],
        "--json",
        "--database",
    ]
    if params.get("user_id"):
        args.extend(["--user-id", params["user_id"]])
    if params.get("language"):
        args.extend(["--language", params["language"]])
    if params.get("model"):
        args.extend(["--model", params["model"]])
    if params.get("output_dir"):
        args.extend(["--output-dir", params["output_dir"]])
    if params.get("folder"):
        args.extend(["--folder", params["folder"]])
    return args


def build_youtube_download_args(params: dict) -> list:
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
    args = [
        params["url"],
        "--json",
        "--database",
    ]
    if params.get("user_id"):
        args.extend(["--user-id", params["user_id"]])
    if params.get("language"):
        args.extend(["--language", params["language"]])
    if params.get("model"):
        args.extend(["--model", params["model"]])
    if params.get("output_dir"):
        args.extend(["--output-dir", params["output_dir"]])
    if params.get("audio_dir"):
        args.extend(["--audio-dir", params["audio_dir"]])
    if params.get("keep_audio"):
        args.append("--keep-audio")
    if params.get("folder"):
        args.extend(["--folder", params["folder"]])
    return args


def build_subdomain_discover_args(params: dict) -> list:
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
    return [params["input_file"], params["output_dir"]]


def build_docx_pack_args(params: dict) -> list:
    return [params["input_dir"], params["output_file"]]


def build_docx_validate_args(params: dict) -> list:
    args = [
        params["unpacked_dir"],
        "--original",
        params["original_file"],
    ]
    if params.get("verbose"):
        args.append("--verbose")
    return args


def build_pptx_inventory_args(params: dict) -> list:
    args = [
        params["input_pptx"],
        params["output_json"],
    ]
    if params.get("issues_only"):
        args.append("--issues-only")
    return args


def build_pptx_thumbnail_args(params: dict) -> list:
    args = [params["input_pptx"]]
    if params.get("output_prefix"):
        args.append(params["output_prefix"])
    if params.get("cols") is not None:
        args.extend(["--cols", str(params["cols"])])
    if params.get("outline_placeholders"):
        args.append("--outline-placeholders")
    return args


def build_xlsx_recalc_args(params: dict) -> list:
    args = [params["file_path"]]
    if params.get("timeout_seconds") is not None:
        args.append(str(params["timeout_seconds"]))
    return args


def build_skill_package_args(params: dict) -> list:
    args = [params["skill_dir"]]
    if params.get("output_dir"):
        args.append(params["output_dir"])
    return args


def build_mcp_evaluation_args(params: dict) -> list:
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
