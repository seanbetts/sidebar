---
title: Skills
summary: How skills extend what sideBar can do, and how to find, install, and manage them.
tags: [manual, skills]
audience: user
surfaces: [app, website, internal-knowledge]
---

{/* TODO: screenshot — skills.png: Skills settings showing Standard + Store sections (iPad landscape) */}
<Frame>
  <img src="/assets/screenshots/skills.png" alt="sideBar skills settings" />
</Frame>

## What Skills Are

Skills are modular capabilities that extend what sideBar can do. Think of
them as plug-ins: each skill gives sideBar access to a specific ability or
external service, and sideBar selects and uses relevant skills
automatically as you need it. You don't need to invoke them by name or switch
modes. When a skill is running, you'll see the tool activity appear inline in
the [conversation](/manual/chat#skills-in-action) so you can follow along in
real time.

## Skill Tiers

Skills fall into three tiers:

- **Required** — core capabilities that are always active. These cannot be
  disabled because sideBar depends on them to function.
- **Standard** — optional skills that come installed and enabled by default.
  You can turn any of them off if you don't want sideBar using them.
- **Store** — additional skills you choose to install. Some are ready to use
  immediately; others require an API key from an external service, which you
  provide during installation.

## Skill States

Standard skills have a toggle: **enabled** means sideBar can use the skill,
**disabled** means it's installed but inactive until you turn it back on.

Store skills can also show as **unavailable** — this means the skill is
installed but can't run right now, either because a required API key is missing
or the skill requires a plan upgrade. sideBar will tell you what's needed.

Skills marked **Beta** are early access. They work, but their behaviour may
change in a future update.

## Finding and Managing Skills

Go to **Settings → Skills** to see everything in one place. Standard skills
appear in a list with a toggle next to each one — flip the toggle to enable or
disable that skill. Store skills are organized by category below the Standard
list; tap any category to browse what's available, then tap a skill to read its
description, see its requirements, and install it.

## Installing a Store Skill

1. Open **Settings → Skills** and scroll to the Store section.
2. Browse by category and tap a skill to view its details and requirements.
3. If the skill needs an API key, enter it in the field provided.
4. Tap **Install** to confirm. The skill becomes available to sideBar
   immediately.

## Uninstalling and Configuring Store Skills

Tap any installed Store skill to open its detail screen. From there you can
update its API key or tap **Uninstall** to remove it entirely. Uninstalling
deletes the skill's credentials from your account.

For Standard skills, disabling the toggle is enough — the skill stays installed
but sideBar won't use it until you turn it back on.
