---
title: Skills Store
summary: How to browse, install, and manage Store skills from the Skills Store.
tags: [manual, skills, store]
audience: user
surfaces: [app, website, internal-knowledge]
---

{/* TODO: screenshot — skills-store.png: Skills Store browsing view with category filters visible (iPad landscape) */}
<Frame>
  <img src="/assets/screenshots/skills-store.png" alt="sideBar Skills Store" />
</Frame>

The Skills Store is where you discover and install additional capabilities for
sideBar. It's a dedicated section of the app — find it in the navigation
alongside Chat, Notes, Tasks, Websites, and Files.

See [Skills](/manual/skills) for an explanation of what skills are and how
they work.

## Browsing the Store

Skills are organised by category — Audio, Media, Web, Developer, and more.
Use the category filter chips at the top to narrow the list, or search by
name to find something specific. Tap any skill card to see its full
description, requirements, and version details.

## Installing a Store Skill

{/* TODO: Update install flow when OAuth external connections ships (docs/plans/2026-03-07-external-connections-oauth2-implementation-plan.md).
    Some skills will require connecting a service account via OAuth instead of entering an API key.
    Install button states will vary: "Install", "Connect Google to install", "Reconnect". */}

1. Tap a skill to open its detail view.
2. Review the description and requirements.
3. If the skill needs an API key from an external service, enter it when
   prompted.
4. Tap **Install**. The skill is available to sideBar immediately.

Once installed, sideBar will use the skill automatically when it's relevant —
you don't need to invoke it by name.

## Managing Installed Skills

After installation, your Store skills are managed from
[Settings](/manual/settings) → **Skills**, not from the Store itself. From
there you can:

- **Enable or disable** the skill with a toggle
- **Update the API key** if your credentials change
- **Uninstall** the skill — this removes it and deletes its credentials from
  your account

Disabling a skill keeps it installed but stops sideBar from using it. You can
re-enable it at any time without reinstalling.
