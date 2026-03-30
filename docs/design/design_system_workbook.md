---
title: Design System Workbook
description: Working brief for the internal sideBar design-system documentation and its target information architecture.
---

## Progress tracker

| # | Section | Doc(s) | Status |
|---|---|---|---|
| 1 | Principles | [principles.md](./principles) | approved |
| 2 | System inheritance | [system-inheritance.md](./system-inheritance) | approved |
| 3 | Voice and content | [voice-and-content.md](./voice-and-content) | approved |
| 4 | Platform strategy | [overview](./platform-strategy/overview), [iOS](./platform-strategy/ios-conventions), [macOS](./platform-strategy/macos-conventions), [web](./platform-strategy/web-conventions) | approved |
| 5 | Foundations: colour | [foundations/colour.md](./foundations/colour) | approved |
| 6 | Foundations: token model | [foundations/token-model.md](./foundations/token-model) | approved |
| 7 | Foundations: typography | [foundations/typography.md](./foundations/typography) | approved |
| 8 | Foundations: materials and appearance | [foundations/materials-and-appearance.md](./foundations/materials-and-appearance) | approved |
| 9 | Foundations: iconography | [foundations/iconography.md](./foundations/iconography) | approved |
| 10 | Foundations: accessibility | [foundations/accessibility.md](./foundations/accessibility) | approved |
| 11 | Components | [components/overview.md](./components/overview) | approved |
| 12 | Patterns: navigation | [patterns/navigation.md](./patterns/navigation) | approved |
| 13 | Patterns: feedback and haptics | [patterns/feedback-and-haptics.md](./patterns/feedback-and-haptics) | approved |
| 14 | Patterns: wait UX | [patterns/wait-ux.md](./patterns/wait-ux) | approved |
| 14a | Patterns: authentication | [patterns/authentication.md](./patterns/authentication) | approved |
| 15 | Patterns: onboarding | [patterns/onboarding.md](./patterns/onboarding) | partial |
| 16 | Patterns: handoffs | [patterns/handoffs.md](./patterns/handoffs) | approved |
| 17 | Patterns: AI assistant UI | [patterns/ai-assistant-ui.md](./patterns/ai-assistant-ui) | approved |
| 18 | sideBar model | [patterns/sidebar-model.md](./patterns/sidebar-model) | approved |
| 19 | Audits | [token-audit](./audits/token-audit) (approved), [current-ui-audit](./audits/current-ui-audit) (live), [patterns-audit](./audits/patterns-audit) (live), [component-inventory](./audits/component-inventory) (live), [system-framework-usage](./audits/system-framework-usage-audit) (live) | live |
| 20 | Patterns: menus and shortcuts | [patterns/menus-and-shortcuts.md](./patterns/menus-and-shortcuts) | not started |
| 23 | Audits: framework usage by app section | [audits/system-framework-usage-audit.md](./audits/system-framework-usage-audit) | not started |
| 21 | Component template | [component-template.md](./component-template) | not started |
| 22 | Feature UI checklist | [feature-ui-checklist.md](./feature-ui-checklist) | drafted |

## Supporting documents

| Document | Purpose |
|---|---|
| [implementation-gaps.md](./implementation-gaps) | Central tracker of all known divergences between design system and codebase |
| [audits/patterns-audit.md](./audits/patterns-audit) | Current-state snapshot of behavioral patterns — haptics, wait states, navigation, material usage |

---

## Document structure convention

The design system uses a strict three-tier structure. Every contributor and agent must follow this separation:

| Tier | Location | Contains | Written as |
|---|---|---|---|
| **Spec docs** | `docs/design/` (foundations, components, patterns) | Target state — how things should work when correctly implemented | Authoritative rules. No hedging, no "currently X but should be Y". |
| **Audit docs** | `docs/design/audits/` | Current state — how things actually work in the codebase today | Descriptive snapshots. Updated as gaps are closed. |
| **Implementation gaps** | `implementation-gaps.md` | The delta — specific divergences between current and target, each as a one-liner with a source link | Actionable. When a gap is resolved, remove it. |

**The key rule**: Spec docs must never contain current-state observations. If you find yourself writing "currently X" or "not yet implemented" in a spec doc, that content belongs in an audit doc or the implementation gaps list instead. Spec docs are written as if the system is already correctly built.

When adding a new gap discovered while writing a spec, add it to `implementation-gaps.md` — do not leave a note in the spec.

---

## Purpose

