---
title: System Prompt Preview
summary: See exactly what sideBar is sending to your AI provider, including the full system prompt and context window usage.
tags: [skills, prompt-preview, debugging]
audience: user
surfaces: [app, website, internal-knowledge]
skill_id: prompt-preview
---

## What it does

System Prompt Preview shows you the complete system prompt that sideBar sends to your
AI provider at the start of a conversation. This includes everything injected
automatically: your profile, memories, open content, skill definitions, and
any other context sideBar has assembled. It also shows a breakdown of how much
of your provider's context window is being used and by what.

It is a transparency and debugging tool. If sideBar is behaving unexpectedly,
a system prompt preview can help you understand what it knows and what instructions it
is working from.

## Actions

| Action | Description |
| --- | --- |
| Generate system prompt preview | Assembles and displays the full system prompt for the current conversation, with a section-by-section breakdown and context window usage report |

## When sideBar uses it

Only when you ask for it explicitly:

- "Show me your system prompt"
- "What instructions are you running under?"
- "What context are you working with right now?"
- "Preview the prompt"

## Requirements

- **Tier:** Standard (included, no installation needed)
- **API key:** None required

## How to enable

System Prompt Preview is enabled by default. To toggle it, go to **Settings → Skills**.

## Opening the preview

When the preview is ready, sideBar shows a button in the conversation to open
it. The skills pill confirms that the skill ran, but the preview itself opens
from the message button.

## What the preview shows

The preview includes:

- **System prompt**: the full text sent to your AI provider at the start of
  every message
- **Section breakdown**: which parts of the prompt come from where (your
  profile, memories, open content, skill definitions, and so on) with
  character counts for each
- **Context window report**: total characters used versus the limit for your
  current provider and model, and whether any content was trimmed to fit

## Examples

> "Show me your system prompt."

> "What do you know about me right now?"

> "How much of your context window are we using?"
