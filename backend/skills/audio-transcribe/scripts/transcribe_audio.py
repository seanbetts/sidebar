#!/usr/bin/env python3
"""
Transcribe Audio

Transcribe audio files using OpenAI's transcription API with automatic chunking.
"""

import sys
import json
import argparse
import io
import os
import time
import tempfile
from pathlib import Path
from datetime import datetime
from typing import Dict, Any, Optional

import requests
from tqdm import tqdm

# Add backend to sys.path for database mode.
BACKEND_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(BACKEND_ROOT))

try:
    from api.db.session import SessionLocal, set_session_user_id
    from api.services.notes_service import NotesService
    from api.services.skill_file_ops import upload_file, download_file
except Exception:
    SessionLocal = None
    NotesService = None
    upload_file = None
    download_file = None


# Default R2 output directory
DEFAULT_R2_DIR = "Transcripts"

# API size limit (25MB with safety margin)
MAX_SIZE = 25_000_000


def save_transcript_database(
    user_id: str,
    content: str,
    title: str,
    folder: str,
) -> Dict[str, Any]:
    if SessionLocal is None or NotesService is None:
        raise RuntimeError("Database dependencies are unavailable")

    db = SessionLocal()

    set_session_user_id(db, user_id)
    try:
        note = NotesService.create_note(
            db,
            user_id,
            content,
            title=title,
            folder=folder,
        )
        return {
            "id": str(note.id),
            "title": note.title,
            "folder": (note.metadata_ or {}).get("folder", ""),
        }
    finally:
        db.close()


def save_transcript(
    transcript: str,
    original_file: Path,
    model: str,
    output_dir: Path,
    usage_info: Optional[Dict[str, Any]] = None,
    output_name: Optional[str] = None,
) -> Path:
    """
    Save transcript to specified folder with timestamp and metadata.

    Args:
        transcript: Transcribed text
        original_file: Path to original audio file
        model: Model used for transcription
        output_dir: Directory to save transcript
        usage_info: Optional usage statistics from API

    Returns:
        Path to saved transcript file
    """
    # Create output directory if it doesn't exist
    output_dir.mkdir(parents=True, exist_ok=True)

    # Generate filename with timestamp (unless overridden)
    if output_name:
        output_filename = output_name
    else:
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        base_name = original_file.stem
        output_filename = f"{base_name}_{timestamp}_transcript.txt"
    output_path = output_dir / output_filename

    # Create metadata header
    usage_text = ""
    if usage_info:
        usage_text = f"""# Usage: {usage_info.get('total_tokens', 'N/A')} total tokens ({usage_info.get('input_tokens', 'N/A')} input, {usage_info.get('output_tokens', 'N/A')} output)
# Audio tokens: {usage_info.get('input_token_details', {}).get('audio_tokens', 'N/A')}
"""

    file_size_mb = original_file.stat().st_size / (1024 * 1024)
    metadata = f"""# Transcript of {original_file.name}
# Generated: {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}
# Model: {model}
# Original file: {original_file.absolute()}
# File size: {file_size_mb:.1f}MB
{usage_text}---

"""

    # Save transcript with metadata
    output_path.write_text(metadata + transcript, encoding='utf-8')

    return output_path


def save_transcript_to_r2(
    user_id: str,
    transcript_path: Path,
    r2_dir: str,
) -> str:
    if upload_file is None:
        raise RuntimeError("Storage dependencies are unavailable")
    r2_dir = (r2_dir or "").strip("/")
    r2_path = f"{r2_dir}/{transcript_path.name}" if r2_dir else transcript_path.name
    record = upload_file(
        user_id,
        r2_path,
        transcript_path,
        content_type="text/plain",
    )
    return record.path


