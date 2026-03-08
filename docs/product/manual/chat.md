---
title: Chat
summary: How to start conversations, send messages, attach files, and understand what sideBar is doing.
tags: [manual, chat, assistant]
audience: user
surfaces: [app, website, internal-knowledge]
---

Chat is your main interface with sideBar. You can ask questions, work
through problems, or give instructions — and sideBar can use Skills to
act on your behalf.

## Starting and Managing Conversations

Your conversations are listed with auto-generated titles and a message count so
you can tell them apart at a glance. Tap any conversation to open it.

To start fresh, tap **New** and you're in. Old conversations can be archived
when you're done with them but don't want to delete them — they stay
searchable and readable even after archiving.

## Sending Messages

Type your message and tap send. Replies stream in as they're generated, so you
see words appear progressively rather than waiting for the whole response. A
**Thinking...** placeholder appears first while sideBar processes your
message.

You can attach files to any message. Attachments move through three states
before the message is ready to send:

- **Uploading** — the file is transferring; you can cancel at this stage
- **Queued** — the upload finished and the file is being prepared
- **Ready** — the attachment is processed and the message can be sent

If an attachment fails, you can retry it or delete it and try a different file.

To copy any message, tap it once — the content goes to your clipboard. The
clipboard clears automatically after 30 seconds, so copied text doesn't linger
longer than you'd want.

## Skills in Action

When sideBar uses a Skill to answer your message, a tool call appears in
or below the response. Each tool shows:

- Its **name** (e.g. web search, notes lookup)
- Its **status**: pending, running, success, or error
- A live **progress banner** with real-time text like "searching..." or
  "processing..." while it's active

Multiple tools can run within a single response, so sideBar can do
several things at once to answer your question.

## Context sideBar Receives

sideBar automatically receives a few pieces of context to make responses
more useful:

- Your **current location** (if you've allowed location access)
- **Current weather** at your location
- Your **timezone**

You don't need to state these things — they're included with every message.

## Offline

Your existing conversations are cached and fully readable without a connection.
You can't send new messages until you're back online, but nothing is lost while
you're offline.
