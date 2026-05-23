---
title: Skills
summary: Common questions about skills, Included skills, installing Store skills, API keys, and how skills work in chat.
tags: [faq, skills]
audience: user
surfaces: [app, website, internal-knowledge]
---

## What are skills?

Skills are modular capabilities that extend what sideBar can do. Each skill
gives sideBar access to a specific ability or external service: searching the
web, transcribing audio, sending email, reading calendars, and more. sideBar
selects and uses relevant skills automatically as you chat. You do not need to
invoke them by name or switch modes.

## What is the difference between Included and Store skills?

- **Included** skills come with sideBar. Some are optional and can be turned
  on or off. Core included skills are locked on because sideBar depends on them
  to function.
- **Store** skills are additional capabilities you choose to install from the
  Skills Store. Some are ready to use immediately; others require an API key
  from an external service.

## Do I need to do anything to use skills?

No, for Included skills. They work automatically. For Store skills you first
install them from the Skills Store, and some require an API key from an
external service before they will work. Once installed, sideBar uses them
without any further input from you.

## How do I know when a skill is running?

When sideBar uses a skill during a conversation, a pill appears inline showing
what it is doing. Once the skill completes, the pill updates to show whether it
succeeded or hit an error. This happens in real time so you can follow along.

## Can I turn skills off?

Yes. Go to Settings → Skills to see all your installed skills with toggles.
Disabling a skill keeps it installed but stops sideBar from using it. You can
re-enable it at any time. Locked included skills cannot be disabled.

## Do Store skills cost money?

Store skills themselves are free to install. Some skills connect to external
services (such as Gmail or Spotify) that may have their own subscription or API
costs. Any such requirements are shown on the skill's detail page before you
install it.

## Some skills need API keys. Which ones, and where do I get them?

Store skills that connect to external services need an API key from that service.
The skill's detail page tells you exactly which key is needed and where to get
it. Your key is encrypted before being stored and only the last four characters
are shown as confirmation. The full key is never displayed again.

Note that a small number of skills require an API key from a specific provider
regardless of which AI provider you use for your main sideBar account. For
example, audio and video transcription uses OpenAI Whisper and therefore needs
an OpenAI API key even if your primary provider is Anthropic or Google. The
skill's detail page will make this clear.

## What happens if I uninstall a skill?

Uninstalling removes the skill and permanently deletes any credentials
associated with it from your account. You can reinstall it later from the Skills
Store, but you will need to provide your API key again.

## What does Beta mean on a skill?

Beta skills are early access. They work, but their behaviour or interface may
change in a future update. Use them knowing that things might shift as they
mature.

## How do I manage skills I have already installed?

Installed skills are managed from Settings → Skills, not from the Skills Store
itself. From there you can enable or disable them, update their API key, or
uninstall them.
