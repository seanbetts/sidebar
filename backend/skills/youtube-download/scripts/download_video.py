#!/usr/bin/env python3
"""Download YouTube Video.

Download YouTube videos or audio using yt-dlp with automatic format conversion.
"""

import argparse
import contextlib
import importlib.util
import io
import json
import logging
import os
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.parse
from pathlib import Path
from typing import Any

import yt_dlp

BACKEND_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(BACKEND_ROOT))

try:
    from api.services.script_sentry import (
        capture_script_exception,
        initialize_script_sentry,
    )
    from api.services.skill_file_ops import upload_file
    from api.services.skill_file_ops_ingestion import (
        create_ingested_file,
        finalize_ingested_file,
        write_ai_markdown,
        write_derivative,
    )
except Exception:
    upload_file = None
    create_ingested_file = None
    finalize_ingested_file = None
    write_ai_markdown = None
    write_derivative = None

    def _noop_initialize_script_sentry(script_name: str) -> bool:
        return False

    def _noop_capture_script_exception(
        exc: BaseException, *, extras: dict[str, Any] | None = None
    ) -> None:
        return None

    initialize_script_sentry = _noop_initialize_script_sentry
    capture_script_exception = _noop_capture_script_exception


# Default output directory (files workspace)
DEFAULT_R2_DIR = "files/videos"
logger = logging.getLogger(__name__)
SCRIPT_ROOT = Path(__file__).resolve().parents[2]
AUDIO_TRANSCRIBE_SCRIPT = (
    SCRIPT_ROOT / "audio-transcribe" / "scripts" / "transcribe_audio.py"
)


def _resolve_js_runtimes() -> dict[str, dict[str, str]] | None:
    value = (
        os.getenv("YT_DLP_JS_RUNTIMES") or os.getenv("YT_DLP_JS_RUNTIME") or ""
    ).strip()
    if value:
        runtimes: dict[str, dict[str, str]] = {}
        for entry in [item.strip() for item in value.split(",") if item.strip()]:
            if ":" in entry:
                runtime, path = entry.split(":", 1)
                runtime = runtime.strip().lower()
                path = path.strip()
                if runtime:
                    runtimes[runtime] = {"path": path} if path else {}
            else:
                runtimes[entry.lower()] = {}
        return runtimes or None
    for runtime in ("node", "deno", "bun"):
        if shutil.which(runtime):
            return {runtime: {}}
    return None


def _detect_impersonation_support() -> str:
    return "curl_cffi" if importlib.util.find_spec("curl_cffi") else "none"


def _resolve_youtube_webpage_client() -> str | None:
    value = (os.getenv("YT_DLP_YOUTUBE_WEBPAGE_CLIENT") or "").strip().lower()
    allowed_clients = {"web", "web_safari", "mweb"}
    if value in allowed_clients:
        return value
    return None


def _resolve_player_clients(audio_only: bool) -> list[str] | None:
    value = (os.getenv("YT_DLP_PLAYER_CLIENTS") or "").strip()
    if value:
        clients = [client.strip() for client in value.split(",") if client.strip()]
        return clients or None
    if audio_only:
        return ["default"]
    return None


def _configure_logging(quiet: bool) -> None:
    if quiet:
        logging.basicConfig(level=logging.WARNING)
    else:
        logging.basicConfig(level=logging.INFO)


def _default_remote_components() -> list[str]:
    return ["ejs:github"]


def _ensure_stdio() -> None:
    for fd in (0, 1, 2):
        try:
            os.fstat(fd)
        except OSError:
            mode = os.O_RDONLY if fd == 0 else os.O_WRONLY
            devnull_fd = os.open(os.devnull, mode)
            os.dup2(devnull_fd, fd)
            os.close(devnull_fd)


