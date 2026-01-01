---
name: youtube-download
description: Download YouTube videos (MP4) or audio (MP3) using yt-dlp with automatic quality selection and format conversion. Use when you need to download videos for offline viewing, extract audio, or archive YouTube content in the files workspace.
---

# youtube-download

Download YouTube videos or audio using yt-dlp.

## Description

Downloads YouTube videos (as MP4) or audio (as MP3) with automatic quality selection, format conversion, and stream verification. Supports single videos and playlists with progress tracking and robust error handling.

## When to Use

- Download YouTube videos for offline viewing
- Extract audio from YouTube videos as MP3
- Download entire playlists
- Archive video content locally
- Create audio library from video content

## Requirements

- **yt-dlp** Python package (installed via pyproject.toml)
- **ffmpeg** system package (required for format conversion)
  - macOS: `brew install ffmpeg`
  - Ubuntu/Debian: `sudo apt-get install ffmpeg`

## Scripts

### download_video.py
Downloads YouTube videos or audio with automatic format selection and conversion.

```bash
python download_video.py URL [--audio] [--playlist] [--output PATH] [--no-upload] [--json]
```

**Arguments**:
- `URL`: YouTube video or playlist URL (required)

**Options**:
- `--audio`: Download audio only (converts to MP3)
- `--playlist`: Download entire playlist (default: single video only)
- `--output`: Output folder (default: files/videos)
- `--no-upload`: Skip uploading to storage (download only)
- `--json`: Output results in JSON format

**Features**:
- Automatic quality selection (best available)
- Format conversion to MP4 (video) or MP3 (audio)
- Stream verification (checks for video + audio)
- Progress tracking with fragment counts
- Robust retry logic (10 retries for fragments)
- Playlist support with batch processing
- URL normalization (handles youtu.be short links)

**Examples**:
```bash
# Download video
python download_video.py "https://youtube.com/watch?v=VIDEO_ID"

# Download audio only
python download_video.py "https://youtube.com/watch?v=VIDEO_ID" --audio

# Download playlist
python download_video.py "https://youtube.com/playlist?list=PLAYLIST_ID" --playlist

# Custom output location
python download_video.py "https://youtube.com/watch?v=VIDEO_ID" --output files/videos

# JSON output
python download_video.py "https://youtube.com/watch?v=VIDEO_ID" --json
```

## Video Output Format

**Video Downloads**:
- Format: MP4 (H.264 video + AAC audio)
- Quality: Best available with AVC codec
- Flags: Fast start enabled for streaming
- Verification: Checks both video and audio streams

**Audio Downloads**:
- Format: MP3
- Quality: 192 kbps
- Source: Best available audio stream (preferably M4A)

## Default Save Location

Videos are saved to your files workspace videos folder:
```
files/videos/
```

Filenames are sanitized and truncated to 100 characters:
```
Video-Title-Here.mp4
Audio-Title-Here.mp3
```

## Error Handling

The skill handles common issues:
- Missing ffmpeg (with installation instructions)
- Invalid URLs (normalizes and validates)
- Private/restricted videos (clear error messages)
- Network failures (automatic retries)
- Missing streams (verification warnings)

## Verification

After download, the skill verifies:
- Video stream presence and codec
- Audio stream presence and codec
- Resolution and bitrate information
- Channel count for audio

## Performance

- Fragment retries: 10 attempts
- Download retries: 10 attempts
- Socket timeout: 30 seconds
- Progress updates: Real-time fragment tracking
