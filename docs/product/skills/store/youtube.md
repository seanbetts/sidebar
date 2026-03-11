---
title: YouTube
summary: Download YouTube videos and audio, and transcribe them into text.
tags: [skills, store, youtube, transcription, video]
audience: user
surfaces: [app, website, internal-knowledge]
skill_id: [youtube-download, youtube-transcribe]
---

## What it does

The YouTube skill lets sideBar download videos and audio from YouTube and,
optionally, transcribe them into text. You can save a video as an MP4, pull
just the audio as an MP3, or go straight to a transcript without keeping
the audio at all. Transcripts are saved to your Files and available to
sideBar in any future conversation.

## Actions

| Action | Description |
| --- | --- |
| Download video | Downloads a YouTube video as an MP4 file and saves it to your Files |
| Download audio | Downloads the audio from a YouTube video as an MP3 file and saves it to your Files |
| Transcribe YouTube | Downloads the audio from a YouTube video, transcribes it, and saves the transcript to your Files. The audio file is deleted automatically once transcription is complete |

## When sideBar uses it

When you share a YouTube URL and ask sideBar to download or transcribe it.
Common triggers:

- "Download this YouTube video"
- "Save the audio from this video as an MP3"
- "Transcribe this YouTube video"
- "Get me a transcript of this talk"

## Requirements

- **Tier:** Store (install from the Skills Store)
- **API key:** An OpenAI API key is required for transcription. Downloading
  video or audio only does not require any API key.

## How to install

1. Open the Skills Store and find YouTube.
2. Tap **Install**. If you want transcription, enter your OpenAI API key when
   prompted. You can skip this and add it later if you only need downloads.
3. The skill is ready immediately.

## What you get

- **Videos** are saved as MP4 files in a **Videos** folder in your Files.
- **Audio** is saved as MP3 files (192 kbps) in the same **Videos** folder.
- **Transcripts** are saved as markdown files alongside the video, including
  the video title, URL, and a timestamp. The audio is deleted automatically
  after transcription unless you ask sideBar to keep it.

Playlist URLs are also supported — sideBar will download each video in the
playlist in sequence.

## Examples

> "Download this YouTube video: [URL]"

> "Save just the audio from this talk as an MP3."

> "Transcribe this video and summarise the key points."

> "Download this playlist."