def _build_storage_payload(
    user_id: str | None,
    record: Any,
    *,
    audio_only: bool,
    filename: str,
) -> dict[str, Any]:
    if not user_id or not record:
        return {
            "file_id": None,
            "ai_path": None,
            "derivatives": [],
        }
    file_id = str(record.id)
    extension = Path(filename).suffix
    if extension:
        extension = extension.lower()
    kind = "audio_original" if audio_only else "video_original"
    base_name = "audio" if audio_only else "video"
    return {
        "file_id": file_id,
        "ai_path": f"{user_id}/files/{file_id}/ai/ai.md",
        "derivatives": [
            {
                "kind": kind,
                "path": f"{user_id}/files/{file_id}/derivatives/{base_name}{extension}",
                "content_type": "audio/mpeg" if audio_only else "video/mp4",
            }
        ],
    }


def _build_ai_markdown_content(
    *,
    title: str,
    transcript: str | None,
    audio_only: bool,
) -> str:
    heading = (title or "YouTube Media").strip()
    transcript_body = (transcript or "").strip()
    if transcript_body:
        return f"## {heading}\n\n{transcript_body}"
    fallback = (
        "Transcript unavailable for this audio download."
        if audio_only
        else "Transcript unavailable for this video."
    )
    return f"## {heading}\n\n{fallback}"


def _load_audio_transcriber():
    if not AUDIO_TRANSCRIBE_SCRIPT.exists():
        raise RuntimeError(
            f"Audio transcription script not found at {AUDIO_TRANSCRIBE_SCRIPT}"
        )
    spec = importlib.util.spec_from_file_location(
        "audio_transcribe_skill", AUDIO_TRANSCRIBE_SCRIPT
    )
    if not spec or not spec.loader:
        raise RuntimeError("Failed to load audio transcription module")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    transcriber = getattr(module, "transcribe_audio", None)
    if not callable(transcriber):
        raise RuntimeError("transcribe_audio function not found")
    return transcriber


def _transcribe_downloaded_media(
    *,
    local_output: Path,
    user_id: str,
) -> tuple[str, dict[str, Any]]:
    transcribe_audio = _load_audio_transcriber()
    temp_root = Path(tempfile.mkdtemp(prefix="yt-download-transcript-"))
    try:
        # Suppress verbose transcriber progress output so tool JSON remains clean.
        with contextlib.redirect_stdout(io.StringIO()):
            result = transcribe_audio(
                str(local_output),
                language=None,
                output_dir=None,
                user_id=user_id,
                temp_dir=str(temp_root),
                keep_local=False,
                upload_result=False,
                response_format="json",
            )
    finally:
        shutil.rmtree(temp_root, ignore_errors=True)

    transcript = str(result.get("transcript") or "").strip()
    metadata: dict[str, Any] = {}
    model = result.get("model")
    if model:
        metadata["model"] = str(model)
    usage = result.get("usage")
    if isinstance(usage, dict):
        for key in (
            "total_tokens",
            "input_tokens",
            "output_tokens",
        ):
            value = usage.get(key)
            if value is not None:
                metadata[f"transcription_{key}"] = value
    return transcript, metadata


