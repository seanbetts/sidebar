"""Central tool definitions for ToolMapper."""
from __future__ import annotations

from api.services.tools import parameter_mapper as pm


def get_tool_definitions() -> dict:
    return {
        "Browse Files": {
            "description": "List files and directories in R2-backed storage with glob pattern support",
            "input_schema": {
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "Directory path (default: '.')"},
                    "pattern": {"type": "string", "description": "Glob pattern (default: '*')"},
                    "recursive": {"type": "boolean", "description": "Search recursively"},
                },
                "required": [],
            },
            "skill": "fs",
            "script": "list.py",
            "build_args": pm.build_fs_list_args,
            "validate_read": True,
        },
        "Read File": {
            "description": "Read file content from R2-backed storage",
            "input_schema": {
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "File path to read"},
                    "start_line": {"type": "integer", "description": "Start line number (optional)"},
                    "end_line": {"type": "integer", "description": "End line number (optional)"},
                },
                "required": ["path"],
            },
            "skill": "fs",
            "script": "read.py",
            "build_args": pm.build_fs_read_args,
            "validate_read": True,
        },
        "Write File": {
            "description": "Write content to file in R2-backed storage for project files and documents. For persistent, searchable notes use Create Note instead.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "File path to write"},
                    "content": {"type": "string", "description": "Content to write"},
                    "dry_run": {"type": "boolean", "description": "Preview without executing"},
                },
                "required": ["path", "content"],
            },
            "skill": "fs",
            "script": "write.py",
            "build_args": pm.build_fs_write_args,
            "validate_write": True,
        },
        "Search Files": {
            "description": "Search for files by name pattern or content in R2-backed storage",
            "input_schema": {
                "type": "object",
                "properties": {
                    "directory": {"type": "string", "description": "Directory to search (default: '.')"},
                    "name_pattern": {
                        "type": "string",
                        "description": "Filename pattern (* and ? wildcards)",
                    },
                    "content_pattern": {"type": "string", "description": "Content pattern (regex)"},
                    "case_sensitive": {"type": "boolean", "description": "Case-sensitive search"},
                },
            },
            "skill": "fs",
            "script": "search.py",
            "build_args": pm.build_fs_search_args,
            "validate_read": True,
        },
        "Unpack DOCX": {
            "description": "Unpack a .docx file into an OOXML directory.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "input_file": {"type": "string", "description": "Path to .docx file"},
                    "output_dir": {"type": "string", "description": "Output directory"},
                },
                "required": ["input_file", "output_dir"],
            },
            "skill": "docx",
            "script": "ooxml/scripts/unpack.py",
            "build_args": pm.build_docx_unpack_args,
            "expect_json": False,
        },
        "Pack DOCX": {
            "description": "Pack an OOXML directory into a .docx file.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "input_dir": {"type": "string", "description": "Unpacked OOXML directory"},
                    "output_file": {"type": "string", "description": "Output .docx path"},
                },
                "required": ["input_dir", "output_file"],
            },
            "skill": "docx",
            "script": "ooxml/scripts/pack.py",
            "build_args": pm.build_docx_pack_args,
            "expect_json": False,
        },
        "Validate DOCX": {
            "description": "Validate an unpacked .docx directory against the original file.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "unpacked_dir": {"type": "string", "description": "Unpacked OOXML directory"},
                    "original_file": {"type": "string", "description": "Original .docx file"},
                    "verbose": {"type": "boolean", "description": "Verbose output"},
                },
                "required": ["unpacked_dir", "original_file"],
            },
            "skill": "docx",
            "script": "ooxml/scripts/validate.py",
            "build_args": pm.build_docx_validate_args,
            "expect_json": False,
        },
        "Inventory PPTX": {
            "description": "Generate an inventory report for a PowerPoint file.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "input_pptx": {"type": "string", "description": "Path to .pptx file"},
                    "output_json": {"type": "string", "description": "Output JSON path"},
                    "issues_only": {"type": "boolean", "description": "Only include slides with issues"},
                },
                "required": ["input_pptx", "output_json"],
            },
            "skill": "pptx",
            "script": "pptx/inventory.py",
            "build_args": pm.build_pptx_inventory_args,
        },
        "Render PPTX Thumbnails": {
            "description": "Render PPTX slide thumbnails to PNG.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "input_pptx": {"type": "string", "description": "Path to .pptx file"},
                    "output_prefix": {"type": "string", "description": "Optional output prefix"},
                    "cols": {"type": "integer", "description": "Columns per sheet"},
                    "outline_placeholders": {
                        "type": "boolean",
                        "description": "Include outline placeholders",
                    },
                },
                "required": ["input_pptx"],
            },
            "skill": "pptx",
            "script": "pptx/render_thumbnails.py",
            "build_args": pm.build_pptx_thumbnail_args,
        },
        "Validate PDF": {
            "description": "Validate a PDF file with pdfcpu.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "input_file": {"type": "string", "description": "Path to PDF file"},
                },
                "required": ["input_file"],
            },
            "skill": "pdf",
            "script": "validate.py",
            "build_args": lambda p: [p["input_file"]],
            "expect_json": False,
        },
        "Merge PDFs": {
            "description": "Merge multiple PDFs into a single output file.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "input_files": {"type": "array", "items": {"type": "string"}},
                    "output_file": {"type": "string"},
                },
                "required": ["input_files", "output_file"],
            },
            "skill": "pdf",
            "script": "merge.py",
            "build_args": lambda p: [*p["input_files"], p["output_file"]],
            "expect_json": False,
        },
        "Split PDF": {
            "description": "Split a PDF by page range.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "input_file": {"type": "string"},
                    "output_dir": {"type": "string"},
                    "pages": {"type": "string", "description": "Page ranges to extract"},
                },
                "required": ["input_file", "output_dir"],
            },
            "skill": "pdf",
            "script": "split.py",
            "build_args": lambda p: [p["input_file"], p["output_dir"], p.get("pages", "")],
            "expect_json": False,
        },
        "Extract PDF Text": {
            "description": "Extract text from a PDF file.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "input_file": {"type": "string"},
                },
                "required": ["input_file"],
            },
            "skill": "pdf",
            "script": "extract_text.py",
            "build_args": lambda p: [p["input_file"]],
            "expect_json": False,
        },
        "Recalculate XLSX": {
            "description": "Recalculate formulas in an .xlsx file.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "file_path": {"type": "string", "description": "Path to .xlsx file"},
                    "timeout_seconds": {"type": "integer", "description": "Timeout in seconds (optional)"},
                },
                "required": ["file_path"],
            },
            "skill": "xlsx",
            "script": "recalculate.py",
            "build_args": pm.build_xlsx_recalc_args,
        },
        "Package Skill": {
            "description": "Package a skill folder into a zip archive.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "skill_dir": {"type": "string", "description": "Path to skill directory"},
                    "output_dir": {"type": "string", "description": "Output directory"},
                },
                "required": ["skill_dir"],
            },
            "skill": "skill-creator",
            "script": "package_skill.py",
            "build_args": pm.build_skill_package_args,
        },
        "Evaluate MCP Server": {
            "description": "Run an MCP evaluation script.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "eval_file": {"type": "string", "description": "Path to evaluation YAML"},
                    "transport": {"type": "string"},
                    "model": {"type": "string"},
                    "command": {"type": "string"},
                    "args": {"type": "array", "items": {"type": "string"}},
                    "env": {"type": "array", "items": {"type": "string"}},
                    "url": {"type": "string"},
                    "headers": {"type": "array", "items": {"type": "string"}},
                    "output": {"type": "string"},
                },
                "required": ["eval_file"],
            },
            "skill": "mcp-builder",
            "script": "evaluate_mcp.py",
            "build_args": pm.build_mcp_evaluation_args,
        },
        "Discover Subdomains": {
            "description": "Discover subdomains for a given domain.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "domain": {"type": "string"},
                    "wordlist": {"type": "string"},
                    "timeout": {"type": "integer"},
                    "dns_timeout": {"type": "integer"},
                    "no_filter": {"type": "boolean"},
                    "verbose": {"type": "boolean"},
                },
                "required": ["domain"],
            },
            "skill": "subdomain-discover",
            "script": "discover_subdomains.py",
            "build_args": pm.build_subdomain_discover_args,
        },
        "Crawler Policy Check": {
            "description": "Analyze a site's crawler policy for robots.txt and llms.txt.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "domain": {"type": "string"},
                    "no_discover": {"type": "boolean"},
                    "wordlist": {"type": "string"},
                    "timeout": {"type": "integer"},
                    "dns_timeout": {"type": "integer"},
                    "no_llms": {"type": "boolean"},
                },
                "required": ["domain"],
            },
            "skill": "web-crawler-policy",
            "script": "analyze_policies.py",
            "build_args": pm.build_crawler_policy_args,
        },
        "Transcribe Audio": {
            "description": "Transcribe an audio file into text and save it as a note.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "file_path": {"type": "string", "description": "Path to audio file"},
                    "language": {"type": "string", "description": "Language code (optional)"},
                    "model": {"type": "string", "description": "Transcription model (optional)"},
                    "output_dir": {"type": "string", "description": "Transcript output directory (optional)"},
                    "folder": {"type": "string", "description": "Notes folder for transcript (optional)"},
                },
                "required": ["file_path"],
            },
            "skill": "audio-transcribe",
            "script": "transcribe_audio.py",
            "build_args": pm.build_audio_transcribe_args,
        },
        "Download YouTube": {
            "description": "Download YouTube video or audio to R2 (Videos folder by default).",
            "input_schema": {
                "type": "object",
                "properties": {
                    "url": {"type": "string", "description": "YouTube URL"},
                    "audio_only": {"type": "boolean", "description": "Download audio only"},
                    "playlist": {"type": "boolean", "description": "Download entire playlist"},
                    "output_dir": {"type": "string", "description": "Output directory (optional)"},
                },
                "required": ["url"],
            },
            "skill": "youtube-download",
            "script": "download_video.py",
            "build_args": pm.build_youtube_download_args,
        },
        "Transcribe YouTube": {
            "description": "Download YouTube audio, transcribe it, and save it as a note.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "url": {"type": "string", "description": "YouTube URL"},
                    "language": {"type": "string", "description": "Language code (optional)"},
                    "model": {"type": "string", "description": "Transcription model (optional)"},
                    "output_dir": {"type": "string", "description": "Transcript output directory (optional)"},
                    "audio_dir": {"type": "string", "description": "Audio output directory (optional)"},
                    "keep_audio": {"type": "boolean", "description": "Keep audio file after transcription"},
                    "folder": {"type": "string", "description": "Notes folder for transcript (optional)"},
                },
                "required": ["url"],
            },
            "skill": "youtube-transcribe",
            "script": "transcribe_youtube.py",
            "build_args": pm.build_youtube_transcribe_args,
        },
        "Create Note": {
            "description": "Create a searchable, persistent markdown note in the database with metadata. Notes are visible in the UI and fully searchable. Preferred for remembering information across sessions.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "title": {
                        "type": "string",
                        "description": "Optional note title (defaults to first line of content)",
                    },
                    "content": {"type": "string", "description": "Markdown content"},
                    "folder": {"type": "string", "description": "Optional folder path"},
                    "tags": {"type": "array", "items": {"type": "string"}},
                },
                "required": ["content"],
            },
            "skill": "notes",
            "script": "save_markdown.py",
            "build_args": pm.build_notes_create_args,
        },
        "Update Note": {
            "description": "Update an existing note in the database by ID.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "note_id": {"type": "string", "description": "Note UUID"},
                    "title": {"type": "string", "description": "Optional note title"},
                    "content": {"type": "string", "description": "Markdown content"},
                },
                "required": ["note_id", "content"],
            },
            "skill": "notes",
            "script": "save_markdown.py",
            "build_args": pm.build_notes_update_args,
        },
        "Delete Note": {
            "description": "Delete a note in the database by ID.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "note_id": {"type": "string", "description": "Note UUID"},
                },
                "required": ["note_id"],
            },
            "skill": "notes",
            "script": "delete_note.py",
            "build_args": pm.build_notes_delete_args,
        },
        "Pin Note": {
            "description": "Pin or unpin a note in the database.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "note_id": {"type": "string", "description": "Note UUID"},
                    "pinned": {"type": "boolean", "description": "Pin state"},
                },
                "required": ["note_id", "pinned"],
            },
            "skill": "notes",
            "script": "pin_note.py",
            "build_args": pm.build_notes_pin_args,
        },
        "Move Note": {
            "description": "Move a note to a folder by ID.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "note_id": {"type": "string", "description": "Note UUID"},
                    "folder": {"type": "string", "description": "Destination folder path"},
                },
                "required": ["note_id", "folder"],
            },
            "skill": "notes",
            "script": "move_note.py",
            "build_args": pm.build_notes_move_args,
        },
        "Get Note": {
            "description": "Fetch a note by ID.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "note_id": {"type": "string", "description": "Note UUID"},
                },
                "required": ["note_id"],
            },
            "skill": "notes",
            "script": "read_note.py",
            "build_args": pm.build_notes_read_args,
        },
        "List Notes": {
            "description": "List notes with optional filters.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "folder": {"type": "string"},
                    "pinned": {"type": "boolean"},
                    "archived": {"type": "boolean"},
                    "created_after": {"type": "string"},
                    "created_before": {"type": "string"},
                    "updated_after": {"type": "string"},
                    "updated_before": {"type": "string"},
                    "opened_after": {"type": "string"},
                    "opened_before": {"type": "string"},
                    "title": {"type": "string"},
                },
            },
            "skill": "notes",
            "script": "list_notes.py",
            "build_args": pm.build_notes_list_args,
        },
        "Get Scratchpad": {
            "description": "Fetch the scratchpad note.",
            "input_schema": {
                "type": "object",
                "properties": {},
            },
            "skill": "notes",
            "script": "scratchpad_get.py",
            "build_args": pm.build_scratchpad_get_args,
        },
        "Update Scratchpad": {
            "description": "Update the scratchpad content.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "content": {"type": "string"},
                },
                "required": ["content"],
            },
            "skill": "notes",
            "script": "scratchpad_update.py",
            "build_args": pm.build_scratchpad_update_args,
        },
        "Clear Scratchpad": {
            "description": "Clear the scratchpad content.",
            "input_schema": {
                "type": "object",
                "properties": {},
            },
            "skill": "notes",
            "script": "scratchpad_clear.py",
            "build_args": pm.build_scratchpad_clear_args,
        },
        "Save Website": {
            "description": "Save a website to the database (visible in UI).",
            "input_schema": {
                "type": "object",
                "properties": {
                    "url": {"type": "string", "description": "Website URL"},
                },
                "required": ["url"],
            },
            "skill": "web-save",
            "script": "save_url.py",
            "build_args": pm.build_website_save_args,
        },
        "Delete Website": {
            "description": "Delete a website in the database by ID.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "website_id": {"type": "string", "description": "Website UUID"},
                },
                "required": ["website_id"],
            },
            "skill": "web-save",
            "script": "delete_website.py",
            "build_args": pm.build_website_delete_args,
        },
        "Pin Website": {
            "description": "Pin or unpin a website in the database.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "website_id": {"type": "string"},
                    "pinned": {"type": "boolean"},
                },
                "required": ["website_id", "pinned"],
            },
            "skill": "web-save",
            "script": "pin_website.py",
            "build_args": pm.build_website_pin_args,
        },
        "Archive Website": {
            "description": "Archive or unarchive a website in the database.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "website_id": {"type": "string"},
                    "archived": {"type": "boolean"},
                },
                "required": ["website_id", "archived"],
            },
            "skill": "web-save",
            "script": "archive_website.py",
            "build_args": pm.build_website_archive_args,
        },
        "Read Website": {
            "description": "Fetch a website by ID.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "website_id": {"type": "string"},
                },
                "required": ["website_id"],
            },
            "skill": "web-save",
            "script": "read_website.py",
            "build_args": pm.build_website_read_args,
        },
        "List Websites": {
            "description": "List websites with optional filters.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "domain": {"type": "string"},
                    "pinned": {"type": "boolean"},
                    "archived": {"type": "boolean"},
                    "created_after": {"type": "string"},
                    "created_before": {"type": "string"},
                    "updated_after": {"type": "string"},
                    "updated_before": {"type": "string"},
                    "opened_after": {"type": "string"},
                    "opened_before": {"type": "string"},
                    "published_after": {"type": "string"},
                    "published_before": {"type": "string"},
                    "title": {"type": "string"},
                },
            },
            "skill": "web-save",
            "script": "list_websites.py",
            "build_args": pm.build_website_list_args,
        },
        "Set UI Theme": {
            "description": "Set the UI theme to light or dark.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "theme": {"type": "string", "enum": ["light", "dark"]},
                },
                "required": ["theme"],
            },
            "skill": "ui-theme",
            "script": None,
            "build_args": None,
        },
        "Generate Prompts": {
            "description": "Generate the current system prompt output for preview.",
            "input_schema": {
                "type": "object",
                "properties": {},
            },
            "skill": "prompt-preview",
            "script": None,
            "build_args": None,
        },
        "Memory Tool": {
            "description": "Create, update, and manage persistent memory files. Paths should start with /memories.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "command": {
                        "type": "string",
                        "enum": ["view", "create", "str_replace", "insert", "delete", "rename"],
                    },
                    "path": {"type": "string"},
                    "view_range": {
                        "type": "array",
                        "items": {"type": "integer"},
                        "minItems": 2,
                        "maxItems": 2,
                    },
                    "file_text": {"type": "string"},
                    "content": {"type": "string"},
                    "old_str": {"type": "string"},
                    "new_str": {"type": "string"},
                    "insert_line": {"type": "integer"},
                    "insert_text": {"type": "string"},
                    "old_path": {"type": "string"},
                    "new_path": {"type": "string"},
                },
                "required": ["command"],
            },
            "skill": "memory",
            "script": None,
            "build_args": None,
        },
    }
