#!/usr/bin/env python3
"""
Transcribe YouTube Video

Download YouTube audio and transcribe it using OpenAI's transcription API.
Combines youtube-download and audio-transcribe skills.
"""

import sys
import json
import argparse
import subprocess
import time
import tempfile
import urllib.parse
from pathlib import Path
from typing import Dict, Any, Optional

# Add backend to sys.path for database mode.
BACKEND_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(BACKEND_ROOT))

try:
    from api.db.session import SessionLocal, set_session_user_id
    from api.services.notes_service import NotesService
    from api.services.skill_file_ops import upload_file
except Exception:
    SessionLocal = None
    NotesService = None
    upload_file = None


# Default directories (R2)
DEFAULT_TRANSCRIPT_DIR = "files/videos/{video_id}/ai"

# Script paths - dynamically locate based on this script's location
SCRIPT_DIR = Path(__file__).parent.parent.parent  # Go up to skills/
PROJECT_ROOT = SCRIPT_DIR.parent  # Go up to project root

YOUTUBE_DOWNLOAD_SCRIPT = SCRIPT_DIR / "youtube-download" / "scripts" / "download_video.py"
AUDIO_TRANSCRIBE_SCRIPT = SCRIPT_DIR / "audio-transcribe" / "scripts" / "transcribe_audio.py"


def update_transcript_metadata(transcript_path: str, youtube_url: str, title: str) -> None:
    """
    Update transcript metadata to include YouTube URL instead of audio filename.

    Args:
        transcript_path: Path to the transcript file
        youtube_url: Original YouTube video URL
        title: Video title
    """
    try:
        with open(transcript_path, 'r', encoding='utf-8') as f:
            content = f.read()

        # Replace the "Original file:" line with YouTube URL
        lines = content.split('\n')
        updated_lines = []
        for line in lines:
            if line.startswith('# Original file:'):
                updated_lines.append(f'# YouTube URL: {youtube_url}')
                updated_lines.append(f'# Video title: {title}')
            else:
                updated_lines.append(line)

        # Write back
        with open(transcript_path, 'w', encoding='utf-8') as f:
            f.write('\n'.join(updated_lines))

    except Exception as e:
        # Don't fail the whole operation if metadata update fails
        print(f"Warning: Could not update transcript metadata: {e}")


def extract_video_id(url: str) -> Optional[str]:
    """Extract a YouTube video id from a URL."""
    try:
        parsed = urllib.parse.urlparse(url)
        if not parsed.scheme:
            parsed = urllib.parse.urlparse("https://" + url)
        if "youtu.be" in parsed.netloc:
            return parsed.path.strip("/") or None
        query = urllib.parse.parse_qs(parsed.query)
        if "v" in query and query["v"]:
            return query["v"][0]
    except Exception:
        return None
    return None

def run_command(cmd: list, stage: str) -> Dict[str, Any]:
    """
    Run a command and return parsed JSON output.

    Args:
        cmd: Command to run as list of arguments
        stage: Stage name for error reporting ("download" or "transcription")

    Returns:
        Parsed JSON output from command

    Raises:
        RuntimeError: If command fails
    """
    try:
        result = subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False
        )

        if result.returncode != 0:
            # Try to parse error JSON from stderr
            try:
                error_data = json.loads(result.stderr)
                raise RuntimeError(
                    f"{stage.capitalize()} failed: {error_data.get('error', {}).get('message', 'Unknown error')}"
                )
            except json.JSONDecodeError:
                # If not JSON, use raw stderr
                raise RuntimeError(f"{stage.capitalize()} failed: {result.stderr}")

        # Parse successful JSON output
        try:
            return json.loads(result.stdout)
        except json.JSONDecodeError:
            raise RuntimeError(f"Failed to parse {stage} output as JSON")

    except subprocess.SubprocessError as e:
        raise RuntimeError(f"{stage.capitalize()} command failed: {e}") from e


