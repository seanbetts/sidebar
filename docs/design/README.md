---
title: Design System Overview
description: The sideBar design system — foundations, components, patterns, and conventions for iOS, macOS, and web.
---

The sideBar design system is the source of truth for UI decisions across iOS, macOS, and web. It documents the target state — how things should be built — not the current state of the codebase. Current-state gaps are tracked in [Implementation Gaps](./implementation-gaps).

## How this is organised

**Overview** — Core principles, voice and content rules, system inheritance policy, and working tools (feature checklist, component template, implementation gaps).

**Platform Strategy** — Conventions specific to iPhone, iPad, Mac, web, and widgets.

**Foundations** — The lowest-level building blocks: colour, tokens, typography, materials, iconography, and accessibility.

**Components** — The shared component library with usage rules.

**Patterns** — Interaction and behavioural patterns: navigation, feedback, wait states, errors, authentication, onboarding, AI assistant UI, and more.

**Audits** — Current-state snapshots of the codebase. Updated as gaps are closed.

## Where to start

- [Design Principles](./principles) — what good looks like in sideBar
- [System Inheritance](./system-inheritance) — what we inherit from Apple vs. design ourselves
- [Token Model](./foundations/token-model) — spacing, sizing, radius, colour tokens, and motion
- [Components](./components/overview) — shared component library
- [Implementation Gaps](./implementation-gaps) — known divergences between the spec and the codebase
