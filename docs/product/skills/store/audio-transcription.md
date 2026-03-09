---
title: Audio Transcription
summary: Transcribe audio files into text and save the transcript to your Files.
tags: [skills, store, audio, transcription]
audience: user
surfaces: [app, website, internal-knowledge]
---

## What it does

Audio Transcription converts audio files into text using OpenAI's transcription
API. Point sideBar at any audio file in your library and it will produce a
transcript saved as a markdown file in your Files, ready to read, search, and
reference in any future conversation.

Large files are automatically split into chunks and processed in sequence,
so there is no file size you need to worry about before starting.

## Actions

| Action | Description |
| --- | --- |
| Transcribe audio | Transcribes an audio file and saves the result as a markdown file in your Files |

## When sideBar uses it

When you ask sideBar to transcribe an audio file. Common triggers:

- "Transcribe this recording"
- "Turn this audio file into text"
- "Transcribe the meeting I recorded"

## Requirements

- **Tier:** Store (install from the Skills Store)
- **API key:** OpenAI — required regardless of which AI provider you use for
  your main sideBar account. See your [OpenAI API dashboard](https://platform.openai.com/api-keys)
  to get a key.

## Supported formats

MP3, M4A, MP4, WAV, AAC, FLAC, OGG, and any other format supported by ffmpeg.

## How to install

1. Open the Skills Store and find Audio Transcription.
2. Tap **Install** and enter your OpenAI API key when prompted.
3. The skill is ready immediately.

## What you get

Transcripts are saved as markdown files in a **Transcripts** folder in your
Files. Each file includes the original filename, transcription model used,
file size, and a timestamp so you can find and identify them easily.

## Examples

> "Transcribe the voice memo I uploaded."

> "Turn my interview recording into text."

> "Transcribe this file and summarise the key points."