def transcribe_youtube(
    url: str,
    language: str = "en",
    model: str = "gpt-4o-transcribe",
    output_dir: Optional[str] = None,
    output_name: Optional[str] = None,
    audio_dir: Optional[str] = None,
    keep_audio: bool = False,
    database: bool = False,
    folder: Optional[str] = None,
    user_id: Optional[str] = None,
) -> Dict[str, Any]:
    """
    Download YouTube audio and transcribe it.

    Args:
        url: YouTube video URL
        language: Language code for transcription
        model: Transcription model to use
        output_dir: R2 folder for transcripts (default: Transcripts)
        audio_dir: R2 folder for audio files (default: Videos)
        keep_audio: Keep audio file after transcription

    Returns:
        Dictionary with combined results from both stages

    Raises:
        RuntimeError: If download or transcription fails
    """
    start_time = time.time()

    if not user_id:
        raise ValueError("user_id is required for storage")

    transcript_dir = output_dir
    if not transcript_dir:
        video_id = extract_video_id(url) or "unknown"
        transcript_dir = f"files/videos/{video_id}/ai"
    transcript_dir = transcript_dir.strip("/")
    transcript_name = output_name or "ai.md"
    temp_root = Path(tempfile.mkdtemp(prefix="yt-transcribe-"))
    target_audio_dir = temp_root / "audio"
    target_audio_dir.mkdir(parents=True, exist_ok=True)

    # Stage 1: Download audio
    print("=" * 80)
    print("Downloading YouTube Audio...")
    print("=" * 80)

    download_cmd = [
        "python3",
        str(YOUTUBE_DOWNLOAD_SCRIPT),
        url,
        "--audio",
        "--json",
        "--output", audio_dir or "files/videos",
        "--user-id", user_id,
        "--temp-dir", str(target_audio_dir),
        "--keep-local",
        "--no-upload",
    ]

    download_result = run_command(download_cmd, "download")

    if not download_result.get('success'):
        raise RuntimeError(f"Download failed: {download_result.get('error', {}).get('message', 'Unknown error')}")

    download_data = download_result['data']
    audio_file_path = Path(download_data.get("local_path") or (Path(download_data['output_dir']) / download_data['filename']))

    print(f"Title: {download_data['title']}")
    print(f"Saved to: {download_data.get('r2_path') or download_data['output_dir']}")
    print(f"Filename: {download_data['filename']}")
    print()

    # Stage 2: Transcribe audio
    print("=" * 80)
    print("Transcribing Audio...")
    print("=" * 80)

    transcribe_cmd = [
        "python3",
        str(AUDIO_TRANSCRIBE_SCRIPT),
        str(audio_file_path),
        "--language", language,
        "--model", model,
        "--json",
        "--user-id", user_id,
        "--output-dir", transcript_dir,
        "--output-name", transcript_name,
        "--temp-dir", str(temp_root / "transcripts"),
        "--keep-local",
    ]

    try:
        transcribe_result = run_command(transcribe_cmd, "transcription")

        if not transcribe_result.get('success'):
            raise RuntimeError(f"Transcription failed: {transcribe_result.get('error', {}).get('message', 'Unknown error')}")

        transcribe_data = transcribe_result['data']

        transcript_path = Path(transcribe_data.get("local_path") or transcribe_data['output_path'])

        print(f"File: {audio_file_path.name}")
        print(f"Transcript: {transcript_path}")

        # Update transcript metadata with YouTube URL
        update_transcript_metadata(
            str(transcript_path),
            url,
            download_data['title']
        )
        if upload_file is not None and transcribe_data.get("output_path"):
            upload_file(user_id, transcribe_data["output_path"], transcript_path, content_type="text/plain")

        # Calculate transcription duration
        transcription_duration = int(time.time() - start_time) - download_data['duration_seconds']

        # Stage 3: Cleanup (if not keeping audio)
        audio_kept = keep_audio
        if not keep_audio and audio_file_path.exists():
            try:
                audio_file_path.unlink()
                print(f"Audio file removed: {audio_file_path}")
            except Exception as e:
                print(f"Warning: Could not remove audio file: {e}")
                audio_kept = True

        note_data = None
        if database:
            if SessionLocal is None or NotesService is None:
                raise RuntimeError("Database dependencies are unavailable")
            if not user_id:
                raise ValueError("user_id is required for database mode")
            transcript_content = transcript_path.read_text(encoding="utf-8")
            note_title = f"Transcript: {download_data['title']}"
            note_folder = folder or "Transcripts/YouTube"
            db = SessionLocal()
            set_session_user_id(db, user_id)
            try:
                note = NotesService.create_note(
                    db,
                    user_id,
                    transcript_content,
                    title=note_title,
                    folder=note_folder,
                )
                note_data = {
                    "id": str(note.id),
                    "title": note.title,
                    "folder": (note.metadata_ or {}).get("folder", ""),
                }
            finally:
                db.close()

        result = {
            'youtube_url': url,
            'title': download_data['title'],
            'audio_file': download_data.get('r2_path') or str(audio_file_path),
            'audio_kept': audio_kept,
            'transcript_file': transcribe_data.get('output_path') or str(transcript_path),
            'language': language,
            'model': model,
            'download_duration_seconds': download_data['duration_seconds'],
            'transcription_duration_seconds': transcription_duration,
            'file_size': transcribe_data.get('file_size', 'Unknown'),
            'audio_duration': transcribe_data.get('duration', 'Unknown')
        }
        if note_data:
            result['note'] = note_data
        return result

    except Exception as e:
        # On transcription error, try to cleanup audio file
        if not keep_audio and audio_file_path.exists():
            try:
                audio_file_path.unlink()
                print(f"Cleaned up audio file after error: {audio_file_path}")
            except Exception as cleanup_error:
                print(f"Warning: Could not cleanup audio file: {cleanup_error}")
        raise