def post_to_api(
    file_obj: io.BytesIO | io.BufferedReader,
    filename: str,
    language: Optional[str],
    model: str,
    api_key: str,
    max_retries: int = 3,
    **kwargs
) -> Dict[str, Any]:
    """
    Send a single file object to the transcription API with retry logic.

    Args:
        file_obj: File object to transcribe
        filename: Name of the file
        language: Language code (optional)
        model: Model to use
        api_key: OpenAI API key
        max_retries: Maximum number of retry attempts
        **kwargs: Additional API parameters

    Returns:
        API response dictionary

    Raises:
        RuntimeError: If transcription fails
    """
    files = {
        "file": (filename, file_obj, "application/octet-stream"),
    }

    data = {"model": model}
    if language:
        data["language"] = language

    # Add optional parameters
    for key in ['chunking_strategy', 'include', 'prompt', 'response_format', 'temperature', 'timestamp_granularities']:
        if key in kwargs and kwargs[key] is not None:
            data[key] = kwargs[key]

    headers = {"Authorization": f"Bearer {api_key}"}

    # Calculate timeout based on file size
    if hasattr(file_obj, 'getvalue'):
        file_size_mb = len(file_obj.getvalue()) / (1024 * 1024)
    else:
        file_size_mb = 10
    timeout = min(max(120, int(file_size_mb * 30)), 300)

    for attempt in range(max_retries):
        try:
            # Reset file position for retry attempts
            if hasattr(file_obj, 'seek'):
                file_obj.seek(0)

            response = requests.post(
                "https://api.openai.com/v1/audio/transcriptions",
                headers=headers,
                files=files,
                data=data,
                timeout=timeout,
            )
            response.raise_for_status()

            # Parse and return response
            try:
                return response.json()
            except (ValueError, KeyError) as exc:
                raise RuntimeError(f"Invalid API response: {exc}") from exc

        except requests.exceptions.Timeout as exc:
            if attempt < max_retries - 1:
                wait_time = 2 ** attempt  # Exponential backoff
                tqdm.write(f"⏰ Timeout on attempt {attempt + 1}/{max_retries}. Retrying in {wait_time}s...")
                time.sleep(wait_time)
                continue
            else:
                raise RuntimeError(
                    f"Request timed out after {max_retries} attempts. "
                    "Try with a smaller file or check your connection."
                ) from exc

        except requests.exceptions.RequestException as exc:
            # Extract error message
            message = ""
            if hasattr(exc, "response") and exc.response is not None:
                try:
                    message = exc.response.json().get("error", {}).get("message", "")
                except Exception:
                    message = exc.response.text

            # Retry on server errors
            if attempt < max_retries - 1 and exc.response and exc.response.status_code >= 500:
                wait_time = 2 ** attempt
                tqdm.write(f"🔄 Server error on attempt {attempt + 1}/{max_retries}. Retrying in {wait_time}s...")
                time.sleep(wait_time)
                continue
            else:
                raise RuntimeError(f"Failed to call transcription API: {message or exc}") from exc

    raise RuntimeError("Max retries exceeded")


def progress_hook(d):
    """Progress hook for displaying download progress."""
    if d['status'] == 'finished':
        tqdm.write(f"  ✓ {Path(d['filename']).name}")


