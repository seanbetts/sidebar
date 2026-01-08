#!/usr/bin/env python3
"""Download YouTube Video

Download YouTube videos or audio using yt-dlp with automatic format conversion.
"""

import argparse
import json
import os
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
    from api.services.skill_file_ops import upload_file
except Exception:
    upload_file = None


# Default output directory (files workspace)
DEFAULT_R2_DIR = "files/videos"


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


def verify_output(filepath: str) -> bool:
    """Verify the output file has both video and audio streams.

    Args:
        filepath: Path to the output file

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

        video_info = json.loads(video_result.stdout)
        audio_info = json.loads(audio_result.stdout)

        has_video = len(video_info.get("streams", [])) > 0
        has_audio = len(audio_info.get("streams", [])) > 0

        if has_video:
            v_stream = video_info["streams"][0]
            print(
                f"  Video stream: {v_stream.get('codec_name', 'unknown')} "
                f"({v_stream.get('width', '?')}x{v_stream.get('height', '?')})"
            )
        else:
            print("  Warning: Output file appears to be missing video stream!")

        if has_audio:
            a_stream = audio_info["streams"][0]
            print(
                f"  Audio stream: {a_stream.get('codec_name', 'unknown')} "
                f"({a_stream.get('channels', '?')} channels)"
            )
        else:
            print("  Warning: Output file appears to be missing audio stream!")

        return has_video and has_audio

    except Exception as e:
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
        if upload_file is None:
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
                    verify_output(str(output_path))

        end_time = time.time()
        duration = end_time - start_time

        # Get final filename (postprocessors may change extension)
        final_filename = Path(filename).name
        if audio_only:
            # FFmpegExtractAudio changes extension to .mp3
            final_filename = Path(filename).stem + ".mp3"

        local_output = save_path / final_filename
        if not local_output.exists():
            raise FileNotFoundError(f"Download output not found: {local_output}")

        record = None
        if upload:
            content_type = "audio/mpeg" if audio_only else "video/mp4"
            r2_path = f"{r2_dir}/{final_filename}" if r2_dir else final_filename
            record = upload_file(
                user_id, r2_path, local_output, content_type=content_type
            )
        storage_payload = _build_storage_payload(
            user_id,
            record,
            audio_only=audio_only,
            filename=final_filename,
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
            "duration_seconds": int(duration),
            "success": True,
            **storage_payload,
        }

    except yt_dlp.utils.DownloadError as e:
        error_msg = str(e)
        if "Unavailable video" in error_msg:
            raise ValueError(
                "Video is unavailable (private, age-restricted, or removed)"
            ) from e
        elif "Invalid URL" in error_msg:
            raise ValueError("Invalid YouTube URL") from e
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

    minutes = result["duration_seconds"] // 60
    seconds = result["duration_seconds"] % 60
    lines.append(f"Duration: {minutes}m {seconds}s")

    lines.append("=" * 80)

    return "\n".join(lines)


def main():
    """Main entry point for download_video script."""
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
