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
from pathlib import Path
from typing import Dict, Any, Optional


# Default directories
DEFAULT_TRANSCRIPT_DIR = Path.home() / "Documents" / "Agent Smith" / "Transcripts"
DEFAULT_AUDIO_DIR = Path.home() / "Library" / "Mobile Documents" / "com~apple~CloudDocs" / "Downloads"

# Script paths
YOUTUBE_DOWNLOAD_SCRIPT = Path("/skills/youtube-download/scripts/download_video.py")
AUDIO_TRANSCRIBE_SCRIPT = Path("/skills/audio-transcribe/scripts/transcribe_audio.py")


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
    audio_dir: Optional[str] = None,
    keep_audio: bool = False
) -> Dict[str, Any]:
    """
    Download YouTube audio and transcribe it.

    Args:
        url: YouTube video URL
        language: Language code for transcription
        model: Transcription model to use
        output_dir: Directory for transcripts (default: ~/Documents/Agent Smith/Transcripts)
        audio_dir: Directory for audio files (default: iCloud Downloads)
        keep_audio: Keep audio file after transcription

    Returns:
        Dictionary with combined results from both stages

    Raises:
        RuntimeError: If download or transcription fails
    """
    start_time = time.time()

    # Stage 1: Download audio
    print("=" * 80)
    print("Downloading YouTube Audio...")
    print("=" * 80)

    download_cmd = [
        "python3",
        str(YOUTUBE_DOWNLOAD_SCRIPT),
        url,
        "--audio",
        "--json"
    ]

    if audio_dir:
        download_cmd.extend(["--output", audio_dir])

    download_result = run_command(download_cmd, "download")

    if not download_result.get('success'):
        raise RuntimeError(f"Download failed: {download_result.get('error', {}).get('message', 'Unknown error')}")

    download_data = download_result['data']
    audio_file_path = Path(download_data['output_dir']) / download_data['filename']

    print(f"Title: {download_data['title']}")
    print(f"Saved to: {download_data['output_dir']}")
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
        "--json"
    ]

    if output_dir:
        transcribe_cmd.extend(["--output-dir", output_dir])

    try:
        transcribe_result = run_command(transcribe_cmd, "transcription")

        if not transcribe_result.get('success'):
            raise RuntimeError(f"Transcription failed: {transcribe_result.get('error', {}).get('message', 'Unknown error')}")

        transcribe_data = transcribe_result['data']

        print(f"File: {audio_file_path.name}")
        print(f"Transcript: {transcribe_data['output_file']}")

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

        return {
            'youtube_url': url,
            'title': download_data['title'],
            'audio_file': str(audio_file_path),
            'audio_kept': audio_kept,
            'transcript_file': transcribe_data['output_file'],
            'language': language,
            'model': model,
            'download_duration_seconds': download_data['duration_seconds'],
            'transcription_duration_seconds': transcription_duration,
            'file_size': transcribe_data.get('file_size', 'Unknown'),
            'audio_duration': transcribe_data.get('duration', 'Unknown')
        }

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
Default Transcript Directory: {DEFAULT_TRANSCRIPT_DIR}
Default Audio Directory: {DEFAULT_AUDIO_DIR}

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
    --output-dir ~/my-transcripts \\
    --audio-dir ~/my-audio

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
        help=f'Directory for transcripts (default: {DEFAULT_TRANSCRIPT_DIR})'
    )
    parser.add_argument(
        '--audio-dir',
        help=f'Directory for audio files (default: {DEFAULT_AUDIO_DIR})'
    )
    parser.add_argument(
        '--keep-audio',
        action='store_true',
        help='Keep audio file after transcription (default: remove)'
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
            audio_dir=args.audio_dir,
            keep_audio=args.keep_audio
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
