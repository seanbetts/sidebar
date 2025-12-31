---
name: youtube-transcribe
description: Transcribe YouTube videos to text by downloading audio and using OpenAI's Whisper API. Use when you need transcripts stored in the files workspace.
---

# youtube-transcribe

Transcribe YouTube videos by downloading audio and running speech-to-text transcription.

## Description

Downloads audio from YouTube videos using the youtube-download skill, then transcribes the audio using the audio-transcribe skill with OpenAI's transcription API. Stores transcripts in the files workspace and does not keep the audio by default.

## When to Use

- Transcribe YouTube lectures or educational content
- Convert YouTube podcasts to text
- Create transcripts of YouTube interviews
- Extract text from YouTube presentations
- Archive YouTube audio content as text

## Requirements

- **youtube-download skill** - Downloads audio from YouTube
  - Requires: ffmpeg (`brew install ffmpeg` on macOS)
  - Requires: yt-dlp (installed via pyproject.toml)
- **audio-transcribe skill** - Transcribes audio files
  - Requires: OPENAI_API_KEY environment variable (stored in Doppler secrets)
  - Requires: pydub and tqdm (installed via pyproject.toml)

## Scripts

### transcribe_youtube.py
Downloads YouTube audio and transcribes it with OpenAI's API.

```bash
python transcribe_youtube.py URL [--language LANG] [--model MODEL] [--output-dir DIR] [--output-name NAME] [--keep-audio] [--audio-dir DIR] [--user-id USER] [--json]
```

**Arguments**:
- `URL`: YouTube video URL (required)

**Options**:
- `--language`: Language code for transcription (default: "en")
- `--model`: Transcription model (default: "gpt-4o-transcribe")
  - Options: gpt-4o-transcribe, gpt-4o-mini-transcribe, whisper-1
- `--output-dir`: Output folder for transcripts (default: files/videos/{video_id}/ai)
- `--output-name`: Transcript filename (default: ai.md)
- `--keep-audio`: Keep downloaded audio file after transcription
- `--audio-dir`: Output folder for downloaded audio (default: files/videos)
- `--user-id`: User id for storage access (required)
- `--json`: Output results in JSON format

**Features**:
- Automatic audio download and transcription
- Progress tracking for both download and transcription stages
- Automatic cleanup of audio files (unless --keep-audio specified)
- Cleanup on error to avoid orphaned files
- Combined error handling from both stages
- Unified output with both audio and transcript locations

**Examples**:
```bash
# Basic transcription
python transcribe_youtube.py "https://youtube.com/watch?v=VIDEO_ID"

# Specify language
python transcribe_youtube.py "https://youtube.com/watch?v=VIDEO_ID" --language es

# Use different model
python transcribe_youtube.py "https://youtube.com/watch?v=VIDEO_ID" --model whisper-1

# Keep audio file after transcription
python transcribe_youtube.py "https://youtube.com/watch?v=VIDEO_ID" --keep-audio

# Custom output locations
python transcribe_youtube.py "https://youtube.com/watch?v=VIDEO_ID" \
  --output-dir files/videos/VIDEO_ID/ai \
  --output-name ai.md \
  --audio-dir files/videos

# JSON output
python transcribe_youtube.py "https://youtube.com/watch?v=VIDEO_ID" --json
```

## Output Format

Human-readable output shows both stages:

```
==========================================================================
Downloading YouTube Audio...
==========================================================================
Title: Example Video
Saved locally for transcription (audio is removed by default)
Filename: Example Video.mp3

==========================================================================
Transcribing Audio...
==========================================================================
File: Example Video.mp3
Transcript: files/videos/VIDEO_ID/ai/ai.md
Duration: 15m 30s

==========================================================================
TRANSCRIPTION COMPLETED SUCCESSFULLY
==========================================================================
YouTube URL: https://youtube.com/watch?v=VIDEO_ID
Transcript: files/videos/VIDEO_ID/ai/ai.md
Audio file: Removed (use --keep-audio to keep)
```

JSON output combines results from both stages:

```json
{
  "success": true,
  "data": {
    "youtube_url": "https://youtube.com/watch?v=VIDEO_ID",
    "title": "Example Video",
    "audio_file": "/tmp/yt-transcribe-.../audio/Example Video.mp3",
    "audio_kept": false,
    "transcript_file": "files/videos/VIDEO_ID/ai/ai.md",
    "language": "en",
    "model": "gpt-4o-transcribe",
    "download_duration_seconds": 45,
    "transcription_duration_seconds": 120
  }
}
```

## Workflow

1. **Download Stage**:
   - Validates YouTube URL
   - Downloads audio using youtube-download skill to `files/videos/` (local only by default)
   - Reports download progress and completion
   - Returns audio file location

2. **Transcription Stage**:
   - Transcribes downloaded audio using audio-transcribe skill
   - Handles automatic chunking for large files
   - Reports transcription progress
   - Saves transcript with metadata

3. **Metadata Update**:
   - Updates transcript to include YouTube URL and video title
   - Replaces audio filename reference with source information

4. **Cleanup Stage**:
   - Removes audio file (unless --keep-audio specified)
   - On error, attempts cleanup to avoid orphaned files

## Error Handling

**Download Errors**:
- Video unavailable (private, age-restricted, removed)
- Invalid YouTube URL
- ffmpeg not installed
- Network connection issues

**Transcription Errors**:
- OPENAI_API_KEY not set
- API rate limits or errors
- Audio file format issues
- Insufficient API credits

**Combined Error Output**:
```json
{
  "success": false,
  "error": {
    "stage": "download|transcription",
    "type": "DownloadError|TranscriptionError",
    "message": "Detailed error message",
    "suggestions": [
      "Action 1",
      "Action 2"
    ]
  }
}
```

## Default Save Locations

**Audio Files (temporary unless `--keep-audio`)**:
```
files/videos/
```
Audio files are automatically deleted after transcription unless `--keep-audio` is specified.

**Transcripts (files workspace)**:
```
files/videos/{video_id}/ai/ai.md
```

## Model Comparison

See audio-transcribe skill documentation for detailed model comparison.

**Quick Reference**:
- **gpt-4o-transcribe** (default): Best quality, 140+ languages
- **gpt-4o-mini-transcribe**: Faster and cheaper
- **whisper-1**: Legacy model, good for very long files

## Usage Costs

Token usage is based on audio duration and transcript length. Check OpenAI pricing for current rates per token.

Cost calculation includes only the transcription stage (audio download is free via yt-dlp).

## Tips

- Use `--keep-audio` if you want to keep the audio file for reference
- Longer videos may require chunking (handled automatically)
- For very long videos (>1 hour), consider using whisper-1 model
- Check YouTube video is not private or age-restricted before running
- Ensure sufficient OpenAI API credits before transcribing long videos

## Related Skills

- **youtube-download** - Download YouTube videos or audio
- **audio-transcribe** - Transcribe audio files to text
