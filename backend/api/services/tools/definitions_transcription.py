"""Transcription and media tool definitions."""
from __future__ import annotations

from api.services.tools import parameter_mapper as pm


def get_transcription_definitions() -> dict:
    """Return transcription tool definitions."""
    return {
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
    }