def format_human_readable(result: Dict[str, Any]) -> str:
    """
    Format result in human-readable format.

    Args:
        result: Result dictionary from transcribe_youtube

    Returns:
        Formatted string for display
    """
    lines = []

    lines.append("=" * 80)
    lines.append("TRANSCRIPTION COMPLETED SUCCESSFULLY")
    lines.append("=" * 80)
    lines.append("")

    lines.append(f"YouTube URL: {result['youtube_url']}")
    lines.append(f"Title: {result['title']}")
    lines.append(f"Language: {result['language']}")
    lines.append(f"Model: {result['model']}")
    lines.append("")

    lines.append(f"Transcript: {result['transcript_file']}")
    lines.append(f"Audio file: {result['audio_file']}")

    if result['audio_kept']:
        lines.append("  Status: Kept")
    else:
        lines.append("  Status: Removed (use --keep-audio to keep)")

    lines.append("")
    lines.append(f"File size: {result['file_size']}")
    lines.append(f"Audio duration: {result['audio_duration']}")

    download_min = result['download_duration_seconds'] // 60
    download_sec = result['download_duration_seconds'] % 60
    transcribe_min = result['transcription_duration_seconds'] // 60
    transcribe_sec = result['transcription_duration_seconds'] % 60

    lines.append(f"Download time: {download_min}m {download_sec}s")
    lines.append(f"Transcription time: {transcribe_min}m {transcribe_sec}s")

    lines.append("=" * 80)

    return '\n'.join(lines)