def segment_audio(
    path: Path,
    max_size: int = MAX_SIZE,
    force_max_duration: Optional[int] = None
) -> list[io.BytesIO]:
    """
    Split an audio file into valid chunks under max_size bytes.

    Args:
        path: Path to audio file
        max_size: Maximum size per chunk in bytes
        force_max_duration: Force maximum chunk duration in seconds (for token limits)

    Returns:
        List of BytesIO objects containing audio chunks

    Raises:
        RuntimeError: If pydub is not available or chunking fails
    """
    try:
        from pydub import AudioSegment
    except Exception as exc:
        raise RuntimeError(
            "pydub is required for splitting large audio files. "
            "Install it via 'pip install pydub' and ensure ffmpeg is available."
        ) from exc

    audio = AudioSegment.from_file(path)
    total_ms = len(audio)

    print(f"🎵 Audio duration: {total_ms / 1000 / 60:.1f} minutes ({total_ms}ms)")

    # Calculate chunk duration based on desired file size
    file_size = path.stat().st_size
    bytes_per_ms = file_size / total_ms
    target_chunk_ms = int(max_size * 0.8 / bytes_per_ms)  # 80% of max size for safety

    # Ensure reasonable chunk size
    min_chunk_ms = 5 * 60 * 1000  # 5 minutes
    max_chunk_ms = 30 * 60 * 1000  # 30 minutes

    # If force_max_duration is specified (for token limits), use that
    if force_max_duration:
        max_chunk_ms = force_max_duration * 1000
        print(f"🔒 Forcing max chunk duration to {force_max_duration/60:.1f} minutes for token limits")

    chunk_ms = max(min_chunk_ms, min(target_chunk_ms, max_chunk_ms))

    # Calculate number of chunks
    num_chunks = int((total_ms + chunk_ms - 1) // chunk_ms)

    print(f"📐 Splitting into {num_chunks} chunks of ~{chunk_ms / 1000 / 60:.1f} minutes each")

    # Map file extensions to compatible ffmpeg formats
    format_mapping = {
        '.m4a': 'mp4',
        '.aac': 'mp4',
        '.mp4': 'mp4',
        '.mp3': 'mp3',
        '.wav': 'wav',
        '.flac': 'flac',
        '.ogg': 'ogg'
    }

    original_ext = path.suffix.lower()
    export_format = format_mapping.get(original_ext, 'mp3')
    export_ext = '.mp3' if export_format == 'mp3' else original_ext

    chunks: list[io.BytesIO] = []

    # Create chunks with full coverage
    chunks_info = []
    current_start = 0
    chunk_index = 1

    while current_start < total_ms:
        end = min(current_start + chunk_ms, total_ms)
        chunks_info.append({
            'index': chunk_index,
            'start': current_start,
            'end': end,
            'duration': end - current_start
        })
        current_start = end
        chunk_index += 1

    print(f"📊 Will create {len(chunks_info)} chunks covering {total_ms/1000/60:.1f} minutes")

    # Create chunks with progress bar
    with tqdm(total=len(chunks_info), desc="🔪 Splitting audio", unit="chunk", leave=False) as pbar:
        for chunk_info in chunks_info:
            start = chunk_info['start']
            end = chunk_info['end']
            index = chunk_info['index']

            segment = audio[start:end]
            duration_sec = len(segment) / 1000

            buf = io.BytesIO()
            segment.export(buf, format=export_format)
            buf.name = f"{path.stem}.part{index}{export_ext}"
            buf.seek(0)

            chunk_size_mb = buf.getbuffer().nbytes / (1024 * 1024)

            if buf.getbuffer().nbytes > max_size:
                raise RuntimeError(
                    f"Chunk {index} ({chunk_size_mb:.1f}MB) exceeds "
                    f"{max_size/(1024*1024):.1f}MB limit"
                )

            tqdm.write(f"📝 Chunk {index}: {start/1000/60:.1f}-{end/1000/60:.1f}min "
                      f"({duration_sec:.1f}s, {chunk_size_mb:.1f}MB)")

            chunks.append(buf)
            pbar.update(1)

    # Verify coverage
    total_chunk_duration = sum(info['duration'] for info in chunks_info)
    coverage_percent = (total_chunk_duration / total_ms) * 100
    print(f"✅ Audio coverage: {coverage_percent:.1f}% "
          f"({total_chunk_duration/1000/60:.1f}/{total_ms/1000/60:.1f} minutes)")

    return chunks


def transcribe_audio(
    file_path: str,
    language: Optional[str] = None,
    model: str = "gpt-4o-transcribe",
    output_dir: Optional[str] = None,
    *,
    user_id: Optional[str] = None,
    temp_dir: Optional[str] = None,
    keep_local: bool = False,
    output_name: Optional[str] = None,
    **kwargs
) -> Dict[str, Any]:
    """
    Transcribe an audio file using OpenAI's transcription endpoint.

    Args:
        file_path: Path to audio file
        language: Language code (optional)
        model: Model to use
        output_dir: Output directory for transcripts
        **kwargs: Additional API parameters

    Returns:
        Dictionary with transcription results

    Raises:
        RuntimeError: If OPENAI_API_KEY not set
        FileNotFoundError: If audio file not found
        Exception: If transcription fails
    """
    api_key = os.getenv("OPENAI_API_KEY")
    if not api_key:
        raise RuntimeError("OPENAI_API_KEY environment variable is not set")
    if not user_id:
        raise ValueError("user_id is required for transcript storage")

    path = Path(file_path)
    temp_root = Path(temp_dir) if temp_dir else Path(tempfile.mkdtemp(prefix="audio-input-"))
    cleanup_temp = temp_dir is None

    if not path.exists() or not path.is_file():
        if not user_id or download_file is None:
            raise FileNotFoundError(f"Audio file not found: {file_path}")
        local_input = temp_root / Path(file_path).name
        download_file(user_id, file_path, local_input)
        path = local_input

    # Local output directory (always temp)
    out_dir = Path(temp_dir) if temp_dir else Path(tempfile.mkdtemp(prefix="transcripts-"))
    r2_dir = (output_dir or DEFAULT_R2_DIR).strip("/")

    file_size_mb = path.stat().st_size / (1024 * 1024)
    print(f"📁 Processing {path.name} ({file_size_mb:.1f}MB) with model {model}")

    # Check if we need to chunk for gpt-4o models
    needs_chunking_for_tokens = False
    if model.startswith('gpt-4o'):
        estimated_minutes = file_size_mb * 0.8
        if estimated_minutes > 8:
            needs_chunking_for_tokens = True
            print(f"🔄 File estimated at {estimated_minutes:.1f} minutes - "
                  "chunking to avoid gpt-4o token limits")

    # Process file
    if path.stat().st_size > MAX_SIZE or needs_chunking_for_tokens:
        if path.stat().st_size > MAX_SIZE:
            print(f"📏 File exceeds {MAX_SIZE / (1024*1024):.1f}MB limit, splitting...")
        else:
            print("📏 Splitting into chunks to avoid token limits...")

        transcripts = []
        force_duration = 300 if model.startswith('gpt-4o') else None
        chunks = segment_audio(path, force_max_duration=force_duration)

        print(f"🎯 Created {len(chunks)} chunks, starting transcription...")

        last_usage = None
        with tqdm(total=len(chunks), desc="🎙️  Transcribing", unit="chunk") as pbar:
            for idx, chunk in enumerate(chunks, start=1):
                chunk_size_mb = len(chunk.getvalue()) / (1024 * 1024)
                pbar.set_description(f"🎙️  Transcribing chunk {idx}/{len(chunks)} ({chunk_size_mb:.1f}MB)")

                try:
                    response = post_to_api(chunk, chunk.name, language, model, api_key, **kwargs)
                    transcript = response.get('text', '')
                    last_usage = response.get('usage')
                    transcripts.append(transcript)

                    word_count = len(transcript.split()) if transcript else 0
                    tqdm.write(f"✓ Chunk {idx} complete: {word_count} words")

                    pbar.update(1)
                except Exception as e:
                    tqdm.write(f"❌ Failed to transcribe chunk {idx}: {e}")
                    raise

        combined_transcript = " ".join(transcripts)
        print(f"✅ Transcription complete! Combined {len(transcripts)} chunks.")
        print(f"📊 Total words: {len(combined_transcript.split())}")

        output_path = save_transcript(
            combined_transcript,
            path,
            model,
            out_dir,
            last_usage,
            output_name=output_name,
        )
        print(f"💾 Transcript saved to: {output_path}")

        r2_path = None
        if user_id:
            r2_path = save_transcript_to_r2(user_id, output_path, r2_dir)

        return {
            'transcript': combined_transcript,
            'output_path': r2_path or str(output_path),
            'local_path': str(output_path) if keep_local else None,
            'word_count': len(combined_transcript.split()),
            'chunks': len(transcripts),
            'model': model,
            'usage': last_usage
        }
    else:
        print("📤 Uploading single file for transcription...")
        with path.open("rb") as f:
            response = post_to_api(f, path.name, language, model, api_key, **kwargs)
            transcript = response.get('text', '')
            usage_info = response.get('usage')

        print(f"✅ Transcription complete!")
        print(f"📊 Total words: {len(transcript.split())}")

        output_path = save_transcript(
            transcript,
            path,
            model,
            out_dir,
            usage_info,
            output_name=output_name,
        )
        print(f"💾 Transcript saved to: {output_path}")

        r2_path = None
        if user_id:
            r2_path = save_transcript_to_r2(user_id, output_path, r2_dir)

        return {
            'transcript': transcript,
            'output_path': r2_path or str(output_path),
            'local_path': str(output_path) if keep_local else None,
            'word_count': len(transcript.split()),
            'chunks': 1,
            'model': model,
            'usage': usage_info
        }


def main() -> None:
    """Main entry point for transcribe_audio script."""
    parser = argparse.ArgumentParser(
        description='Transcribe audio using OpenAI API',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=f"""
Default Output (R2): {DEFAULT_R2_DIR}

Examples:
  # Basic transcription
  %(prog)s meeting.m4a

  # Specify language
  %(prog)s interview.mp3 --language es

  # Use different model
  %(prog)s podcast.wav --model whisper-1

  # Custom output directory
  %(prog)s audio.mp4 --output-dir Transcripts

  # Automatic VAD chunking
  %(prog)s large-file.m4a --chunking-strategy auto

Supported Models:
  - gpt-4o-transcribe (default, best quality)
  - gpt-4o-mini-transcribe (faster, cheaper)
  - whisper-1 (legacy, no token limits)

Requirements:
  - OPENAI_API_KEY environment variable
  - ffmpeg (for audio processing)
        """
    )

    parser.add_argument("file", help="Path to audio file")
    parser.add_argument("--language", default="en", help="Language hint (default: en)")
    parser.add_argument("--model", default="gpt-4o-transcribe", help="Transcription model")
    parser.add_argument("--output-dir", help="R2 folder for transcripts (default: Transcripts)")
    parser.add_argument("--output-name", help="Output filename override (default: timestamped)")
    parser.add_argument("--chunking-strategy", help="Use 'auto' for automatic VAD-based chunking")
    parser.add_argument("--include", action="append", help="Additional info to include")
    parser.add_argument("--prompt", help="Optional text to guide the model's style")
    parser.add_argument("--response-format", default="json", help="Output format (default: json)")
    parser.add_argument("--temperature", type=float, default=0.0, help="Sampling temperature")
    parser.add_argument("--timestamp-granularities", action="append", help="Timestamp granularities")
    parser.add_argument("--json", action="store_true", help="Output results in JSON format")
    parser.add_argument("--database", action="store_true", help="Save transcript to the database")
    parser.add_argument("--user-id", help="User id for storage/database access")
    parser.add_argument("--temp-dir", help="Temporary working directory")
    parser.add_argument(
        "--keep-local",
        action="store_true",
        help="Keep local transcript file (for chaining)",
    )
    parser.add_argument(
        "--folder",
        help="Database folder for transcript note (default: Transcripts/Audio)",
    )

    args = parser.parse_args()

    # Parse chunking strategy
    chunking_strategy = None
    if args.chunking_strategy:
        chunking_strategy = "auto" if args.chunking_strategy == "auto" else args.chunking_strategy

    try:
        redirected_stdout = None
        try:
            if args.json:
                redirected_stdout = sys.stdout
                sys.stdout = sys.stderr
            result = transcribe_audio(
                args.file,
                language=args.language,
                model=args.model,
                output_dir=args.output_dir,
                user_id=args.user_id,
                temp_dir=args.temp_dir,
                keep_local=args.keep_local,
                output_name=args.output_name,
                chunking_strategy=chunking_strategy,
                include=args.include,
                prompt=args.prompt,
                response_format=args.response_format,
                temperature=args.temperature,
                timestamp_granularities=args.timestamp_granularities
            )
        finally:
            if redirected_stdout is not None:
                sys.stdout = redirected_stdout

        note_data = None
        if args.database:
            if not args.user_id:
                raise ValueError("user_id is required for database mode")
            transcript_content = result["transcript"]
            note_title = f"Transcript: {Path(args.file).stem}"
            note_folder = args.folder or "Transcripts/Audio"
            note_data = save_transcript_database(
                args.user_id,
                transcript_content,
                note_title,
                note_folder,
            )

        if args.json:
            # Don't include full transcript in JSON output (it's saved to file)
            output = {
                'success': True,
                'data': {
                    'output_path': result['output_path'],
                    'local_path': result.get('local_path'),
                    'word_count': result['word_count'],
                    'chunks': result['chunks'],
                    'model': result['model'],
                    'usage': result.get('usage'),
                    'note': note_data
                }
            }
            print(json.dumps(output, indent=2))
        else:
            if note_data:
                print(f"🗒️ Note created: {note_data['id']}")
            print("\n" + result['transcript'])

        sys.exit(0)

    except (RuntimeError, FileNotFoundError) as e:
        error_output = {
            'success': False,
            'error': {
                'type': 'ValidationError',
                'message': str(e),
                'suggestions': [
                    'Ensure OPENAI_API_KEY environment variable is set',
                    'Verify audio file exists and is readable',
                    'Check that ffmpeg is installed',
                    'Ensure pydub is installed (pip install pydub)'
                ]
            }
        }
        print(json.dumps(error_output, indent=2), file=sys.stderr)
        sys.exit(1)

    except Exception as e:
        error_output = {
            'success': False,
            'error': {
                'type': 'TranscriptionError',
                'message': str(e),
                'suggestions': [
                    'Check your internet connection',
                    'Verify OpenAI API key is valid',
                    'Try with a smaller audio file',
                    'Check if audio format is supported'
                ]
            }
        }
        print(json.dumps(error_output, indent=2), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
