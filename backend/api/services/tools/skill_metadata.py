"""Skill metadata for display in tool listings."""

SKILL_DISPLAY = {
    "fs": {
        "name": "Files",
        "description": "Browse, read, search, and write files in R2-backed storage.",
    },
    "notes": {
        "name": "Notes",
        "description": "Create, update, and organize notes and scratchpad content.",
    },
    "docx": {
        "name": "Word Documents",
        "description": "Create and edit .docx documents with formatting preserved.",
    },
    "pdf": {
        "name": "PDFs",
        "description": "Extract, merge, split, and generate PDF documents.",
    },
    "pptx": {
        "name": "Presentations",
        "description": "Create and edit PowerPoint decks with slides and layouts.",
    },
    "xlsx": {
        "name": "Spreadsheets",
        "description": "Create, edit, and analyze spreadsheets with formulas.",
    },
    "web-save": {
        "name": "Web Save",
        "description": "Save web pages as clean markdown in the database for later use.",
    },
    "web-search": {
        "name": "Web Search",
        "description": "Search the live web for up-to-date information.",
    },
    "subdomain-discover": {
        "name": "Subdomain Discovery",
        "description": "Find subdomains using DNS and certificate sources.",
    },
    "web-crawler-policy": {
        "name": "Crawler Policy",
        "description": "Analyze robots.txt and llms.txt access policies.",
    },
    "audio-transcribe": {
        "name": "Audio Transcription",
        "description": "Transcribe audio files into text and store transcripts in R2.",
    },
    "youtube-download": {
        "name": "YouTube Download",
        "description": "Download YouTube video or audio to the files workspace (videos by default).",
    },
    "youtube-transcribe": {
        "name": "YouTube Transcription",
        "description": "Transcribe YouTube videos into text and store transcripts in the files workspace.",
    },
    "mcp-builder": {
        "name": "MCP Builder",
        "description": "Guide and templates for building MCP servers.",
    },
    "skill-creator": {
        "name": "Skill Creator",
        "description": "Guide for creating and updating skills.",
    },
    "ui-theme": {
        "name": "UI Theme",
        "description": "Allow the assistant to switch light or dark mode.",
    },
    "prompt-preview": {
        "name": "Prompt Preview",
        "description": "Generate the current system prompt output for preview.",
    },
    "memory": {
        "name": "Memory",
        "description": "Store and manage persistent user memories.",
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