This workbook is the starting point for creating a practical design system for sideBar across iOS, macOS, and web.

It is not a theoretical design exercise and it is not a brand book. Its job is to help us do three things well:

- document the UI and interaction patterns that already exist
- decide what should become the standard going forward
- give the AI coding agent a clear set of rules it can reliably follow

The design system should make sideBar feel more consistent, more polished, more native, and easier to evolve.

Because this is primarily an iOS and macOS product, the system should stay close to Apple’s Human Interface Guidelines and modern Apple frameworks wherever they already provide strong answers. We should be explicit about what we inherit from the platform, what we lightly customise, and what we intentionally design ourselves.

---

## What this workbook is for

This document is a working brief for building the design system in stages.

We will use it to:

- audit the current product
- identify inconsistency, duplication, and rough edges
- define the design principles that should guide future decisions
- document foundations, components, patterns, and writing rules
- create implementation guidance the AI coding agent can turn into code and skills

The goal is not to design everything from scratch. The goal is to capture the best of what already exists, clean up what is inconsistent, and create a durable system for future work.

---

## What success looks like

The design system is successful if:

- new UI can be built faster with fewer ad hoc decisions
- sideBar feels more consistent across screens, flows, and platforms
- sideBar feels unmistakably native on Apple platforms
- the AI coding agent can build new UI from documented patterns rather than guessing
- copy, feedback, onboarding, assistant behaviours, and sideBar’s voice feel intentional rather than improvised
- voice and language feel consistent across the product, docs, support, and marketing
- the docs become the default reference point for UI decisions

---

## How we should approach this

1. **Audit before inventing**
   Start with what is already in sideBar.

2. **Native by default**
   Use Apple’s native frameworks, components, behaviours, and conventions unless there is a clear reason not to.

3. **Inherit before inventing**
   Before creating custom UI, first ask whether the platform already provides a strong pattern we can adopt.

4. **Standardise what matters most**
   Focus first on the areas that appear most often or create the most inconsistency.

5. **Design for both humans and agents**
   The docs must be easy to read, precise, and actionable.

6. **Keep one shared product language**
   The app should feel like one product, even where platform conventions differ.

7. **Treat words and character as part of the design system**
   Labels, empty states, errors, assistant framing, onboarding copy, and sideBar’s personality are part of the experience.

8. **Make the system map cleanly to code**
   Tokens, components, states, and variants should have clear implementation counterparts.

---

## How to use this workbook

Each section in this document should produce a real output, usually a markdown doc inside `docs/design/`.

For each section:

- the **AI coding agent** should review the codebase and describe what exists today
- **Sean** should answer the product, quality, and taste questions
- the final outcome should be a documented rule, pattern, or decision that can be reused

This should be treated as a working process, not a one-off exercise. Some sections will start as rough notes, then become proper design-system docs once the thinking is clear.

---

## Standard template for final design docs

Each final document in `docs/design/` should follow a consistent structure so it is easy for both humans and the AI coding agent to read, compare, and extend.

**All spec docs describe target state only.** Do not mix current-state observations into spec docs — see the document structure convention above.

Not every doc needs every subsection, but this should be the default starting shape.

```md
# Document title

## Purpose
What this doc covers and why it exists.

## Why this matters
Why this area is important to sideBar’s product quality and consistency.

## Scope
What is included and what is explicitly out of scope.

## Design rules
The actual principles, rules, or standards this doc defines.

## Platform notes
Anything specific to iPhone, iPad, Mac, or web.

## System inheritance notes
What should be inherited from Apple or platform-native behaviour versus customised.

## Content notes
Any wording, tone, or terminology guidance relevant to this area.

## Accessibility notes
Accessibility expectations and non-negotiable requirements.

## AI-agent instructions
Practical guidance the AI coding agent should follow when implementing or extending this area.

## Examples
Good examples, bad examples, edge cases, or before/after notes.

## Open questions
Anything still undecided or needing human judgement.

## Related docs
Links to other relevant design-system docs.
```

A few doc types will need lighter or heavier versions of this template, but the goal is consistency rather than rigidity.

---

## Section workflow and status tracking

Each workbook section should also have a small operational header so we can track what is ready, what is blocked, and what still needs input.

Use this structure for each major section while the workbook is in progress:

```md
- Status: not started | in progress | drafted | approved
- Owner: Sean | AI coding agent | both
- Inputs needed: docs, screenshots, code review, product decisions, etc.
- Outputs: the docs or artefacts this section should produce
- Dependencies: which other sections need to exist first
- Codebase review required: yes / no
- Human judgement required: yes / no
```

