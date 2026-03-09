---
title: Troubleshooting
summary: Solutions to common issues with chat, file ingestion, sync, and skills.
tags: [manual, troubleshooting, support]
audience: user
surfaces: [app, website, internal-knowledge]
---

## Chat isn't working

**"Invalid API key" or similar error**
Your API key may be incorrect, expired, or have been revoked. Go to
**Settings → sideBar**, re-enter your key, and save. Make sure you copy the
full key from your provider's dashboard without trailing spaces.

**"Insufficient credits" or "Billing" error**
Your provider account has run out of credits or has no payment method attached.
Log in to your provider's dashboard and top up your balance or add a payment
method. See [API Keys](/manual/api-keys) for links.

**"Rate limit exceeded"**
Your provider account has hit its usage limit. This is usually temporary — wait
a few minutes and try again. If it happens frequently, consider upgrading your
provider plan or switching providers in **Settings → sideBar**.

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
re-exporting or re-saving the file and uploading again.

**PDF content is missing or incomplete**
Some PDFs are scanned images with no embedded text. sideBar can index text
content but cannot OCR image-only PDFs.

## Sync isn't working

**Changes aren't appearing on another device**
Check that both devices have an internet connection. Pull to refresh on the
relevant section. If changes still aren't showing, go to **Settings → User**
and check for pending writes in the Sync status panel.

**"Pending changes" showing in Settings**
You made changes while offline. They will sync automatically when your
connection returns. No action needed.

## A skill isn't working

**Skill isn't running when expected**
Check that the skill is enabled in **Settings → Skills**. If it is enabled,
make sure the skill's requirements are met — some Store skills need an API key
before they will work.

**"Skill error" pill in chat**
The skill ran but hit an error. Tap the pill to see the error detail. Common
causes are a missing or invalid API key, a network failure, or an unsupported
input. Check the skill's requirements in the [Skills](/skills/store/) docs.

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
