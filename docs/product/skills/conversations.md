---
title: Conversations
summary: Search and rename your saved conversations through Chat.
tags: [skills, conversations]
audience: user
surfaces: [app, website, internal-knowledge]
skill_id: conversations
---

## What it does

The Conversations skill helps sideBar find past chats and rename them when
you ask. It is designed for explicit conversation-management requests, so
sideBar does not rename chats on its own. It can rename the current chat or
another saved chat if your request makes the target clear. If more than one
conversation matches what you asked for, sideBar asks a follow-up instead of
guessing.

## Actions

| Action | Description |
| --- | --- |
| Search conversations | Finds saved conversations by title or recent visible context |
| Rename conversation | Renames a specific conversation when you explicitly ask |

## When sideBar uses it

When your request is about finding or renaming a chat. Common triggers:

- Asking sideBar to rename the current conversation
- Looking for an older conversation by title
- Looking for a conversation by what it was about
- Renaming another saved conversation by title or context

## Requirements

- **Tier:** Standard (included, no installation needed)
- **API key:** None required

## How to enable

The Conversations skill is enabled by default. To toggle it, go to **Settings → Skills**.

## Examples

> "Rename this chat to Lisbon itinerary."

> "Rename my conversation about the Q2 pricing model to Revenue model review."

> "Find the chat where we planned the Barcelona trip."

> "Rename the chat about launch copy to Homepage launch copy."

If sideBar finds multiple likely matches, it asks which conversation you mean
before renaming anything.