def _store_downloaded_output(
    *,
    user_id: str,
    local_output: Path,
    r2_path: str,
    processed_url: str,
    title: str,
    filename: str,
    audio_only: bool,
    duration_seconds: int | None,
    download_duration_seconds: int,
) -> tuple[Any, dict[str, Any]]:
    content_type = "audio/mpeg" if audio_only else "video/mp4"
    transcript = ""
    transcript_meta: dict[str, Any] = {}
    transcript_error: str | None = None
    if not audio_only:
        try:
            transcript, transcript_meta = _transcribe_downloaded_media(
                local_output=local_output,
                user_id=user_id,
            )
        except Exception as exc:
            transcript_error = str(exc)
            logger.warning("Transcription unavailable for %s: %s", local_output, exc)
    source_metadata: dict[str, Any] = {
        "provider": "youtube-download",
        "youtube_url": processed_url,
        "audio_only": audio_only,
        "download_duration_seconds": download_duration_seconds,
    }
    if duration_seconds is not None:
        source_metadata["duration_seconds"] = duration_seconds
    if transcript.strip():
        source_metadata["transcript_status"] = "ready"
    elif audio_only:
        source_metadata["transcript_status"] = "skipped"
    else:
        source_metadata["transcript_status"] = "failed"
        if transcript_error:
            source_metadata["transcript_error"] = transcript_error
    if transcript_meta.get("model"):
        source_metadata["transcription_model"] = transcript_meta["model"]

    if (
        create_ingested_file
        and write_derivative
        and write_ai_markdown
        and finalize_ingested_file
    ):
        record = create_ingested_file(
            user_id,
            filename,
            content_type,
            size=local_output.stat().st_size,
            source_url=processed_url,
            source_metadata=source_metadata,
            path=r2_path,
        )
        derivative = write_derivative(
            user_id,
            record,
            local_output,
            kind="audio_original" if audio_only else "video_original",
            content_type=content_type,
        )
        ai_content = _build_ai_markdown_content(
            title=title,
            transcript=transcript,
            audio_only=audio_only,
        )
        ingestion_meta: dict[str, Any] = {
            "skill": "youtube-download",
            "size_bytes": local_output.stat().st_size,
            "download_duration_seconds": download_duration_seconds,
        }
        if duration_seconds is not None:
            ingestion_meta["duration_seconds"] = duration_seconds
        if transcript_meta.get("model"):
            ingestion_meta["model"] = transcript_meta["model"]
        ai_derivative = write_ai_markdown(
            user_id,
            record,
            ai_content,
            frontmatter={
                "source_url": processed_url,
                "source_type": "youtube-download",
                "ingestion": ingestion_meta,
            },
            derivative_items=[
                {
                    "kind": derivative["kind"],
                    "path": derivative["storage_key"],
                    "content_type": derivative.get("content_type")
                    or derivative.get("mime"),
                }
            ],
        )
        payload = finalize_ingested_file(user_id, record, [derivative, ai_derivative])
        return record, payload

    if upload_file is None:
        raise RuntimeError("Storage dependencies are unavailable")
    record = upload_file(user_id, r2_path, local_output, content_type=content_type)
    payload = _build_storage_payload(
        user_id,
        record,
        audio_only=audio_only,
        filename=filename,
    )
    return record, payload