### Status definitions

- **Not started**: the section exists but has not been worked on yet
- **In progress**: inputs are being gathered or the section is actively being drafted
- **Drafted**: there is a usable first version, but it still needs review or refinement
- **Approved**: the section is good enough to treat as the current source of truth

### Ownership guidance

- **Sean**: best when the section depends mainly on product judgement, taste, priorities, or positioning
- **AI coding agent**: best when the section depends mainly on codebase inspection, inventory work, or implementation detail
- **Both**: best when the section needs technical review plus product judgement

This workflow layer should keep the workbook practical and stop it from becoming a static outline.

---

## Design docs structure

The initial proposed structure has been reviewed and rationalised. Many foundations (spacing, sizing, radius, borders, elevation, layout, motion, theming) are fully covered by `token-model.md`, `colour.md`, and `materials-and-appearance.md` and do not warrant standalone files. Individual component docs (buttons, inputs, cards, etc.) are deferred — the component inventory and overview serve the current team size. Several proposed patterns were consolidated into broader docs or deemed too thin for standalone treatment.

```text
docs/
  design/
    README.md
    design_system_workbook.md
    principles.md
    system-inheritance.md
    voice-and-content.md
    implementation-gaps.md
    platform-strategy/
      overview.md
      ios-conventions.md
      macos-conventions.md
      web-conventions.md
      widgets.md
    foundations/
      overview.md
      token-model.md        ← covers spacing, sizing, radius, borders, motion
      colour.md
      typography.md
      materials-and-appearance.md  ← covers elevation, theming
      iconography.md
      accessibility.md
    components/
      overview.md           ← inventory + rules; individual docs added on demand
    patterns/
      overview.md
      navigation.md
      feedback-and-haptics.md
      wait-ux.md
      authentication.md
      onboarding.md
      handoffs.md
      ai-assistant-ui.md
      sidebar-model.md
      menus-and-shortcuts.md  ← to build
    audits/
      token-audit.md
      current-ui-audit.md
      patterns-audit.md
      component-inventory.md
      system-framework-usage-audit.md
```

---

## Recommended process

We should work through this in two tracks at the same time:

### Track 1: Audit the current product
Identify what already exists in sideBar and how consistent it is.

### Track 2: Define the target system
Decide what the standard should be going forward.

This prevents us from inventing an idealised system that does not match the real product.

Apple’s Human Interface Guidelines and native framework behaviour should be treated as a baseline input into the target system, especially for iOS and macOS patterns we do not need to reinvent.

---


## Remaining items

### 20. Patterns: menus and shortcuts

Consolidate keyboard shortcut, menu bar, and context menu conventions that are currently scattered across `macos-conventions.md` and `web-conventions.md`. Define the complete shortcut set, menu bar structure, and context menu rules for each platform.

Output: `patterns/menus-and-shortcuts.md`

---

### 21. Component template

A template to follow when building a new component. Covers file structure, token usage, accessibility requirements, platform branching, and reduce-motion handling. Ensures new components conform to the design system from the start without requiring a separate review pass.

Output: `component-template.md`

---

### 22. Feature UI checklist

A pre-flight checklist for shipping new UI. Covers tokens used, haptics added, reduce-motion respected, accessibility labels present, platform variants tested, and implementation-gaps checked. Converts the design system's implicit requirements into an explicit pass/fail list.

Output: `feature-ui-checklist.md` (drafted)

---

### 23. Audits: framework usage by app section

Extend `system-framework-usage-audit.md` with a per-section breakdown of the native frameworks used in each area of the app. Covers Chat, Notes, Tasks, Websites, Files, and Settings — documenting the UIKit/AppKit/SwiftUI split, any bridging complexity, and prescriptive guidance for new work in each area.

Output: new section in `audits/system-framework-usage-audit.md`

---

## Notes

- The first version should optimise for usefulness, not completeness.
- It is better to document 70% of the real system clearly than 100% of an imagined one vaguely.
- Figma can come later once the underlying system is stable enough to deserve it.
- The markdown docs are the source of truth. Skills, prompts, and future design assets should consume them rather than replace them.
- The design system should sit on top of Apple's Human Interface Guidelines for iOS and macOS rather than trying to replace them.
- Where Apple gives us strong native behaviour, appearance, or accessibility support, we should usually inherit it and document that choice clearly.
