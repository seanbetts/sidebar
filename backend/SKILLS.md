# sideBar Skills Catalog

**Last Updated:** 2026-02-22 16:43:41
**Total Skills:** 16

This file is auto-generated from skill frontmatter. Do not edit manually.

---

## Active Skills

### Filesystem

#### [files](./skills/files/SKILL.md) `[reads, writes]`
Filesystem operations backed by ingestion - list, read, write, rename, pin, delete, and search files. Use for file management tasks in storage.

### Notes

#### [notes](./skills/notes/SKILL.md) `[reads, writes]`
Notes operations backed by the database - create, update, read, list, rename, move, pin, archive, delete notes and folders, plus scratchpad management.

### Web

#### [subdomain-discover](./skills/subdomain-discover/SKILL.md)
Discover subdomains using DNS bruteforce, Certificate Transparency logs, and sitemap parsing. Use when you need to map a brand's digital footprint, perform security reconnaissance, or prepare for crawler policy analysis.

#### [web-crawler-policy](./skills/web-crawler-policy/SKILL.md)
Analyze robots.txt and llms.txt policies to understand which crawlers can access content. Use when auditing crawler policies, analyzing AI content accessibility, or generating marketing intelligence on brand representation in LLMs.

#### [web-save](./skills/web-save/SKILL.md) `[reads, writes, network, external_apis]`
Database-backed website operations - add, read, list, rename, pin, archive, delete, and export websites.

### Media

#### [audio-transcribe](./skills/audio-transcribe/SKILL.md)
Transcribe audio files to text using OpenAI's Whisper API with automatic chunking for large files. Use when you need to convert meeting recordings, podcasts, interviews, or any audio content to text.

#### [youtube-download](./skills/youtube-download/SKILL.md)
Download YouTube videos (MP4) or audio (MP3) using yt-dlp with automatic quality selection and format conversion. Use when you need to download videos for offline viewing, extract audio, or archive YouTube content in the files workspace.

#### [youtube-transcribe](./skills/youtube-transcribe/SKILL.md)
Transcribe YouTube videos to text by downloading audio and using OpenAI's Whisper API. Use when you need transcripts stored in the files workspace.

### Development

#### [skill-creator](./skills/skill-creator/SKILL.md)
Guide for creating effective skills. This skill should be used when users want to create a new skill (or update an existing skill) that extends Claude's capabilities with specialized knowledge, workflows, or tool integrations.

### Other

#### [assistant-identity](./skills/assistant-identity/SKILL.md) `[reads, writes]`
View, update, or reset assistant identity fields (name, tone, values, boundaries) stored in user settings.

#### [assistant-soul](./skills/assistant-soul/SKILL.md) `[reads, writes]`
View, update, or reset assistant soul fields (purpose, operating_principles, adaptation_policy, success_signals) stored in user settings.

#### [product-feedback](./skills/product-feedback/SKILL.md) `[writes, network, external_apis]`
Submit bug reports and feature requests to the product team by creating GitHub issues. Use when a user asks to report/file/log a bug, report that something is broken, submit product feedback, or request a new feature.

#### [prompt-preview](./skills/prompt-preview/SKILL.md)
Generate the current system prompt output with injected variables for preview or debugging.

#### [settings-other-preferences](./skills/settings-other-preferences/SKILL.md) `[writes]`
Update device-local Other settings preferences (temperature units and biometric unlock preference) through realtime preference events. Use when the assistant needs to change settings in the Other section.

#### [settings-profile-user](./skills/settings-profile-user/SKILL.md) `[reads, writes]`
Read and update user-managed Profile and User settings fields (name, job title, employer, date of birth, gender, pronouns, location, communication style, working relationship, and profile image). Use when the assistant needs to inspect or modify these settings.

#### [tasks](./skills/tasks/SKILL.md) `[reads, writes]`
Create, complete, defer, and organize tasks and projects.
