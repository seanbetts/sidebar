"""Maps MCP tools to Claude tool definitions and handles execution."""
import json
import time
import re
from typing import Dict, Any, List
from api.config import settings
from api.executors.skill_executor import SkillExecutor
from api.security.path_validator import PathValidator
from api.security.audit_logger import AuditLogger

SKILL_DISPLAY = {
    "fs": {
        "name": "Files",
        "description": "Browse, read, search, and write files in your workspace."
    },
    "notes": {
        "name": "Notes",
        "description": "Create, update, and organize notes and scratchpad content."
    },
    "docx": {
        "name": "Word Documents",
        "description": "Create and edit .docx documents with formatting preserved."
    },
    "pdf": {
        "name": "PDFs",
        "description": "Extract, merge, split, and generate PDF documents."
    },
    "pptx": {
        "name": "Presentations",
        "description": "Create and edit PowerPoint decks with slides and layouts."
    },
    "xlsx": {
        "name": "Spreadsheets",
        "description": "Create, edit, and analyze spreadsheets with formulas."
    },
    "web-save": {
        "name": "Web Save",
        "description": "Save web pages as clean markdown for later use."
    },
    "web-search": {
        "name": "Web Search",
        "description": "Search the live web for up-to-date information."
    },
    "subdomain-discover": {
        "name": "Subdomain Discovery",
        "description": "Find subdomains using DNS and certificate sources."
    },
    "web-crawler-policy": {
        "name": "Crawler Policy",
        "description": "Analyze robots.txt and llms.txt access policies."
    },
    "audio-transcribe": {
        "name": "Audio Transcription",
        "description": "Transcribe audio files into text."
    },
    "youtube-download": {
        "name": "YouTube Download",
        "description": "Download YouTube video or audio."
    },
    "youtube-transcribe": {
        "name": "YouTube Transcription",
        "description": "Transcribe YouTube videos into text."
    },
    "mcp-builder": {
        "name": "MCP Builder",
        "description": "Guide and templates for building MCP servers."
    },
    "skill-creator": {
        "name": "Skill Creator",
        "description": "Guide for creating and updating skills."
    },
    "ui-theme": {
        "name": "UI Theme",
        "description": "Allow the assistant to switch light or dark mode."
    },
    "prompt-preview": {
        "name": "Prompt Preview",
        "description": "Generate the current system prompt output for preview."
    },
    "memory": {
        "name": "Memory",
        "description": "Store and manage persistent user memories."
    },
}

EXPOSED_SKILLS = {
    "fs",
    "notes",
    "web-save",
    "web-search",
    "memory",
    "ui-theme",
    "prompt-preview",
    "audio-transcribe",
    "youtube-download",
    "youtube-transcribe",
    "subdomain-discover",
    "web-crawler-policy",
    "docx",
    "pdf",
    "pptx",
    "xlsx",
    "skill-creator",
    "mcp-builder",
}


