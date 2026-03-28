---
title: Troubleshooting
summary: Solutions to common issues with chat, file ingestion, sync, and skills.
tags: [manual, troubleshooting, support]
audience: user
surfaces: [app, website, internal-knowledge]
---

## Chat isn't working

**"Session expired. Please sign in again."**
Your sideBar session has expired. Sign out from **Settings → Profile** and
sign back in.

**Provider API error or unexpected error**
Your API key may be incorrect, expired, or have been revoked, or your provider
account may have run out of credits. Check your key in **Settings → sideBar**
and confirm your billing status in your provider's dashboard. See
[API Keys](/manual/api-keys) for links to each provider.

**"Network connection failed. Please check your internet."**
sideBar cannot reach the server. Check your internet connection and try again.

**"Server error. Please try again soon."**
A temporary server error. Wait a moment and try again.

**"Server took too long to respond. Please try again."**
The request timed out. This can happen with very large attachments. Try again,
or reduce the amount of content attached to your message.

**Failed response with a retry icon**
The error was temporary. Tap the retry icon beside the error pill to append a
fresh assistant attempt while keeping the failed bubble visible.

**"Attachment and context are too large for one message."**
You have too many items open or attached. Close any open notes, websites, or
files you are not using, or remove some attachments, and try again.

**Failed response without a retry icon**
If the failed bubble is not the latest eligible one, retry is no longer shown
there. If the latest failed bubble also has no retry icon, the request needs a
change in input or settings rather than another identical retry. Reduce
attachments, shorten the request, fix provider credentials, or switch settings
before sending again.

**Responses feel slow or cut off**
This can happen when your conversation is very long. Start a new conversation
from the compose button in Chat. Your memories carry forward automatically.

## A file won't ingest

**Stuck on "processing"**
Wait a few minutes — large files take longer. If the card still shows
processing after several minutes, tap **Retry**.

**Shows an error**
The file may be in an unsupported format, corrupt, or too large. Check the
supported formats in [Files](/manual/files). If the format is supported, try
re-exporting or re-saving the file and uploading again. Tap **Retry** to
attempt again without re-uploading.

**PDF content is missing or incomplete**
Some PDFs are scanned images with no embedded text. sideBar can index text
content but cannot read image-only PDFs.

## Sync isn't working

**Changes aren't appearing on another device**
Check that both devices have an internet connection. Pull to refresh on the
relevant section. If changes still aren't showing, go to **Settings → User**
and check for queued changes in the Sync status panel.

**"Pending changes" in Settings**
You made changes while offline. They will sync automatically when your
connection returns. No action needed.

## A skill isn't working

**Skill isn't running when expected**
Check that the skill is enabled in **Settings → Skills**. If it is enabled,
make sure the skill's requirements are met — some Store skills need an API key
before they will work.

**Skill error shown in chat**
The skill ran but hit an error. Tap the skill pill in the conversation to see
the full error detail. Common causes are a missing or invalid API key, a
network failure, or an unsupported input. Check the skill's requirements in
the [Skills docs](/skills/store/).

**Store skill shows as "unavailable"**
The skill is installed but is missing a required API key or credential. Tap the
skill in **Settings → Skills** to add the missing key.

## Sign-in problems

**Verification email didn't arrive**
Check your spam or junk folder. If it's not there, wait a minute and try
signing in again to trigger a new verification email.

**Forgotten password**
Tap **Forgot password** on the sign-in screen and follow the reset link sent
to your email.

## Still stuck?

Tell sideBar in Chat: "I'm having a problem with X". sideBar will log a
support ticket and send you a tracking link. You can also email
[support@trysidebar.ai](mailto:support@trysidebar.ai). See
[Getting Help](/manual/getting-help) for more.
