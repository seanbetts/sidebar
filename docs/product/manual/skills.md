---
title: Skills
summary: What skills are, how sideBar uses them, and the difference between Required, Standard, and Store skills.
tags: [manual, skills]
audience: user
surfaces: [app, website, internal-knowledge]
---

{/* TODO: screenshot — skills.png: Settings → Skills showing Standard skill toggles (iPad landscape) */}
<Frame>
  {/* TODO: alt text — replace with a rich, specific description of what's shown (for screen readers and AI crawlers) */}
  <img src="/assets/screenshots/skills.png" alt="sideBar skills settings" />
</Frame>

Skills are modular capabilities that extend what sideBar can do. Think of
them as plug-ins: each skill gives sideBar access to a specific ability or
external service. sideBar selects and uses relevant skills automatically as
you chat. You don't need to invoke them by name or switch modes. When a
skill is running, you'll see the skill pill appear inline in the
[conversation](/manual/chat#skills-in-action) so you can follow along in
real time.

## Skill Tiers

Skills fall into three tiers:

- **Required**: core skills that are always active. These cannot be
  disabled because sideBar depends on them to function.
- **Standard**: optional skills that come installed and enabled by default.
  You can turn any of them off if you don't want sideBar using them.
- **Store**: additional skills you choose to install from the
  [Skills Store](/manual/skills-store). Some are ready to use immediately;
  others require an API key from an external service, which you provide
  during installation.

## Skill States

Standard skills have a toggle: **enabled** means sideBar can use the skill,
**disabled** means it's installed but inactive until you turn it back on.

Store skills can also show as **unavailable**, this means the skill is
installed but can't run right now, either because a required API key is
missing or the skill requires a plan upgrade. sideBar will tell you what's
needed.

Skills marked **Beta** are early access. They work, but their behaviour may
change in a future update.

{/* TODO: Update availability states when OAuth external connections ships (docs/superpowers/plans/2026-03-07-external-connections-oauth2-implementation-plan.md).
    New states to add: ready, needs_connection, scope_upgrade_required, error.
    Some skills will show "Connect Google to install" instead of an API key field. */}

## Mixing Skills

Skills are most powerful when they work together. sideBar can chain multiple
skills in a single conversation turn without you needing to think about which
ones are involved. A few examples of what this looks like in practice:

- **Research and capture**: "Search for the latest news on X and save a
  summary as a note" uses Web Search to find results and Notes to write
  them up.
- **Plan from content**: "Read the article I saved yesterday and create
  tasks for each action item" uses Websites to pull in the page and Tasks
  to capture the actions.
- **Cross-reference**: "What tasks do I have this week, and have I saved
  anything relevant to them?" uses Tasks and Websites together to give you
  a joined-up view.
- **Capture and follow up**: "Save this URL, give me a one-paragraph
  summary, and add a task to read it properly tonight" uses Websites,
  Notes, and Tasks in one go.

The more skills you have enabled, the more sideBar can do in a single
request. If a skill you expect to be used is not running, check that it is
enabled in [Settings](/manual/settings) → **Skills**.

## Managing Skills

Go to [Settings](/manual/settings) → **Skills** to manage what's active.
Standard and Required skills appear as a list with a toggle next to each one.
Installed Store skills appear here too. You can enable, disable, update
their API key, or uninstall them from this view.

To browse and install new Store skills, go to the
[Skills Store](/manual/skills-store).