class ToolMapper:
    """Maps MCP tools to Claude tool definitions."""

    def __init__(self):
        self.executor = SkillExecutor(settings.skills_dir, settings.workspace_base)
        self.path_validator = PathValidator(settings.workspace_base, settings.writable_paths)

        # Single source of truth for all tools
        self.tools = {
            "Browse Files": {
                "description": "List files and directories in workspace with glob pattern support",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "path": {"type": "string", "description": "Directory path (default: '.')"},
                        "pattern": {"type": "string", "description": "Glob pattern (default: '*')"},
                        "recursive": {"type": "boolean", "description": "Search recursively"}
                    },
                    "required": []
                },
                "skill": "fs",
                "script": "list.py",
                "build_args": lambda p: self._build_fs_list_args(p),
                "validate_read": True
            },
            "Read File": {
                "description": "Read file content from workspace",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "path": {"type": "string", "description": "File path to read"},
                        "start_line": {"type": "integer", "description": "Start line number (optional)"},
                        "end_line": {"type": "integer", "description": "End line number (optional)"}
                    },
                    "required": ["path"]
                },
                "skill": "fs",
                "script": "read.py",
                "build_args": lambda p: self._build_fs_read_args(p),
                "validate_read": True
            },
            "Write File": {
                "description": "Write content to file in workspace (writable paths: notes/, documents/)",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "path": {"type": "string", "description": "File path to write"},
                        "content": {"type": "string", "description": "Content to write"},
                        "dry_run": {"type": "boolean", "description": "Preview without executing"}
                    },
                    "required": ["path", "content"]
                },
                "skill": "fs",
                "script": "write.py",
                "build_args": lambda p: self._build_fs_write_args(p),
                "validate_write": True
            },
            "Search Files": {
                "description": "Search for files by name pattern or content in workspace",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "directory": {"type": "string", "description": "Directory to search (default: '.')"},
                        "name_pattern": {"type": "string", "description": "Filename pattern (* and ? wildcards)"},
                        "content_pattern": {"type": "string", "description": "Content pattern (regex)"},
                        "case_sensitive": {"type": "boolean", "description": "Case-sensitive search"}
                    }
                },
                "skill": "fs",
                "script": "search.py",
                "build_args": lambda p: self._build_fs_search_args(p),
                "validate_read": True
            },
            "Unpack DOCX": {
                "description": "Unpack a .docx file into an OOXML directory.",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "input_file": {"type": "string", "description": "Path to .docx file"},
                        "output_dir": {"type": "string", "description": "Output directory"}
                    },
                    "required": ["input_file", "output_dir"]
                },
                "skill": "docx",
                "script": "ooxml/scripts/unpack.py",
                "build_args": lambda p: [p["input_file"], p["output_dir"]],
                "expect_json": False
            },
            "Pack DOCX": {
                "description": "Pack an OOXML directory into a .docx file.",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "input_dir": {"type": "string", "description": "Unpacked OOXML directory"},
                        "output_file": {"type": "string", "description": "Output .docx path"}
                    },
                    "required": ["input_dir", "output_file"]
                },
                "skill": "docx",
                "script": "ooxml/scripts/pack.py",
                "build_args": lambda p: [p["input_dir"], p["output_file"]],
                "expect_json": False
            },
            "Validate DOCX": {
                "description": "Validate an unpacked .docx directory against the original file.",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "unpacked_dir": {"type": "string", "description": "Unpacked OOXML directory"},
                        "original_file": {"type": "string", "description": "Original .docx file"},
                        "verbose": {"type": "boolean", "description": "Verbose output"}
                    },
                    "required": ["unpacked_dir", "original_file"]
                },
                "skill": "docx",
                "script": "ooxml/scripts/validate.py",
                "build_args": lambda p: self._build_docx_validate_args(p),
                "expect_json": False
            },
            "Check PDF Fillable Fields": {
                "description": "Check if a PDF contains fillable form fields.",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "input_pdf": {"type": "string", "description": "Input PDF path"}
                    },
                    "required": ["input_pdf"]
                },
                "skill": "pdf",
                "script": "check_fillable_fields.py",
                "build_args": lambda p: [p["input_pdf"]],
                "expect_json": False
            },
            "Extract PDF Form Fields": {
                "description": "Extract PDF form field metadata to JSON.",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "input_pdf": {"type": "string", "description": "Input PDF path"},
                        "output_json": {"type": "string", "description": "Output JSON path"}
                    },
                    "required": ["input_pdf", "output_json"]
                },
                "skill": "pdf",
                "script": "extract_form_field_info.py",
                "build_args": lambda p: [p["input_pdf"], p["output_json"]],
                "expect_json": False
            },
            "Fill PDF Form Fields": {
                "description": "Fill a PDF's form fields using a fields JSON file.",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "input_pdf": {"type": "string", "description": "Input PDF path"},
                        "fields_json": {"type": "string", "description": "Fields JSON path"},
                        "output_pdf": {"type": "string", "description": "Output PDF path"}
                    },
                    "required": ["input_pdf", "fields_json", "output_pdf"]
                },
                "skill": "pdf",
                "script": "fill_fillable_fields.py",
                "build_args": lambda p: [p["input_pdf"], p["fields_json"], p["output_pdf"]],
                "expect_json": False
            },
            "Fill PDF Form Annotations": {
                "description": "Fill a PDF using annotation-based fields JSON.",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "input_pdf": {"type": "string", "description": "Input PDF path"},
                        "fields_json": {"type": "string", "description": "Fields JSON path"},
                        "output_pdf": {"type": "string", "description": "Output PDF path"}
                    },
                    "required": ["input_pdf", "fields_json", "output_pdf"]
                },
                "skill": "pdf",
                "script": "fill_pdf_form_with_annotations.py",
                "build_args": lambda p: [p["input_pdf"], p["fields_json"], p["output_pdf"]],
                "expect_json": False
            },
            "Convert PDF To Images": {
                "description": "Convert each PDF page to PNG images.",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "input_pdf": {"type": "string", "description": "Input PDF path"},
                        "output_dir": {"type": "string", "description": "Output directory"}
                    },
                    "required": ["input_pdf", "output_dir"]
                },
                "skill": "pdf",
                "script": "convert_pdf_to_images.py",
                "build_args": lambda p: [p["input_pdf"], p["output_dir"]],
                "expect_json": False
            },
            "Create PDF Validation Image": {
                "description": "Create a validation image with bounding boxes for PDF field placement.",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "page_number": {"type": "integer", "description": "Page number (1-based)"},
                        "fields_json": {"type": "string", "description": "Fields JSON path"},
                        "input_image": {"type": "string", "description": "Input image path"},
                        "output_image": {"type": "string", "description": "Output image path"}
                    },
                    "required": ["page_number", "fields_json", "input_image", "output_image"]
                },
                "skill": "pdf",
                "script": "create_validation_image.py",
                "build_args": lambda p: [
                    str(p["page_number"]),
                    p["fields_json"],
                    p["input_image"],
                    p["output_image"],
                ],
                "expect_json": False
            },
            "Check PDF Bounding Boxes": {
                "description": "Validate that PDF bounding boxes do not overlap.",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "fields_json": {"type": "string", "description": "Fields JSON path"}
                    },
                    "required": ["fields_json"]
                },
                "skill": "pdf",
                "script": "check_bounding_boxes.py",
                "build_args": lambda p: [p["fields_json"]],
                "expect_json": False
            },
            "Extract PPTX Text Inventory": {
                "description": "Extract structured text inventory from a PPTX to JSON.",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "input_pptx": {"type": "string", "description": "Input PPTX path"},
                        "output_json": {"type": "string", "description": "Output JSON path"},
                        "issues_only": {"type": "boolean", "description": "Only include overflow/overlap issues"}
                    },
                    "required": ["input_pptx", "output_json"]
                },
                "skill": "pptx",
                "script": "inventory.py",
                "build_args": lambda p: self._build_pptx_inventory_args(p),
                "expect_json": False
            },
            "Rearrange PPTX Slides": {
                "description": "Rearrange slides in a PPTX by sequence.",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "template_pptx": {"type": "string", "description": "Template PPTX path"},
                        "output_pptx": {"type": "string", "description": "Output PPTX path"},
                        "sequence": {"type": "string", "description": "Comma-separated slide indices (0-based)"}
                    },
                    "required": ["template_pptx", "output_pptx", "sequence"]
                },
                "skill": "pptx",
                "script": "rearrange.py",
                "build_args": lambda p: [p["template_pptx"], p["output_pptx"], p["sequence"]],
                "expect_json": False
            },
            "Replace PPTX Text": {
                "description": "Apply text replacements in a PPTX using an inventory JSON.",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "input_pptx": {"type": "string", "description": "Input PPTX path"},
                        "replacements_json": {"type": "string", "description": "Replacements JSON path"},
                        "output_pptx": {"type": "string", "description": "Output PPTX path"}
                    },
                    "required": ["input_pptx", "replacements_json", "output_pptx"]
                },
                "skill": "pptx",
                "script": "replace.py",
                "build_args": lambda p: [p["input_pptx"], p["replacements_json"], p["output_pptx"]],
                "expect_json": False
            },
            "Generate PPTX Thumbnails": {
                "description": "Generate thumbnail grid images from a PPTX.",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "input_pptx": {"type": "string", "description": "Input PPTX path"},
                        "output_prefix": {"type": "string", "description": "Output prefix for images"},
                        "cols": {"type": "integer", "description": "Number of columns"},
                        "outline_placeholders": {"type": "boolean", "description": "Outline placeholders"}
                    },
                    "required": ["input_pptx"]
                },
                "skill": "pptx",
                "script": "thumbnail.py",
                "build_args": lambda p: self._build_pptx_thumbnail_args(p),
                "expect_json": False
            },
            "Unpack PPTX": {
                "description": "Unpack a .pptx file into an OOXML directory.",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "input_file": {"type": "string", "description": "Path to .pptx file"},
                        "output_dir": {"type": "string", "description": "Output directory"}
                    },
                    "required": ["input_file", "output_dir"]
                },
                "skill": "pptx",
                "script": "ooxml/scripts/unpack.py",
                "build_args": lambda p: [p["input_file"], p["output_dir"]],
                "expect_json": False
            },
            "Pack PPTX": {
                "description": "Pack an OOXML directory into a .pptx file.",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "input_dir": {"type": "string", "description": "Unpacked OOXML directory"},
                        "output_file": {"type": "string", "description": "Output .pptx path"}
                    },
                    "required": ["input_dir", "output_file"]
                },
                "skill": "pptx",
                "script": "ooxml/scripts/pack.py",
                "build_args": lambda p: [p["input_dir"], p["output_file"]],
                "expect_json": False
            },
            "Validate PPTX": {
                "description": "Validate an unpacked .pptx directory against the original file.",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "unpacked_dir": {"type": "string", "description": "Unpacked OOXML directory"},
                        "original_file": {"type": "string", "description": "Original .pptx file"},
                        "verbose": {"type": "boolean", "description": "Verbose output"}
                    },
                    "required": ["unpacked_dir", "original_file"]
                },
                "skill": "pptx",
                "script": "ooxml/scripts/validate.py",
                "build_args": lambda p: self._build_docx_validate_args(p),
                "expect_json": False
            },
            "Recalculate Spreadsheet": {
                "description": "Recalculate formulas in a spreadsheet.",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "file_path": {"type": "string", "description": "Spreadsheet file path"},
                        "timeout_seconds": {"type": "integer", "description": "Timeout in seconds"}
                    },
                    "required": ["file_path"]
                },
                "skill": "xlsx",
                "script": "recalc.py",
                "build_args": lambda p: self._build_xlsx_recalc_args(p),
                "expect_json": False
            },
            "Create Skill": {
                "description": "Create a new skill scaffold at the specified path.",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "skill_name": {"type": "string", "description": "Skill name"},
                        "output_dir": {"type": "string", "description": "Parent directory for the skill"}
                    },
                    "required": ["skill_name", "output_dir"]
                },
                "skill": "skill-creator",
                "script": "init_skill.py",
                "build_args": lambda p: [p["skill_name"], "--path", p["output_dir"]],
                "expect_json": False
            },
            "Package Skill": {
                "description": "Package a skill directory into a .skill file.",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "skill_dir": {"type": "string", "description": "Skill directory path"},
                        "output_dir": {"type": "string", "description": "Output directory (optional)"}
                    },
                    "required": ["skill_dir"]
                },
                "skill": "skill-creator",
                "script": "package_skill.py",
                "build_args": lambda p: self._build_skill_package_args(p),
                "expect_json": False
            },
            "Validate Skill": {
                "description": "Validate a skill directory for correctness.",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "skill_dir": {"type": "string", "description": "Skill directory path"}
                    },
                    "required": ["skill_dir"]
                },
                "skill": "skill-creator",
                "script": "quick_validate.py",
                "build_args": lambda p: [p["skill_dir"]],
                "expect_json": False
            },
            "Evaluate MCP Server": {
                "description": "Evaluate an MCP server using an XML evaluation file.",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "eval_file": {"type": "string", "description": "Path to evaluation XML file"},
                        "transport": {"type": "string", "description": "Transport type (stdio, sse, http)"},
                        "command": {"type": "string", "description": "Command for stdio transport"},
                        "args": {"type": "array", "items": {"type": "string"}, "description": "Args for stdio command"},
                        "env": {"type": "array", "items": {"type": "string"}, "description": "Env vars KEY=VALUE"},
                        "url": {"type": "string", "description": "MCP server URL (sse/http)"},
                        "headers": {"type": "array", "items": {"type": "string"}, "description": "Headers 'Key: Value'"},
                        "model": {"type": "string", "description": "Claude model for evaluation"},
                        "output": {"type": "string", "description": "Output report file path"}
                    },
                    "required": ["eval_file"]
                },
                "skill": "mcp-builder",
                "script": "evaluation.py",
                "build_args": lambda p: self._build_mcp_evaluation_args(p),
                "expect_json": False
            },
            "Discover Subdomains": {
                "description": "Discover subdomains for a given domain.",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "domain": {"type": "string", "description": "Domain to discover subdomains for"},
                        "wordlist": {"type": "string", "description": "Custom wordlist path (optional)"},
                        "timeout": {"type": "number", "description": "HTTP timeout seconds (optional)"},
                        "dns_timeout": {"type": "number", "description": "DNS timeout seconds (optional)"},
                        "no_filter": {"type": "boolean", "description": "Skip filtering internal/redirect domains"},
                        "verbose": {"type": "boolean", "description": "Enable verbose output"}
                    },
                    "required": ["domain"]
                },
                "skill": "subdomain-discover",
                "script": "discover_subdomains.py",
                "build_args": lambda p: self._build_subdomain_discover_args(p)
            },
            "Analyze Crawler Policy": {
                "description": "Analyze robots.txt and llms.txt policies for a domain.",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "domain": {"type": "string", "description": "Target domain to analyze"},
                        "no_discover": {"type": "boolean", "description": "Skip subdomain discovery"},
                        "wordlist": {"type": "string", "description": "Custom wordlist path (optional)"},
                        "timeout": {"type": "number", "description": "HTTP timeout seconds (optional)"},
                        "dns_timeout": {"type": "number", "description": "DNS timeout seconds (optional)"},
                        "no_llms": {"type": "boolean", "description": "Skip checking llms.txt files"}
                    },
                    "required": ["domain"]
                },
                "skill": "web-crawler-policy",
                "script": "analyze_policies.py",
                "build_args": lambda p: self._build_crawler_policy_args(p)
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
                        "folder": {"type": "string", "description": "Notes folder for transcript (optional)"}
                    },
                    "required": ["file_path"]
                },
                "skill": "audio-transcribe",
                "script": "transcribe_audio.py",
                "build_args": lambda p: self._build_audio_transcribe_args(p)
            },
            "Download YouTube": {
                "description": "Download YouTube video or audio to the workspace.",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "url": {"type": "string", "description": "YouTube URL"},
                        "audio_only": {"type": "boolean", "description": "Download audio only"},
                        "playlist": {"type": "boolean", "description": "Download entire playlist"},
                        "output_dir": {"type": "string", "description": "Output directory (optional)"}
                    },
                    "required": ["url"]
                },
                "skill": "youtube-download",
                "script": "download_video.py",
                "build_args": lambda p: self._build_youtube_download_args(p)
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
                        "folder": {"type": "string", "description": "Notes folder for transcript (optional)"}
                    },
                    "required": ["url"]
                },
                "skill": "youtube-transcribe",
                "script": "transcribe_youtube.py",
                "build_args": lambda p: self._build_youtube_transcribe_args(p)
            },
            "Create Note": {
                "description": "Create a markdown note in the database (visible in UI).",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "title": {"type": "string", "description": "Optional note title"},
                        "content": {"type": "string", "description": "Markdown content"},
                        "folder": {"type": "string", "description": "Optional folder path"},
                        "tags": {"type": "array", "items": {"type": "string"}}
                    },
                    "required": ["content"]
                },
                "skill": "notes",
                "script": "save_markdown.py",
                "build_args": lambda p: self._build_notes_create_args(p)
            },
            "Update Note": {
                "description": "Update an existing note in the database by ID.",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "note_id": {"type": "string", "description": "Note UUID"},
                        "title": {"type": "string", "description": "Optional note title"},
                        "content": {"type": "string", "description": "Markdown content"}
                    },
                    "required": ["note_id", "content"]
                },
                "skill": "notes",
                "script": "save_markdown.py",
                "build_args": lambda p: self._build_notes_update_args(p)
            },
            "Delete Note": {
                "description": "Delete a note in the database by ID.",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "note_id": {"type": "string", "description": "Note UUID"}
                    },
                    "required": ["note_id"]
                },
                "skill": "notes",
                "script": "delete_note.py",
                "build_args": lambda p: [p["note_id"], "--database"]
            },
            "Pin Note": {
                "description": "Pin or unpin a note in the database.",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "note_id": {"type": "string", "description": "Note UUID"},
                        "pinned": {"type": "boolean", "description": "Pin state"}
                    },
                    "required": ["note_id", "pinned"]
                },
                "skill": "notes",
                "script": "pin_note.py",
                "build_args": lambda p: [p["note_id"], "--pinned", str(p["pinned"]).lower(), "--database"]
            },
            "Move Note": {
                "description": "Move a note to a folder by ID.",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "note_id": {"type": "string", "description": "Note UUID"},
                        "folder": {"type": "string", "description": "Destination folder path"}
                    },
                    "required": ["note_id", "folder"]
                },
                "skill": "notes",
                "script": "move_note.py",
                "build_args": lambda p: [p["note_id"], "--folder", p["folder"], "--database"]
            },
            "Get Note": {
                "description": "Fetch a note by ID.",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "note_id": {"type": "string", "description": "Note UUID"}
                    },
                    "required": ["note_id"]
                },
                "skill": "notes",
                "script": "read_note.py",
                "build_args": lambda p: [p["note_id"], "--database"]
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
                        "title": {"type": "string"}
                    }
                },
                "skill": "notes",
                "script": "list_notes.py",
                "build_args": lambda p: self._build_notes_list_args(p)
            },
            "Get Scratchpad": {
                "description": "Fetch the scratchpad note.",
                "input_schema": {
                    "type": "object",
                    "properties": {}
                },
                "skill": "notes",
                "script": "scratchpad_get.py",
                "build_args": lambda p: ["--database"]
            },
            "Update Scratchpad": {
                "description": "Update the scratchpad content.",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "content": {"type": "string"}
                    },
                    "required": ["content"]
                },
                "skill": "notes",
                "script": "scratchpad_update.py",
                "build_args": lambda p: ["--content", p["content"], "--database"]
            },
            "Clear Scratchpad": {
                "description": "Clear the scratchpad content.",
                "input_schema": {
                    "type": "object",
                    "properties": {}
                },
                "skill": "notes",
                "script": "scratchpad_clear.py",
                "build_args": lambda p: ["--database"]
            },
            "Save Website": {
                "description": "Save a website to the database (visible in UI).",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "url": {"type": "string", "description": "Website URL"}
                    },
                    "required": ["url"]
                },
                "skill": "web-save",
                "script": "save_url.py",
                "build_args": lambda p: [p["url"], "--database"]
            },
            "Delete Website": {
                "description": "Delete a website in the database by ID.",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "website_id": {"type": "string", "description": "Website UUID"}
                    },
                    "required": ["website_id"]
                },
                "skill": "web-save",
                "script": "delete_website.py",
                "build_args": lambda p: [p["website_id"], "--database"]
            },
            "Pin Website": {
                "description": "Pin or unpin a website in the database.",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "website_id": {"type": "string"},
                        "pinned": {"type": "boolean"}
                    },
                    "required": ["website_id", "pinned"]
                },
                "skill": "web-save",
                "script": "pin_website.py",
                "build_args": lambda p: [p["website_id"], "--pinned", str(p["pinned"]).lower(), "--database"]
            },
            "Archive Website": {
                "description": "Archive or unarchive a website in the database.",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "website_id": {"type": "string"},
                        "archived": {"type": "boolean"}
                    },
                    "required": ["website_id", "archived"]
                },
                "skill": "web-save",
                "script": "archive_website.py",
                "build_args": lambda p: [p["website_id"], "--archived", str(p["archived"]).lower(), "--database"]
            },
            "Read Website": {
                "description": "Fetch a website by ID.",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "website_id": {"type": "string"}
                    },
                    "required": ["website_id"]
                },
                "skill": "web-save",
                "script": "read_website.py",
                "build_args": lambda p: [p["website_id"], "--database"]
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
                        "title": {"type": "string"}
                    }
                },
                "skill": "web-save",
                "script": "list_websites.py",
                "build_args": lambda p: self._build_website_list_args(p)
            },
            "Set UI Theme": {
                "description": "Set the UI theme to light or dark.",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "theme": {"type": "string", "enum": ["light", "dark"]}
                    },
                    "required": ["theme"]
                },
                "skill": "ui-theme",  # Special case - no skill execution
                "script": None,
                "build_args": None
            },
            "Generate Prompts": {
                "description": "Generate the current system prompt output for preview.",
                "input_schema": {
                    "type": "object",
                    "properties": {}
                },
                "skill": "prompt-preview",
                "script": None,
                "build_args": None
            },
            "Memory Tool": {
                "description": "Create, update, and manage persistent memory files. Paths should start with /memories.",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "command": {
                            "type": "string",
                            "enum": ["view", "create", "str_replace", "insert", "delete", "rename"]
                        },
                        "path": {"type": "string"},
                        "view_range": {
                            "type": "array",
                            "items": {"type": "integer"},
                            "minItems": 2,
                            "maxItems": 2
                        },
                        "file_text": {"type": "string"},
                        "content": {"type": "string"},
                        "old_str": {"type": "string"},
                        "new_str": {"type": "string"},
                        "insert_line": {"type": "integer"},
                        "insert_text": {"type": "string"},
                        "old_path": {"type": "string"},
                        "new_path": {"type": "string"}
                    },
                    "required": ["command"]
                },
                "skill": "memory",
                "script": None,
                "build_args": None
            }
        }
        self._build_tool_name_maps()

    def _build_tool_name_maps(self) -> None:
        self.tool_name_map = {}
        self.tool_name_reverse = {}
        for display_name in self.tools.keys():
            safe_name = self._normalize_tool_name(display_name)
            base = safe_name
            suffix = 1
            while safe_name in self.tool_name_map and self.tool_name_map[safe_name] != display_name:
                suffix += 1
                safe_name = f"{base}_{suffix}"
                if len(safe_name) > 128:
                    safe_name = safe_name[:128]
            self.tool_name_map[safe_name] = display_name
            self.tool_name_reverse[display_name] = safe_name

    @staticmethod
    def _normalize_tool_name(name: str) -> str:
        safe = re.sub(r"[^a-zA-Z0-9_-]+", "_", name).strip("_")
        if not safe:
            safe = "tool"
        return safe[:128]

    def get_tool_display_name(self, tool_name: str) -> str:
        return self.tool_name_map.get(tool_name, tool_name)

    @staticmethod
    def _normalize_result(result: Any) -> Dict[str, Any]:
        if isinstance(result, dict):
            success = bool(result.get("success", False))
            data = result.get("data")
            error = result.get("error")

            if success and data is None:
                data = {
                    key: value
                    for key, value in result.items()
                    if key not in {"success", "error"}
                }

            if not success and not error:
                error = "Unknown error"

            return {
                "success": success,
                "data": data,
                "error": error
            }

        return {
            "success": True,
            "data": result,
            "error": None
        }

    def get_claude_tools(self, allowed_skills: List[str] | None = None) -> List[Dict[str, Any]]:
        """Convert tool configs to Claude tool schema."""
        return [
            {
                "name": self.tool_name_reverse.get(name, name),
                "description": config["description"],
                "input_schema": config["input_schema"]
            }
            for name, config in self.tools.items()
            if self._is_skill_enabled(config.get("skill"), allowed_skills)
        ]

    async def execute_tool(
        self,
        name: str,
        parameters: dict,
        allowed_skills: List[str] | None = None,
        context: Dict[str, Any] | None = None
    ) -> Dict[str, Any]:
        """Execute tool via skill executor."""
        start_time = time.time()

        try:
            # Get tool config
            display_name = self.get_tool_display_name(name)
            tool_config = self.tools.get(display_name)
            if not tool_config:
                return self._normalize_result({
                    "success": False,
                    "error": f"Unknown tool: {display_name}"
                })

            if not self._is_skill_enabled(tool_config.get("skill"), allowed_skills):
                return self._normalize_result({
                    "success": False,
                    "error": f"Skill disabled: {tool_config.get('skill')}"
                })

            # Special case: UI theme (no skill execution)
            if display_name == "Set UI Theme":
                theme = parameters.get("theme")
                if theme not in {"light", "dark"}:
                    return self._normalize_result({"success": False, "error": "Invalid theme"})

                result = {"success": True, "data": {"theme": theme}}

                AuditLogger.log_tool_call(
                    tool_name=name,
                    parameters={"theme": theme},
                    duration_ms=(time.time() - start_time) * 1000,
                    success=True
                )

                return self._normalize_result(result)

            # Special case: prompt preview
            if display_name == "Generate Prompts":
                if not context:
                    return self._normalize_result({
                        "success": False,
                        "error": "Missing prompt context"
                    })
                db = context.get("db")
                user_id = context.get("user_id")
                if not db or not user_id:
                    return self._normalize_result({
                        "success": False,
                        "error": "Missing database or user context"
                    })

                from api.services.prompt_context_service import PromptContextService

                system_prompt, first_message_prompt = PromptContextService.build_prompts(
                    db=db,
                    user_id=user_id,
                    open_context=context.get("open_context"),
                    user_agent=context.get("user_agent"),
                    current_location=context.get("current_location"),
                    current_location_levels=context.get("current_location_levels"),
                    current_weather=context.get("current_weather"),
                )
                result = {
                    "success": True,
                    "data": {
                        "system_prompt": system_prompt,
                        "first_message_prompt": first_message_prompt,
                    },
                }

                AuditLogger.log_tool_call(
                    tool_name=display_name,
                    parameters={},
                    duration_ms=(time.time() - start_time) * 1000,
                    success=True
                )

                return self._normalize_result(result)

            # Special case: memory tool
            if display_name == "Memory Tool":
                if not context:
                    return self._normalize_result({
                        "success": False,
                        "error": "Missing memory context"
                    })
                db = context.get("db")
                user_id = context.get("user_id")
                if not db or not user_id:
                    return self._normalize_result({
                        "success": False,
                        "error": "Missing database or user context"
                    })

                from api.services.memory_tool_handler import MemoryToolHandler

                result = MemoryToolHandler.execute_command(db, user_id, parameters)
                return self._normalize_result(result)

            # Validate paths if needed
            if tool_config.get("validate_write"):
                if "path" in parameters:
                    self.path_validator.validate_write_path(parameters["path"])
            elif tool_config.get("validate_read"):
                path_to_validate = parameters.get("path") or parameters.get("directory", ".")
                self.path_validator.validate_read_path(path_to_validate)

            # Build arguments using the tool's build function
            args = tool_config["build_args"](parameters)

            # Execute skill
            result = await self.executor.execute(
                tool_config["skill"],
                tool_config["script"],
                args,
                expect_json=tool_config.get("expect_json", True),
            )

            # Log execution (redact sensitive content)
            log_params = parameters.copy()
            if "content" in log_params and display_name == "Update Scratchpad":
                log_params["content"] = "<redacted>"
            if "content" in log_params and display_name in ["Create Note", "Update Note", "Write File"]:
                log_params.pop("content", None)

            AuditLogger.log_tool_call(
                tool_name=display_name,
                parameters=log_params,
                duration_ms=(time.time() - start_time) * 1000,
                success=result.get("success", False)
            )

            return self._normalize_result(result)

        except Exception as e:
            AuditLogger.log_tool_call(
                tool_name=name,
                parameters=parameters,
                duration_ms=(time.time() - start_time) * 1000,
                success=False,
                error=str(e)
            )
            return self._normalize_result({"success": False, "error": str(e)})

    @staticmethod
    def _is_skill_enabled(skill_name: str | None, allowed_skills: List[str] | None) -> bool:
        if not skill_name:
            return True
        if allowed_skills is None:
            return True
        return skill_name in set(allowed_skills)

    # Argument builders for each tool type
    def _build_fs_list_args(self, params: dict) -> list:
        path = params.get("path", ".")
        pattern = params.get("pattern", "*")
        recursive = params.get("recursive", False)

        args = [path, "--pattern", pattern]
        if recursive:
            args.append("--recursive")
        return args

    def _build_fs_read_args(self, params: dict) -> list:
        args = [params["path"]]
        if "start_line" in params:
            args.extend(["--start-line", str(params["start_line"])])
        if "end_line" in params:
            args.extend(["--end-line", str(params["end_line"])])
        return args

    def _build_fs_write_args(self, params: dict) -> list:
        args = [params["path"], "--content", params["content"]]
        if params.get("dry_run"):
            args.append("--dry-run")
        return args

    def _build_fs_search_args(self, params: dict) -> list:
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
        return args

    def _build_notes_create_args(self, params: dict) -> list:
        args = [
            params.get("title", ""),
            "--content",
            params["content"],
            "--mode",
            "create",
            "--database"
        ]
        if "folder" in params:
            args.extend(["--folder", params["folder"]])
        if "tags" in params:
            args.extend(["--tags", ",".join(params["tags"])])
        return args

    def _build_notes_update_args(self, params: dict) -> list:
        return [
            params.get("title", ""),
            "--content",
            params["content"],
            "--mode",
            "update",
            "--note-id",
            params["note_id"],
            "--database"
        ]

    def _build_notes_list_args(self, params: dict) -> list:
        args = ["--database"]
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

    def _build_website_list_args(self, params: dict) -> list:
        args = ["--database"]
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

    def _build_audio_transcribe_args(self, params: dict) -> list:
        args = [
            params["file_path"],
            "--json",
            "--database",
        ]
        if params.get("language"):
            args.extend(["--language", params["language"]])
        if params.get("model"):
            args.extend(["--model", params["model"]])
        if params.get("output_dir"):
            args.extend(["--output-dir", params["output_dir"]])
        if params.get("folder"):
            args.extend(["--folder", params["folder"]])
        return args

    def _build_youtube_download_args(self, params: dict) -> list:
        args = [
            params["url"],
            "--json",
        ]
        if params.get("audio_only"):
            args.append("--audio")
        if params.get("playlist"):
            args.append("--playlist")
        if params.get("output_dir"):
            args.extend(["--output", params["output_dir"]])
        return args

    def _build_youtube_transcribe_args(self, params: dict) -> list:
        args = [
            params["url"],
            "--json",
            "--database",
        ]
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

    def _build_subdomain_discover_args(self, params: dict) -> list:
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

    def _build_crawler_policy_args(self, params: dict) -> list:
        args = [
            params["domain"],
            "--json",
        ]
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

    def _build_docx_validate_args(self, params: dict) -> list:
        args = [
            params["unpacked_dir"],
            "--original",
            params["original_file"],
        ]
        if params.get("verbose"):
            args.append("--verbose")
        return args

    def _build_pptx_inventory_args(self, params: dict) -> list:
        args = [
            params["input_pptx"],
            params["output_json"],
        ]
        if params.get("issues_only"):
            args.append("--issues-only")
        return args

    def _build_pptx_thumbnail_args(self, params: dict) -> list:
        args = [params["input_pptx"]]
        if params.get("output_prefix"):
            args.append(params["output_prefix"])
        if params.get("cols") is not None:
            args.extend(["--cols", str(params["cols"])])
        if params.get("outline_placeholders"):
            args.append("--outline-placeholders")
        return args

    def _build_xlsx_recalc_args(self, params: dict) -> list:
        args = [params["file_path"]]
        if params.get("timeout_seconds") is not None:
            args.append(str(params["timeout_seconds"]))
        return args

    def _build_skill_package_args(self, params: dict) -> list:
        args = [params["skill_dir"]]
        if params.get("output_dir"):
            args.append(params["output_dir"])
        return args

    def _build_mcp_evaluation_args(self, params: dict) -> list:
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
