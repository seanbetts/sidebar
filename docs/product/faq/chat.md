---
title: Chat
summary: Common questions about chatting with sideBar, context, memory, skills, and conversations.
tags: [faq, chat]
audience: user
surfaces: [app, website, internal-knowledge]
---

## What does sideBar know about me when I chat?

Quite a lot, automatically. Every conversation includes the current date, time,
and your timezone, your location and weather (if you've granted permission),
your device, and your profile details. It also includes a snapshot of your
tasks, any content you have open (a note, website, or file), and recent
activity across the app.

See [Chat](/manual/chat) for the full breakdown of what's included.

## Does sideBar remember previous conversations?

Not directly. Each conversation starts fresh, but sideBar builds up
[Memories](/manual/settings#memories) over time: persistent notes it creates
automatically as it learns about you, your preferences, and how you work. These
are included in every conversation, so sideBar gets better at knowing you even
without remembering specific past chats.

## What are memories and how do they work?

Memories are reference documents sideBar draws on during every conversation.
sideBar creates them automatically as it learns more about you. You can also
add, edit, or search them manually in Settings. You don't need to mention them;
sideBar reads relevant ones automatically.

## Can I attach files to a chat message?

Yes. Tap the attachment button in the chat input to attach a note, file,
website, or image. Attachments go through three stages (uploading, queued, then
ready) before you can send.

## Can sideBar take actions, not just answer questions?

Yes. Through skills, sideBar can do things as well as say things: search the
web, transcribe audio or video, send emails, create calendar events, and more.
Skills run automatically during a conversation when they are relevant. You can
see a full list of what is available in the [Skills Store](/manual/skills-store).

## How do skills work in chat?

When sideBar uses a skill during a conversation, you'll see it displayed inline
as a pill showing what it's doing. Once complete, it shows whether it succeeded
or hit an error. You don't need to invoke skills by name; sideBar picks the
right ones automatically based on what you're asking.

## How do I start a new conversation?

Tap the compose button in the Chat view. Previous conversations are saved and
you can swipe to delete ones you no longer need.

## Which AI model does sideBar use?

It depends on your chosen provider. sideBar uses a recent, capable model from
whichever provider you have configured: a Claude model for Anthropic, a GPT
model for OpenAI, and a Gemini model for Google. The specific version may
update over time as newer releases become available.

## Does sideBar use my conversations to train AI models?

No. sideBar does not train on your conversations. When you send a message, it
is processed by your chosen AI provider under your own API account, subject to
that provider's terms. sideBar does not store or use your conversation content
for model training. See our [Privacy Policy](https://trysidebar.ai/privacy) for
full details.

## Is there a message limit?

sideBar does not impose its own message limits. Your usage is subject to the
rate limits of your chosen AI provider, which vary by plan and account tier. If
you hit a rate limit, you will see an error in the chat. Switching providers or
upgrading your provider plan resolves this.

## Why did sideBar get something wrong?

sideBar works from the context it has available. If something is missing or
unclear, its response may be off. If a skill wasn't enabled, a piece of content
wasn't open, or your profile is incomplete, that can affect the quality of the
response. It's also worth checking which AI provider you're using, as
capability varies.
