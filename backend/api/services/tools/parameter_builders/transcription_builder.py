"""Parameter builders for transcription tools."""

from __future__ import annotations

from api.services.tools.parameter_builders.base import BaseParameterBuilder


class TranscriptionParameterBuilder(BaseParameterBuilder):
    """Builders for transcription tool arguments."""

    @staticmethod
    def build_audio_transcribe_args(params: dict) -> list:
        """Build CLI arguments for audio transcription."""
        file_path = params["file_path"]
        args = [file_path, "--json"]
        TranscriptionParameterBuilder.append_user_id(args, params)
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

    @staticmethod
    def build_youtube_download_args(params: dict) -> list:
        """Build CLI arguments for YouTube download."""
        args = [params["url"], "--json"]
        TranscriptionParameterBuilder.append_user_id(args, params)
        if params.get("audio_only"):
            args.append("--audio")
        if params.get("playlist"):
            args.append("--playlist")
        if params.get("output_dir"):
            args.extend(["--output", params["output_dir"]])
        return args

    @staticmethod
    def build_youtube_transcribe_args(params: dict) -> list:
        """Build CLI arguments for YouTube transcription."""
        args = [params["url"], "--json"]
        TranscriptionParameterBuilder.append_user_id(args, params)
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