def main():
    """Main entry point for transcribe_youtube script."""
    parser = argparse.ArgumentParser(
        description='Download YouTube audio and transcribe it',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=f"""
Default Transcript Directory (R2): {DEFAULT_TRANSCRIPT_DIR}

Examples:
  # Basic transcription
  %(prog)s "https://youtube.com/watch?v=VIDEO_ID"

  # Specify language
  %(prog)s "https://youtube.com/watch?v=VIDEO_ID" --language es

  # Use different model
  %(prog)s "https://youtube.com/watch?v=VIDEO_ID" --model whisper-1

  # Keep audio file
  %(prog)s "https://youtube.com/watch?v=VIDEO_ID" --keep-audio

  # Custom output locations
  %(prog)s "https://youtube.com/watch?v=VIDEO_ID" \\
    --output-dir Transcripts \\
    --output-name ai.md \\
    --audio-dir Videos

  # JSON output
  %(prog)s "https://youtube.com/watch?v=VIDEO_ID" --json

Requirements:
  - ffmpeg must be installed (brew install ffmpeg on macOS)
  - OPENAI_API_KEY must be set (stored in Doppler secrets)
        """
    )

    # Required argument
    parser.add_argument(
        'url',
        help='YouTube video URL'
    )

    # Optional arguments
    parser.add_argument(
        '--language',
        default='en',
        help='Language code for transcription (default: en)'
    )
    parser.add_argument(
        '--model',
        default='gpt-4o-transcribe',
        choices=['gpt-4o-transcribe', 'gpt-4o-mini-transcribe', 'whisper-1'],
        help='Transcription model (default: gpt-4o-transcribe)'
    )
    parser.add_argument(
        '--output-dir',
        help=f'R2 folder for transcripts (default: {DEFAULT_TRANSCRIPT_DIR})'
    )
    parser.add_argument(
        '--output-name',
        help='Transcript filename (default: ai.md)'
    )
    parser.add_argument(
        '--audio-dir',
        help='R2 folder for audio (default: Videos)'
    )
    parser.add_argument(
        '--keep-audio',
        action='store_true',
        help='Keep audio file after transcription (default: remove)'
    )
    parser.add_argument(
        '--database',
        action='store_true',
        help='Save transcript to the database'
    )
    parser.add_argument(
        '--user-id',
        required=True,
        help='User id for storage access'
    )
    parser.add_argument(
        '--folder',
        help='Database folder for transcript note (default: Transcripts/YouTube)'
    )
    parser.add_argument(
        '--json',
        action='store_true',
        help='Output results in JSON format'
    )

    args = parser.parse_args()

    try:
        # Transcribe the YouTube video
        result = transcribe_youtube(
            url=args.url,
            language=args.language,
            model=args.model,
            output_dir=args.output_dir,
            output_name=args.output_name,
            audio_dir=args.audio_dir,
            keep_audio=args.keep_audio,
            database=args.database,
            folder=args.folder,
            user_id=args.user_id,
        )

        # Output results
        if args.json:
            output = {
                'success': True,
                'data': result
            }
            print(json.dumps(output, indent=2))
        else:
            print("\n" + format_human_readable(result))

        sys.exit(0)

    except RuntimeError as e:
        error_message = str(e)
        stage = "download" if "download" in error_message.lower() else "transcription"

        error_output = {
            'success': False,
            'error': {
                'stage': stage,
                'type': f'{stage.capitalize()}Error',
                'message': error_message,
                'suggestions': [
                    'Check your internet connection' if stage == 'download' else 'Verify OPENAI_API_KEY is set',
                    'Ensure ffmpeg is installed' if stage == 'download' else 'Check OpenAI API credits',
                    'Verify the YouTube URL is correct' if stage == 'download' else 'Try with a different model',
                    'Check if video is accessible (not private/restricted)' if stage == 'download' else 'Ensure audio file is valid'
                ]
            }
        }

        if args.json:
            print(json.dumps(error_output, indent=2), file=sys.stderr)
        else:
            print(f"\nError: {error_message}", file=sys.stderr)
            print("\nSuggestions:", file=sys.stderr)
            for suggestion in error_output['error']['suggestions']:
                print(f"  - {suggestion}", file=sys.stderr)

        sys.exit(1)

    except Exception as e:
        error_output = {
            'success': False,
            'error': {
                'stage': 'unknown',
                'type': 'UnexpectedError',
                'message': str(e),
                'suggestions': [
                    'Check that youtube-download and audio-transcribe skills are properly installed',
                    'Verify all required dependencies are installed',
                    'Check system logs for more details'
                ]
            }
        }

        if args.json:
            print(json.dumps(error_output, indent=2), file=sys.stderr)
        else:
            print(f"\nUnexpected error: {e}", file=sys.stderr)
            print("\nSuggestions:", file=sys.stderr)
            for suggestion in error_output['error']['suggestions']:
                print(f"  - {suggestion}", file=sys.stderr)

        sys.exit(1)


if __name__ == '__main__':
    main()