def check_ffmpeg() -> bool:
    """Check if ffmpeg is installed and has required capabilities.

    Returns:
        True if ffmpeg is properly installed, False otherwise
    """
    try:
        result = subprocess.run(
            ["ffmpeg", "-version"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )

        if result.returncode != 0:
            return False

        # Check for required codecs
        codecs_result = subprocess.run(
            ["ffmpeg", "-codecs"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )

        required_codecs = ["h264", "aac"]
        codecs_output = codecs_result.stdout.lower()

        missing_codecs = [
            codec for codec in required_codecs if codec not in codecs_output
        ]

        if missing_codecs:
            print(
                f"Warning: ffmpeg is missing required codecs: {', '.join(missing_codecs)}"
            )
            return False

        return True

    except FileNotFoundError:
        return False


def _parse_ffprobe_json(raw_output: str) -> dict[str, Any]:
    """Parse ffprobe JSON output, tolerating prefixed noise lines."""
    parsed = raw_output.strip()
    if not parsed:
        return {}
    try:
        return json.loads(parsed)
    except json.JSONDecodeError:
        json_start = parsed.find("{")
        if json_start >= 0:
            return json.loads(parsed[json_start:])
        raise


def verify_output(filepath: str, *, quiet: bool = False) -> bool:
    """Verify the output file has both video and audio streams.

    Args:
        filepath: Path to the output file
        quiet: If True, suppress stdout output

    Returns:
        True if file has both video and audio, False otherwise
    """
    try:
        # Check video stream
        cmd = [
            "ffprobe",
            "-v",
            "error",
            "-select_streams",
            "v:0",
            "-show_entries",
            "stream=codec_name,width,height,bit_rate",
            "-of",
            "json",
            filepath,
        ]
        video_result = subprocess.run(cmd, capture_output=True, text=True, check=False)

        # Check audio stream
        cmd = [
            "ffprobe",
            "-v",
            "error",
            "-select_streams",
            "a:0",
            "-show_entries",
            "stream=codec_name,channels,bit_rate",
            "-of",
            "json",
            filepath,
        ]
        audio_result = subprocess.run(cmd, capture_output=True, text=True, check=False)

        video_info = _parse_ffprobe_json(video_result.stdout)
        audio_info = _parse_ffprobe_json(audio_result.stdout)

        has_video = len(video_info.get("streams", [])) > 0
        has_audio = len(audio_info.get("streams", [])) > 0

        if has_video and not quiet:
            v_stream = video_info["streams"][0]
            print(
                f"  Video stream: {v_stream.get('codec_name', 'unknown')} "
                f"({v_stream.get('width', '?')}x{v_stream.get('height', '?')})"
            )
        elif not has_video and not quiet:
            print("  Warning: Output file appears to be missing video stream!")

        if has_audio and not quiet:
            a_stream = audio_info["streams"][0]
            print(
                f"  Audio stream: {a_stream.get('codec_name', 'unknown')} "
                f"({a_stream.get('channels', '?')} channels)"
            )
        elif not has_audio and not quiet:
            print("  Warning: Output file appears to be missing audio stream!")

        return has_video and has_audio

    except Exception as e:
        if quiet:
            logger.warning("Output stream verification failed: %s", e)
        else:
            print(f"  Error verifying output file: {e}")
        return False


def progress_hook(d):
    """Progress hook for yt-dlp downloads."""
    if d["status"] == "downloading":
        if "fragment_index" in d and "fragment_count" in d:
            print(
                f"\r  Downloading fragment {d['fragment_index']}/{d['fragment_count']} "
                f"({d.get('_percent_str', 'N/A')})",
                end="",
                flush=True,
            )
        elif "_percent_str" in d:
            print(f"\r  Downloading... {d['_percent_str']}", end="", flush=True)
    elif d["status"] == "finished":
        print(f"\n  Download completed: {Path(d['filename']).name}")


def normalize_url(url: str) -> str:
    """Normalize and validate YouTube URL.

    Args:
        url: YouTube URL to normalize

    Returns:
        Normalized YouTube URL

    Raises:
        ValueError: If URL is invalid or not YouTube
    """
    try:
        # Add protocol if missing
        parsed = urllib.parse.urlparse(url)
        if not parsed.scheme:
            url = "https://" + url
            parsed = urllib.parse.urlparse(url)

        # Validate it's a YouTube URL
        if not any(domain in parsed.netloc for domain in ["youtube.com", "youtu.be"]):
            raise ValueError("Not a valid YouTube URL")

        # Convert youtu.be short links to full format
        if "youtu.be" in parsed.netloc:
            video_id = parsed.path.strip("/")
            return f"https://www.youtube.com/watch?v={video_id}"

        return url

    except Exception as e:
        raise ValueError(f"Invalid URL format: {e}") from e


def download_youtube(
    url: str,
    audio_only: bool = False,
    is_playlist: bool = False,
    output_dir: str | None = None,
    quiet: bool = False,
    *,
    user_id: str | None = None,
    temp_dir: str | None = None,
    keep_local: bool = False,
    upload: bool = True,
) -> dict[str, Any]:
    """Download YouTube video or audio.

    Args:
        url: YouTube URL to download
        audio_only: If True, download audio only (MP3)
        is_playlist: If True, download entire playlist
        output_dir: Custom output directory (default: workspace Downloads)
        quiet: If True, suppress progress output (for JSON mode)

    Returns:
        Dictionary with download results

    Raises:
        ValueError: If URL is invalid or ffmpeg not found
        Exception: If download fails
    """
    _ensure_stdio()
    _configure_logging(quiet)

    # Check ffmpeg
    if not check_ffmpeg():
        raise ValueError(
            "ffmpeg is not installed or missing required codecs. "
            "Install with: brew install ffmpeg (macOS) or "
            "sudo apt-get install ffmpeg (Ubuntu/Debian)"
        )

    # Normalize URL
    processed_url = normalize_url(url)

    if upload:
        if not user_id:
            raise ValueError("user_id is required for storage")
        if (
            upload_file is None
            and (
                create_ingested_file is None
                or write_derivative is None
                or write_ai_markdown is None
                or finalize_ingested_file is None
            )
        ):
            raise RuntimeError("Storage dependencies are unavailable")

    r2_dir = (output_dir or DEFAULT_R2_DIR).strip("/")
    local_root = (
        Path(temp_dir) if temp_dir else Path(tempfile.mkdtemp(prefix="yt-download-"))
    )
    local_root.mkdir(parents=True, exist_ok=True)
    save_path = local_root

    # Configure yt-dlp options
    ydl_opts = {
        "outtmpl": str(save_path / "%(title).100s.%(ext)s").replace("|", "-"),
        "format": "bestvideo[vcodec^=avc]+bestaudio/best[vcodec^=avc]/bestvideo+bestaudio/best",
        "merge_output_format": "mp4",
        "postprocessors": [
            {
                "key": "FFmpegVideoConvertor",
                "preferedformat": "mp4",
            }
        ],
        "verbose": False,
        "prefer_ffmpeg": True,
        "postprocessor_args": [
            "-c:v",
            "libx264",
            "-c:a",
            "aac",
            "-movflags",
            "+faststart",
        ],
        "fragment_retries": 10,
        "retries": 10,
        "file_access_retries": 3,
        "socket_timeout": 30,
        "continuedl": True,
        "noprogress": True if quiet else False,
        "progress_hooks": [] if quiet else [progress_hook],
        "quiet": quiet,
    }

    youtube_extractor_args: dict[str, list[str]] = {}
    player_clients = _resolve_player_clients(audio_only)
    if player_clients:
        youtube_extractor_args["player_client"] = player_clients

    webpage_client = _resolve_youtube_webpage_client()
    if webpage_client:
        youtube_extractor_args["webpage_client"] = [webpage_client]

    if youtube_extractor_args:
        ydl_opts["extractor_args"] = {"youtube": youtube_extractor_args}

    # Audio-only configuration
    if audio_only:
        ydl_opts.update(
            {
                "format": "140-8/140/bestaudio[ext=m4a]/bestaudio",
                "postprocessors": [
                    {
                        "key": "FFmpegExtractAudio",
                        "preferredcodec": "mp3",
                        "preferredquality": "192",
                    }
                ],
                "postprocessor_args": [],
            }
        )

    # Playlist configuration
    if is_playlist:
        ydl_opts["yes_playlist"] = True
    else:
        ydl_opts["playlist_items"] = "1"

    start_time = time.time()

    js_runtimes = _resolve_js_runtimes()
    if js_runtimes:
        ydl_opts["js_runtimes"] = js_runtimes
    logger.info(
        "yt-dlp player clients: %s",
        ",".join(player_clients) if player_clients else "default",
    )
    logger.info(
        "yt-dlp extractor args: %s",
        json.dumps(ydl_opts.get("extractor_args"), sort_keys=True)
        if ydl_opts.get("extractor_args")
        else "none",
    )
    logger.info(
        "yt-dlp js runtimes: %s", ",".join(js_runtimes.keys()) if js_runtimes else "none"
    )
    logger.info("yt-dlp impersonation support: %s", _detect_impersonation_support())
    logger.info("yt-dlp audio_only=%s playlist=%s", audio_only, is_playlist)
    remote_components = _default_remote_components()
    ydl_opts["remote_components"] = remote_components
    logger.info("yt-dlp remote components: %s", ",".join(remote_components))

    try:
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            # Extract info without downloading
            if not quiet:
                print("Fetching video information...")
            info = ydl.extract_info(processed_url, download=False)

            if not info:
                raise ValueError("Could not extract video information")

            title = info.get("title", "Unknown")
            if not quiet:
                print(f"Title: {title}")

            # Get expected filename
            filename = ydl.prepare_filename(info)

            # Download
            if not quiet:
                print("Starting download...")
            ydl.download([processed_url])

            # Verify output (video only)
            if not audio_only:
                output_path = Path(save_path) / Path(filename).name
                if output_path.exists():
                    if not quiet:
                        print("\nVerifying output streams...")
                    verify_output(str(output_path), quiet=quiet)

        end_time = time.time()
        download_duration_seconds = int(end_time - start_time)

        # Get final filename (postprocessors may change extension)
        final_filename = Path(filename).name
        if audio_only:
            # FFmpegExtractAudio changes extension to .mp3
            final_filename = Path(filename).stem + ".mp3"

        video_duration_seconds: int | None = None
        raw_duration = info.get("duration")
        if isinstance(raw_duration, (int, float)) and raw_duration > 0:
            video_duration_seconds = int(raw_duration)

        local_output = save_path / final_filename
        if not local_output.exists():
            raise FileNotFoundError(f"Download output not found: {local_output}")

        record = None
        storage_payload = {"file_id": None, "ai_path": None, "derivatives": []}
        if upload:
            r2_path = f"{r2_dir}/{final_filename}" if r2_dir else final_filename
            record, storage_payload = _store_downloaded_output(
                user_id=user_id,
                local_output=local_output,
                r2_path=r2_path,
                processed_url=processed_url,
                title=title,
                filename=final_filename,
                audio_only=audio_only,
                duration_seconds=video_duration_seconds,
                download_duration_seconds=download_duration_seconds,
            )

        if not keep_local and temp_dir is None:
            local_output.unlink(missing_ok=True)

        return {
            "url": processed_url,
            "title": title,
            "output_dir": r2_dir or ".",
            "filename": final_filename,
            "r2_path": record.path if record else None,
            "local_path": str(local_output) if keep_local or not upload else None,
            "audio_only": audio_only,
            "is_playlist": is_playlist,
            "duration_seconds": video_duration_seconds,
            "video_duration_seconds": video_duration_seconds,
            "download_duration_seconds": download_duration_seconds,
            "success": True,
            **storage_payload,
        }

    except yt_dlp.utils.DownloadError as e:
        error_msg = str(e)
        lowered = error_msg.lower()
        if "Unavailable video" in error_msg:
            raise ValueError(
                "Video is unavailable (private, age-restricted, or removed)"
            ) from e
        elif "Invalid URL" in error_msg:
            raise ValueError("Invalid YouTube URL") from e
        elif (
            "sign in to confirm you're not a bot" in lowered
            or "cookies-from-browser" in lowered
            or "requested format is not available" in lowered
        ):
            raise RuntimeError(
                "YouTube blocked anonymous download for this video"
            ) from e
        elif "HTTP Error 403" in error_msg or "403" in error_msg:
            raise RuntimeError("HTTP 403 Forbidden while downloading YouTube media") from e
        else:
            raise Exception(f"Download failed: {error_msg}") from e


def format_human_readable(result: dict[str, Any]) -> str:
    """Format result in human-readable format.

    Args:
        result: Result dictionary from download_youtube

    Returns:
        Formatted string for display
    """
    lines = []

    lines.append("=" * 80)
    lines.append("DOWNLOAD COMPLETED SUCCESSFULLY")
    lines.append("=" * 80)
    lines.append("")

    lines.append(f"Title: {result['title']}")
    lines.append(f"URL: {result['url']}")
    lines.append(f"Type: {'Audio (MP3)' if result['audio_only'] else 'Video (MP4)'}")
    lines.append(f"Playlist: {'Yes' if result['is_playlist'] else 'No'}")
    lines.append(f"Saved to: {result.get('r2_path') or result['output_dir']}")
    lines.append(f"Filename: {result['filename']}")

    media_duration = result.get("duration_seconds")
    if isinstance(media_duration, (int, float)) and media_duration >= 0:
        minutes = int(media_duration) // 60
        seconds = int(media_duration) % 60
        lines.append(f"Media duration: {minutes}m {seconds}s")
    else:
        lines.append("Media duration: Unknown")
    download_seconds = int(result.get("download_duration_seconds") or 0)
    minutes = download_seconds // 60
    seconds = download_seconds % 60
    lines.append(f"Download time: {minutes}m {seconds}s")

    lines.append("=" * 80)

    return "\n".join(lines)


def main():
    """Main entry point for download_video script."""
    initialize_script_sentry("youtube-download.download_video")
    parser = argparse.ArgumentParser(
        description="Download YouTube videos or audio using yt-dlp",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=f"""
Default Output (R2): {DEFAULT_R2_DIR}

Examples:
  # Download video
  %(prog)s "https://youtube.com/watch?v=VIDEO_ID"

  # Download audio only
  %(prog)s "https://youtube.com/watch?v=VIDEO_ID" --audio

  # Download playlist
  %(prog)s "https://youtube.com/playlist?list=PLAYLIST_ID" --playlist

  # Custom output directory
  %(prog)s "https://youtube.com/watch?v=VIDEO_ID" --output Videos

Requirements:
  - ffmpeg must be installed (brew install ffmpeg on macOS)
        """,
    )

    # Required argument
    parser.add_argument("url", help="YouTube video or playlist URL")

    # Optional arguments
    parser.add_argument(
        "--audio", action="store_true", help="Download audio only (converts to MP3)"
    )
    parser.add_argument(
        "--playlist",
        action="store_true",
        help="Download entire playlist (default: single video only)",
    )
    parser.add_argument("--output", help="R2 folder to save output (default: Videos)")
    parser.add_argument("--user-id", required=True, help="User id for storage access")
    parser.add_argument("--temp-dir", help="Temporary working directory")
    parser.add_argument(
        "--keep-local", action="store_true", help="Keep local file (for chaining)"
    )
    parser.add_argument(
        "--no-upload", action="store_true", help="Skip uploading to storage"
    )
    parser.add_argument(
        "--json", action="store_true", help="Output results in JSON format"
    )

    args = parser.parse_args()

    try:
        # Download the video
        result = download_youtube(
            url=args.url,
            audio_only=args.audio,
            is_playlist=args.playlist,
            output_dir=args.output,
            quiet=args.json,
            user_id=args.user_id,
            temp_dir=args.temp_dir,
            keep_local=args.keep_local,
            upload=not args.no_upload,
        )

        # Output results
        if args.json:
            output = {"success": True, "data": result}
            print(json.dumps(output, indent=2))
        else:
            print("\n" + format_human_readable(result))

        sys.exit(0)

    except ValueError as e:
        capture_script_exception(
            e,
            extras={"url": args.url, "audio_only": args.audio},
        )
        error_output = {
            "success": False,
            "error": {
                "type": "ValidationError",
                "message": str(e),
                "suggestions": [
                    "Verify the YouTube URL is correct",
                    "Ensure ffmpeg is installed",
                    "Check if video is accessible (not private/restricted)",
                    "Try with --audio flag for audio-only download",
                ],
            },
        }
        print(json.dumps(error_output, indent=2), file=sys.stderr)
        sys.exit(1)

    except Exception as e:
        capture_script_exception(
            e,
            extras={"url": args.url, "audio_only": args.audio},
        )
        error_output = {
            "success": False,
            "error": {
                "type": "DownloadError",
                "message": str(e),
                "suggestions": [
                    "Check your internet connection",
                    "Verify the video is still available",
                    "Try again later if YouTube is rate-limiting",
                    "Check ffmpeg installation",
                ],
            },
        }
        print(json.dumps(error_output, indent=2), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
