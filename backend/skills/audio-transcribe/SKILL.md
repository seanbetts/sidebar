---
name: audio-transcribe
description: Transcribe audio files to text using OpenAI's Whisper API with automatic chunking for large files. Use when you need to convert meeting recordings, podcasts, interviews, or any audio content to text.
---

# audio-transcribe

Transcribe audio files using OpenAI's transcription API with automatic chunking for large files.

## Description

Transcribes audio files to text using OpenAI's gpt-4o-transcribe, gpt-4o-mini-transcribe, or whisper-1 models. Automatically handles files larger than 25MB by splitting them into chunks and stitching transcripts together. Saves transcripts with metadata including timestamps, model info, and usage statistics.

## When to Use

- Transcribe meeting recordings or interviews
- Convert podcasts or lectures to text
- Create subtitles or captions from audio
- Extract text from voice memos or audio notes
- Process large audio files (automatic chunking)

## Requirements

- **OPENAI_API_KEY** environment variable must be set (stored in Doppler secrets)
- **ffmpeg** system package (for audio processing)
  - macOS: `brew install ffmpeg`
  - Ubuntu/Debian: `sudo apt-get install ffmpeg`
- **pydub** Python package (installed via pyproject.toml)
- **tqdm** Python package (for progress bars)

## Scripts

### transcribe_audio.py
Transcribes audio files with automatic chunking and progress tracking.

```bash
python transcribe_audio.py FILE [--language LANG] [--model MODEL] [--output-dir DIR] [--json]
```

**Arguments**:
- `FILE`: Path to audio file (required)

**Options**:
- `--language`: Language code (default: "en")
- `--model`: Transcription model (default: "gpt-4o-transcribe")
  - Options: gpt-4o-transcribe, gpt-4o-mini-transcribe, whisper-1
- `--output-dir`: Directory for transcripts (default: ~/Documents/Agent Smith/Transcripts)
- `--chunking-strategy`: Use "auto" for automatic VAD-based chunking
- `--prompt`: Optional text to guide model's style
- `--response-format`: Output format (json, text, srt, vtt, verbose_json)
- `--temperature`: Sampling temperature 0-1 (default: 0.0)
- `--json`: Output results in JSON format

**Features**:
- Automatic chunking for files >25MB
- Smart token limit handling for gpt-4o models (5-minute chunks)
- Progress bars for chunking and transcription
- Retry logic with exponential backoff
- Stream verification before chunking
- Metadata headers (timestamp, model, usage stats)

**Examples**:
```bash
# Basic transcription
python transcribe_audio.py meeting.m4a

# Specify language
python transcribe_audio.py interview.mp3 --language es

# Use different model
python transcribe_audio.py podcast.wav --model whisper-1

# Custom output location
python transcribe_audio.py audio.mp4 --output-dir ~/my-transcripts

# Automatic VAD chunking
python transcribe_audio.py large-file.m4a --chunking-strategy auto

# JSON output
python transcribe_audio.py audio.m4a --json
```

## Output Format

Transcripts are saved with metadata headers:

```
# Transcript of meeting.m4a
# Generated: 2025-12-20 14:30:45
# Model: gpt-4o-transcribe
# Original file: /path/to/meeting.m4a
# File size: 15.3MB
# Usage: 1250 total tokens (50 input, 1200 output)
# Audio tokens: 1180
---

[Transcribed text content here]
```

Filenames include timestamps:
```
meeting_20251220_143045_transcript.txt
```

## Default Save Location

Transcripts are saved to:
```
~/Documents/Agent Smith/Transcripts/
```

## Supported Audio Formats

- **Common**: MP3, M4A, MP4, WAV
- **Other**: AAC, FLAC, OGG, and more (via ffmpeg)

Files are automatically converted during chunking to maintain compatibility.

## Chunking Behavior

**Automatic Chunking When**:
- File size > 25MB (API limit)
- File duration > 8 minutes (for gpt-4o models, token limit safety)

**Chunk Parameters**:
- Standard chunks: 5-30 minutes each
- gpt-4o chunks: 5 minutes max (to avoid 2048 token limit)
- 80% of max file size for safety margin
- Full audio coverage verification

## Retry & Error Handling

- **Timeouts**: 3 retries with exponential backoff (1s, 2s, 4s)
- **Server errors (5xx)**: 3 retries with backoff
- **Dynamic timeouts**: Based on file size (120-300 seconds)
- **Clear error messages**: With actionable suggestions

## Progress Tracking

Real-time progress bars show:
- Audio chunking progress
- Transcription progress per chunk
- Chunk details (duration, size)
- Word counts per chunk
- Total coverage verification

## Model Comparison

**gpt-4o-transcribe** (default):
- Best quality and accuracy
- Supports 140+ languages
- 2048 token output limit
- Requires chunking for long files

**gpt-4o-mini-transcribe**:
- Faster and cheaper
- Good quality
- Same token limits as gpt-4o

**whisper-1**:
- Legacy model
- No token limits
- Good for very long files
- Slightly less accurate

## Usage Costs

Token usage is reported in transcript metadata:
- Input tokens: Audio duration
- Output tokens: Transcribed text
- Total tokens: Sum of both

Check OpenAI pricing for current rates per token.
