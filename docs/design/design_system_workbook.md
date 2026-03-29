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
| 17 | Patterns: AI assistant UI | [patterns/ai-assistant-ui.md](./patterns/ai-assistant-ui) | draft |
| 18 | Agent rules | agent-rules/ | not started |
| 19 | Audits | [token-audit](./audits/token-audit) (approved), [current-ui-audit](./audits/current-ui-audit), [patterns-audit](./audits/patterns-audit), [component-inventory](./audits/component-inventory), [system-framework-usage](./audits/system-framework-usage-audit) (drafted) | partial |

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

## Proposed design docs structure

```text
docs/
  design/
    README.md
    design-system-workbook.md
    principles.md
    system-inheritance.md
    voice-and-content.md
    platform-strategy/
      overview.md
      ios-conventions.md
      macos-conventions.md
      web-conventions.md
    foundations/
      overview.md
      token-model.md
      colour.md
      typography.md
      spacing.md
      sizing.md
      radius.md
      borders.md
      elevation.md
      layout.md
      materials-and-appearance.md
      motion.md
      iconography.md
      theming.md
      accessibility.md
    components/
      overview.md
      buttons.md
      inputs.md
      search.md
      cards.md
      lists.md
      navigation.md
      modals.md
      feedback.md
      loading.md
      empty-states.md
    patterns/
      navigation.md
      sidebars-toolbars-and-split-views.md
      windows-and-panels.md
      menus-commands-and-shortcuts.md
      search-and-filtering.md
      forms.md
      editing.md
      wait-ux.md
      onboarding.md
      handoffs.md
      settings.md
      ai-assistant-ui.md
      feedback-and-haptics.md
      writing-and-localisation.md
      loading-errors-success.md
    agent-rules/
      ui-implementation-rules.md
      component-template.md
      feature-ui-checklist.md
      prompt-templates.md
      design-to-code-parity.md
    audits/
      current-ui-audit.md
      inconsistency-backlog.md
      token-audit.md
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

# 1. Design principles

## Why this section matters

This is where we define what “good” looks like in sideBar.

If we do this well, the rest of the design system becomes easier. Principles should help us make decisions when there is no obvious right answer, especially when we are balancing clarity, power, native behaviour, speed, and product character.

This section should not read like brand language. It should read like a set of practical decision rules.

## What we need to produce

A short `principles.md` document that defines:

- the core design principles for sideBar
- the trade-offs we are willing to make
- where we want to feel most native
- where we want sideBar to feel distinctive
- the role of sideBar’s voice, character, and personality in the product experience

## Questions for Sean

- What should sideBar feel like in a few words?
- What should users feel when using it?
- What matters more: speed, calmness, delight, density, flexibility, or power?
- Should sideBar feel minimal, warm, technical, premium, playful, or something else?
- Where should we prefer clarity over cleverness?
- Where should we prefer native conventions over custom UI?
- What should make sideBar unmistakably itself?
- What are the signature qualities or moments that give it identity?
- What kind of character should sideBar project across the whole product?
- How strong or restrained should that character be?
- Where should sideBar feel warm, witty, opinionated, or playful, and where should it stay neutral?
- Where do we consciously want to inherit Apple’s design language rather than create our own?

## Questions for the AI coding agent

- What product behaviours are already consistent across sideBar?
- What visual or interaction patterns appear to reflect an implicit product philosophy?
- Where does the current UI feel fragmented or inconsistent?
- Which parts already feel distinctive in a good way?
- Which custom patterns currently fight the platform?
- Where are we reinventing things Apple already gives us?
- Where does the current writing or behaviour already imply a distinctive sideBar personality?

## Good output for this section

A principles doc with 4 to 8 principles, each written as:

- a short principle statement
- why it matters
- what it means in practice
- examples of the kinds of decisions it should influence

It should also include:

- a short section on signature product character
- a clear statement of where we are native by default
- a first-pass definition of sideBar’s voice and behavioural character

---

# 2. System inheritance

## Why this section matters

A big part of making sideBar feel polished and modern is knowing what not to design from scratch.

Because sideBar is primarily iOS and macOS, a large part of the design system should come from Apple’s native controls, materials, typography, accessibility behaviours, and interaction patterns. This section defines where we intentionally inherit from the platform so the system stays lean, native, and easier to maintain.

This section should stop us from customising things just because we can.

## What we need to produce

A `system-inheritance.md` document that clearly separates:

- what we inherit from Apple by default
- what we lightly customise
- what we only replace in exceptional cases

## Areas to cover

- native controls and containers
- system colours and semantic colours
- Dynamic Type and text styles
- SF Symbols
- system materials and appearance
- native sheets, popovers, alerts, menus, and toolbars
- platform-standard interactions and animations
- accessibility behaviours inherited from the system

## Questions for Sean

- Where do we want to rely on Apple defaults with minimal customisation?
- Where do we want sideBar to feel unmistakably Apple-native?
- Where do we need to add our own visual language on top of the system?
- Which customisations are worth the maintenance cost, and which are not?

## Questions for the AI coding agent

- Which system frameworks and native components are already heavily used?
- Which parts of the UI are mostly inherited from SwiftUI, UIKit, or AppKit?
- Where have we wrapped or restyled native components?
- Where are we using custom UI where a native component might be better?
- Which Apple behaviours are we already getting for free and should document rather than recreate?

## Good output for this section

A practical inheritance guide that answers questions like:

- Should this be a native component, a thin wrapper, or a custom component?
- Should this use system colour, a semantic token, or a custom brand value?
- Are we solving a real product need, or recreating something the platform already solves?

---

# 3. Platform strategy

## Why this section matters

The product should feel like one product across iOS, macOS, and web, but it should not behave identically everywhere.

This section defines where consistency matters most and where platform-specific behaviour should win. It is especially important for making sure the Mac app feels like a real Mac app, the iOS app feels natural on iPhone and iPad, and the web app follows the same overall product logic without awkwardly pretending to be native Apple software.

## What we need to produce

A small set of platform docs that explain:

- what should stay shared across platforms
- what should intentionally differ
- which platform conventions are non-negotiable
- how touch, pointer, keyboard, windowing, and layout expectations should shape the UI

## Questions for Sean

- Which parts of the experience must feel identical across platforms?
- Where should platform-native conventions win?
- Should sideBar feel more Apple-native first, or fully cross-platform first?
- Are there any platform-specific features that should be embraced rather than abstracted away?
- What should a user always recognise no matter which platform they are on?
- Which parts of sideBar should behave differently on iPhone, iPad, Mac, and web?

## Questions for the AI coding agent

- Which components or screens currently differ between iOS, macOS, and web?
- Where are there already platform-specific implementations?
- Which patterns are shared cleanly and which are drifting?
- Where are we forcing sameness when native divergence would be better?
- Where are we missing desktop-specific or mobile-specific conventions?

## Good output for this section

Platform docs covering:

- `platform-strategy/overview.md`
- `platform-strategy/ios-conventions.md`
- `platform-strategy/macos-conventions.md`
- `platform-strategy/web-conventions.md`

These should define:

- shared product rules
- allowed differences by platform
- adaptive layout expectations
- input model differences such as touch, pointer, and keyboard
- rules for when to prefer native components
- platform-specific conventions that must be preserved

---

# 4. Foundations

## Why this section matters

Foundations are the raw ingredients of the system.

They define the visual language that sits underneath every screen and component: colour, typography, spacing, sizing, materials, motion, and layout. If this layer is messy, everything built on top of it becomes harder to standardise.

Because this is primarily an Apple-platform product, this section should be very clear about which foundational choices come from Apple’s own system language and which are ours. In many places the right answer will be to inherit system typography, semantic colours, materials, spacing behaviour, and adaptive appearance rather than inventing our own alternatives.

## What we need to produce

A set of foundation docs that:

- describe the core visual building blocks of sideBar
- explain where they come from
- define where we use platform semantics versus custom values
- identify which values should become reusable tokens

This section should result in a foundation layer that feels coherent, restrained, and easy for the AI coding agent to use consistently.

## Areas to cover

- colour
- typography
- spacing
- sizing
- corner radius
- borders and dividers
- shadows and elevation
- layout/grid
- materials and appearance
- iconography
- motion
- theming

## Questions for Sean

- What level of visual expressiveness do we want?
- Should the UI aim for restraint or stronger character?
- How important is dark mode parity?
- How much motion is appropriate?
- Do we want sideBar to feel visually quiet, rich, or somewhere in between?
- Which visual qualities should come directly from Apple’s system materials and typography?
- Where do we want sideBar to have a more distinctive point of view?

## Questions for the AI coding agent

- What colours, fonts, spacing values, radii, shadows, and sizing patterns already exist in code?
- Are there hard-coded values that should become tokens?
- Are there competing token systems already in use?
- Where is visual drift most obvious?
- Which foundations are already centralised and which are scattered?
- Where are we already using system colours, materials, and typography correctly?
- Where have we introduced visual rules that do not seem intentional or reusable?

## Good output for this section

A foundations layer that answers questions like:

- Which visual values are system-derived and which are product-defined?
- Which values are core enough to standardise across the whole app?
- Which visual differences are intentional and which are accidental?
- How should the agent choose sensible defaults when building something new?

The final output should be a set of docs in `foundations/` plus a first-pass inventory of reusable values that can later feed the token model.

---

# 5. Token model

## Why this section matters

The token model is what turns visual consistency into something enforceable.

Without it, the design system stays descriptive and the codebase keeps drifting. With it, the AI coding agent has a shared vocabulary it can actually use. This is the bridge between design thinking and implementation.

For sideBar, the token model also needs to handle a subtle but important distinction: some values should map directly to Apple’s semantic system values, while others should be defined by us. That means this section is not just about naming tokens. It is about deciding what should be abstracted and what should remain platform-native.

## What we need to produce

A `token-model.md` document that defines:

- the layers of the token system
- how tokens should be named
- what kinds of decisions belong in tokens
- how tokens should map to code and, later, to Figma
- where native platform semantics should be used instead of custom tokens

## Structure to define

- global tokens: raw values
- alias tokens: semantic values
- component tokens: optional, where needed
- theme mappings for light/dark and any future brand layers
- mappings to Apple semantic values where appropriate

## Questions for Sean

- How opinionated do we want token naming to be?
- Do we want semantic names that describe purpose rather than appearance?
- How much flexibility do we want for future theming?
- Which visual decisions should remain platform-derived rather than tokenised?
- How much abstraction is helpful versus over-engineered for a solo-built product?

## Questions for the AI coding agent

- What token-like abstractions already exist in SwiftUI and web code?
- Which hard-coded values should become global tokens?
- Which repeated usages suggest alias tokens?
- Are there component-specific values that should stay local?
- Which tokens can map directly to Apple semantic colours, text styles, or materials?
- Where are existing names unclear, inconsistent, or too tied to implementation detail?

## Good output for this section

A token model that makes these decisions easy:

- Should this be a global token, an alias token, or a component-level value?
- Should this map to a platform semantic value rather than a custom token?
- Is this a reusable design decision or just a local implementation detail?
- How should the same concept be represented across SwiftUI, web, and future design tooling?

The final output should be practical rather than overcomplicated. The goal is a token model the agent will actually use, not a perfectly academic abstraction.

---

# 6. Accessibility

## Goal
Ensure accessibility is built into the system, not added later.

## Questions for Sean
- What accessibility standards do we want to hold ourselves to?
- Are there any user groups or accessibility needs that should be prioritised?
- How much should we optimise for keyboard-first usage on macOS and web?
- Are there any accessibility principles that should be treated as non-negotiable?
- Which platform accessibility features do we want to adopt as defaults wherever possible?

## Questions for the AI coding agent
- What accessibility support already exists in code?
- Where are there likely issues with contrast, sizing, labels, focus, or motion?
- Which components need accessibility guidance documented?
- How does the web app behave with zoom, reflow, focus order, and semantic markup?
- Are there gaps in screen reader annotations or meaningful text?
- Where are we failing to inherit accessible platform behaviour because of custom UI?

## Output
An `accessibility.md` doc covering:
- contrast
- minimum target sizes
- Dynamic Type / text scaling
- keyboard and focus behaviour
- reduced motion
- screen reader guidance
- meaningful text
- semantic structure
- alt text / captions where relevant
- web zoom and reflow rules
- colour usage rules
- rules for inheriting built-in accessibility support from native components

---

# 7. Voice, character, and content design

## Why this section matters

A polished product is not just made of visuals and components. It is also made of words and personality.

Labels, empty states, errors, confirmations, helper text, onboarding copy, and assistant framing all shape how clear, trustworthy, and premium sideBar feels. If the wording is inconsistent or vague, the UI will feel less finished even if the visuals are strong.

For sideBar, this matters even more because it is an AI assistant with an explicit identity and soul. That means voice is not just a copywriting concern. It is part of the product itself. This section should define both the practical writing rules and the underlying character that makes sideBar feel recognisable across the app, docs, support, and marketing.

## What we need to produce

A `voice-and-content.md` document that defines:

- sideBar’s voice and character
- the tone and writing style of sideBar
- how common UI messages should be written
- how AI-related copy should be framed
- which words and patterns should be preferred or avoided
- how writing should support accessibility and localisation
- how that voice should extend into docs, marketing, and support content

This section should make copy decisions more systematic and reduce ad hoc wording across sideBar.

## Areas to cover

- voice and character
- tone of voice
- buttons and CTA labels
- field labels
- helper text
- placeholders
- empty states
- error messages
- confirmation messages
- success messages
- notifications
- AI assistant UI framing
- writing and localisation

## Questions for Sean

- What tone should sideBar use?
- What should sideBar’s character feel like in a few words?
- Should the UI feel concise, supportive, neutral, expert, or conversational?
- How should AI-related UI be framed so it feels trustworthy and clear?
- What language should we avoid?
- Where should the UI be warm versus purely functional?
- How literal or plainspoken should the UI be?
- Should sideBar sound the same everywhere, or slightly different in assistant-led moments?
- How much personality is appropriate in the product, docs, support, and marketing?

## Questions for the AI coding agent

- What patterns already exist in buttons, labels, placeholders, empty states, errors, and system messages?
- Where is wording inconsistent?
- Are there repeated terms being used differently?
- Are there unclear labels or overly technical phrases in the UI today?
- Which strings are likely to create future localisation issues?
- Where does sideBar currently sound more human, more technical, or more abrupt than intended?
- Where does the current writing imply a distinctive character that could be standardised?

## Good output for this section

A voice and content guide that answers questions like:

- What should sideBar’s voice feel like?
- How much personality should show up in different contexts?
- What should a good button label sound like?
- How should we write empty states so they are useful without being noisy?
- How do we explain AI actions clearly without sounding defensive or vague?
- Which terms should be standard across the whole of sideBar?
- How should the assistant phrase suggestions, uncertainty, success, and failure?
- How should that same voice extend into docs, support, and marketing?

The final output should be practical enough that the AI coding agent can use it when generating UI copy, and clear enough that it can guide broader sideBar writing beyond the product UI.

---

# 8. Component library

## Why this section matters

The component library is where the design system becomes reusable.

It is the layer that turns principles, foundations, and writing rules into actual building blocks sideBar can use repeatedly. If this section is done well, new UI gets easier to build, existing UI becomes easier to clean up, and the AI coding agent has a clear set of parts to compose rather than invent.

For sideBar, the component library should also make a clear distinction between three things:

- native Apple components we use as-is
- thin wrappers around native components
- truly custom components that solve a product-specific need

That distinction matters because it will keep the system simpler, more native, and easier to maintain.

## What we need to produce

A documented component library that:

- inventories the components we already have
- identifies which ones should become standard
- clarifies which are native, wrapped, or custom
- defines usage, variants, states, and content rules
- gives the AI coding agent a reusable component vocabulary

## Priority components

- buttons
- text inputs
- search fields
- text areas / editors
- toggles / checkboxes / pickers
- cards
- list rows
- navigation elements
- tabs / segmented controls
- sheets / modals / popovers
- alerts / banners / toasts
- loading states
- empty states

## Questions for Sean

- Which components matter most to standardise first?
- Which parts of sideBar currently feel the least polished?
- Which components should feel especially premium or distinctive?
- Which components are central to sideBar’s identity?
- Which components should remain close to Apple defaults?
- Which components most affect first impressions?

## Questions for the AI coding agent

- What reusable components already exist?
- Which components are duplicated with slight variations?
- Which components have too many one-off styles?
- What states already exist for each component?
- Which components are missing documentation but already used heavily?
- Which components look shared but are actually implemented differently?
- Which components should be documented as native wrappers rather than bespoke components?
- Which components are hardest to use consistently today?

## Good output for this section

A component library where each doc makes it easy to answer:

- When should this component be used?
- When should it not be used?
- Is this native, wrapped, or custom?
- What variants and states are allowed?
- What content patterns belong with it?
- What should the agent reuse instead of recreating?

Each component doc should include:

- purpose
- usage
- variants
- states
- accessibility notes
- platform notes
- content notes
- implementation notes
- inheritance notes
- examples
- do / do not use guidance

---

# 9. Iconography

## Why this section matters

Icons do a lot of subtle work in a product.

They help users scan interfaces faster, recognise actions and objects, and build familiarity over time. But iconography only helps if it is consistent. If icons vary in style, meaning, size, or usage, the UI starts to feel noisier and less deliberate.

For sideBar, iconography should stay closely aligned to Apple’s ecosystem wherever possible, especially through SF Symbols. This section exists to make icon usage feel native, restrained, and semantically consistent rather than decorative or improvised.

## What we need to produce

An `iconography.md` document that defines how icons should be chosen, styled, paired with text, and used across sideBar.

It should explain:

- when icons add clarity versus noise
- when SF Symbols should be the default choice
- how icon size, weight, and rendering should stay consistent
- when icons should be paired with labels
- when custom icons are justified and how they should fit into the system

## Questions for Sean

- Do we want a quiet utilitarian icon style or something more expressive?
- Where should icons help comprehension, and where do they just add visual noise?
- Are there parts of sideBar where icons should be avoided?
- How closely do we want to align to SF Symbols as the default icon system?
- Which parts of sideBar should feel especially native and system-like in their iconography?

## Questions for the AI coding agent

- Which icon sets are currently in use?
- Are icon sizes, weights, and meanings consistent?
- Are the same concepts represented by different icons in different places?
- Are icons being used where labels would be clearer?
- Where are we deviating from SF Symbols, and why?
- Which icons are currently acting more like decoration than communication?

## Good output for this section

An iconography guide that answers:

- When should we use an icon, a label, or both?
- Which symbol should represent a given concept across the whole app?
- What sizes and weights are appropriate in different contexts?
- When is a custom icon justified instead of an SF Symbol?
- How should the agent choose icons without introducing inconsistency?

The final output should make icon usage feel calm, familiar, and system-aware rather than stylistically fragmented.

---

# 10. Interaction patterns

## Why this section matters

This is where the design system defines how sideBar behaves, not just how it looks.

A product can have clean foundations and solid components and still feel inconsistent if similar actions behave differently in different places. Interaction patterns are what make sideBar feel predictable, forgiving, and well designed over time.

For sideBar, this section matters even more because it includes AI-supported moments, content creation, editing flows, and actions that may move users between different parts of sideBar. The aim is to create behavioural consistency, not just visual consistency.

## What we need to produce

A set of pattern docs that define the standard behaviour for the most important flows in sideBar.

These docs should explain:

- how common tasks should work
- where sideBar should feel especially fast, safe, or forgiving
- when the UI should confirm, suggest, automate, or stay out of the way
- which patterns should closely follow Apple conventions
- where the agent should reuse an existing interaction pattern instead of inventing a new one

## Areas to cover

- navigation
- search
- filtering and sorting
- create/edit flows
- destructive actions
- confirmation and undo
- empty states
- loading and sync
- errors and recovery
- success feedback
- multi-step flows
- AI-assisted interactions
- platform-specific navigation shells

## Questions for Sean

- Where do we want sideBar to feel especially fast or forgiving?
- How much confirmation is right before destructive actions?
- When should the UI explain, suggest, automate, or stay out of the way?
- How opinionated should AI-assisted UI be?
- When should sideBar offer a next step versus staying passive?
- Which interaction patterns should explicitly follow Apple conventions?
- Which moments in sideBar should feel especially calm, safe, or polished?

## Questions for the AI coding agent

- What interaction patterns are already present in sideBar?
- Where do equivalent flows behave differently in different areas?
- Are there inconsistent loading, error, or success states?
- Are there repeated flows that should become standard patterns?
- Which flows currently require too much user recovery or guesswork?
- Where do custom interactions fight the expected platform model?
- Which flows feel the most polished already and could become templates?

## Good output for this section

A pattern library that makes these decisions easy:

- How should the same type of task behave across sideBar?
- When should we use confirmation, undo, or silent completion?
- How should sideBar handle recovery from errors or interruptions?
- When should the assistant suggest something versus taking the user straight into an action?
- Which existing interaction pattern should the agent reuse when building something new?

The final output should be a `patterns/` layer that acts as the behavioural reference for sideBar, not just a list of ideas.

---

# 11. Navigation shells, windows, commands, and search

## Why this section matters

These patterns shape how the whole product feels to use, especially on Apple platforms.

A Mac app is defined as much by its windows, menus, toolbars, commands, sidebars, and keyboard behaviour as it is by its individual components. The same is true on iOS and iPadOS, where navigation structure, search placement, and presentation patterns strongly influence whether sideBar feels truly native.

This section exists to capture those structural patterns so we do not end up with a collection of nice components inside an incoherent shell.

## What we need to produce

A set of pattern docs that define the structural UI of sideBar across platforms, especially:

- how people move around sideBar
- how windows and panels should behave on Mac
- how commands and shortcuts should be exposed
- how search should be placed and behave
- how sidebars, split views, and toolbars should support the overall information architecture

## Areas to cover

- sidebars
- split views
- toolbars
- windows and panels
- tab structures
- menus and commands
- keyboard shortcuts
- context menus
- search field placement and behaviour

## Questions for Sean

- Which navigation shell should define the core identity of sideBar on each platform?
- How much of the Mac app should lean into desktop conventions like commands, menus, and multiple windows?
- Which structural patterns should stay as close as possible to native Apple conventions?
- Where does the web app need to follow the same mental model, and where can it diverge?
- Which parts of sideBar should always be reachable quickly?
- Where do we want sideBar to feel spacious and desktop-like versus compact and task-focused?

## Questions for the AI coding agent

- Which structural patterns already exist across iOS, macOS, and web?
- Are sidebars, toolbars, split views, and windows being used consistently?
- What commands, menus, and shortcuts already exist on macOS?
- Where is search placed today, and does it follow platform expectations?
- Which structural patterns feel improvised rather than intentional?
- Where are we missing obvious Apple-platform conventions?
- Which navigation structures are causing duplication or complexity in the codebase?

## Good output for this section

A small set of pattern docs that answer:

- What is the default navigation shell on each platform?
- When should we use a sidebar, a tab structure, a split view, or a separate window?
- Which actions belong in menus, toolbars, context menus, or inline UI?
- How should search behave across iPhone, iPad, Mac, and web?
- Which keyboard shortcuts and commands should be treated as part of sideBar’s core UX?

The final output should cover:

- `patterns/sidebars-toolbars-and-split-views.md`
- `patterns/windows-and-panels.md`
- `patterns/menus-commands-and-shortcuts.md`
- `patterns/search-and-filtering.md`

---

# 12. Wait UX

## Why this section matters

A lot of product quality is revealed in moments where the system is not instant.

Loading, syncing, indexing, retrieving, generating, and saving are all moments where users are forced to interpret what sideBar is doing. If those moments are vague, jumpy, or inconsistent, the whole app feels less reliable. If they are calm, clear, and well paced, sideBar feels more trustworthy.

This matters especially in an AI product, where some operations are genuinely uncertain in duration and some results may be generated rather than fetched. The app needs a clear language for waiting that feels native, informative, and reassuring without becoming noisy.

## What we need to produce

A `wait-ux.md` document that defines how sideBar should behave during short delays, long waits, and background work.

It should explain:

- when to show nothing
- when to show subtle activity
- when to show progress or status messaging
- how to preserve context while waiting
- how to handle cancellation, retry, and recovery
- how AI generation states should feel different from ordinary loading

## Areas to cover

- instant responses
- short waits
- longer waits
- determinate vs indeterminate states
- skeletons and shimmer
- preserving context during waiting
- AI generation states
- cancellation and retry
- background processing

## Questions for Sean

- What kinds of waiting are most common in sideBar?
- Where do users need reassurance versus where should the UI stay invisible?
- How transparent should sideBar be about what it is doing?
- How should AI generation be framed so it feels trustworthy and calm?
- Where should wait states feel lightweight versus more explicit?

## Questions for the AI coding agent

- What loading indicators already exist?
- Where do we use spinners, skeletons, progress bars, or blank states today?
- Are wait states descriptive or generic?
- Where do multiple competing indicators appear?
- Which slow operations need better feedback or recovery?
- Where are we dropping users out of context while work is happening?
- Which AI flows need a more deliberate waiting pattern?

## Good output for this section

A wait UX guide that answers:

- Should this action show no feedback, subtle feedback, or explicit progress?
- What wording should appear while something is happening?
- How do we distinguish loading, syncing, indexing, and generating?
- When should users be able to cancel, retry, or continue doing other work?
- How should the agent describe work-in-progress states without sounding repetitive or uncertain?

The final output should be a simple but opinionated framework for handling delay across the whole app.

---

# 13. Feedback and haptics

## Why this section matters

Good products constantly tell users what is happening, whether something worked, and what they can do next.

That feedback can be obvious or subtle: a state change, a success message, a warning, a disabled control, a progress indicator, or a haptic acknowledgement. If these signals are inconsistent, sideBar feels less responsive and less trustworthy. If they are well judged, sideBar feels calm, polished, and alive.

Because this is primarily an Apple-platform product, this section should also define where haptics and other native feedback behaviours are worth using and where restraint is the better choice.

## What we need to produce

A `feedback-and-haptics.md` document that defines how sideBar should communicate outcomes, affordances, and state changes.

It should explain:

- which kinds of feedback sideBar uses
- when feedback should be subtle versus explicit
- how success, warning, and error states should differ
- when haptics are appropriate on Apple platforms
- how feedback should support trust without becoming noisy

## Areas to cover

- success feedback
- error feedback
- warning states
- subtle acknowledgements
- haptics
- progress feedback
- disabled states
- retry and recovery signals

## Questions for Sean

- Where should feedback feel subtle versus explicit?
- Which moments deserve haptics on Apple platforms?
- How celebratory or restrained should success states be?
- Where do we want reassurance without adding noise?
- Which product moments most need a stronger feeling of responsiveness?

## Questions for the AI coding agent

- What feedback patterns already exist today?
- Are success, error, and warning states implemented consistently?
- Where are haptics already used?
- Which actions currently lack useful feedback?
- Are we overusing or underusing transient feedback like banners or toasts?
- Which actions rely too much on visual change alone and need clearer acknowledgement?

## Good output for this section

A feedback guide that answers:

- What kind of feedback should follow this action?
- Should the result be silent, subtle, or explicit?
- Does this moment justify haptics, and if so what kind?
- How should recovery be signalled when something fails?
- How do we make sideBar feel responsive without interrupting the user too often?

The final output should give sideBar a consistent language of acknowledgement, progress, reassurance, and recovery.

---

# 14. Onboarding

## Why this section matters

Even strong products can feel confusing if they ask too much of users too early.

Onboarding is how we help people understand sideBar, discover important capabilities, and build confidence without overwhelming them. It is not just a first-run flow. It also includes feature introduction, contextual education, permission moments, and re-entry paths for things users skipped or forgot.

For sideBar, onboarding matters because sideBar combines standard productivity patterns with AI-supported behaviour. That means some things should feel instantly obvious, while others will need thoughtful explanation at the right moment.

## What we need to produce

An `onboarding.md` document that defines how we introduce sideBar, explain key capabilities, and teach users without slowing them down.

It should explain:

- what a new user needs to understand first
- which things should be taught contextually rather than upfront
- how feature education should work over time
- how permission requests should be framed
- when onboarding should be optional, skippable, or revisit-able

## Areas to cover

- first-run onboarding
- feature introduction
- contextual education
- teaching popovers
- empty-state education
- permission requests
- re-entry paths

## Questions for Sean

- What must a new user understand quickly to succeed?
- Which features need active explanation and which should feel self-evident?
- How much onboarding is too much?
- What should be optional, skippable, or revisit-able?
- Which parts of sideBar are most likely to confuse first-time users?

## Questions for the AI coding agent

- What onboarding already exists?
- Where are users likely to encounter confusion today?
- Which areas of sideBar would benefit from contextual education rather than a tutorial?
- Are there places where onboarding is missing, overly verbose, or badly timed?
- Which permission or setup moments currently feel abrupt or unclear?

## Good output for this section

An onboarding guide that answers:

- What should a new user learn on day one versus later?
- When should we teach inline, in a modal flow, or through an empty state?
- How should AI features be introduced without sounding intimidating or overpromising?
- When should sideBar remind, re-teach, or stay silent?
- How do we help users succeed quickly without overexplaining sideBar?

The final output should give sideBar a clear educational strategy rather than a collection of one-off tips and walkthroughs.

---

# 15. Handoffs

## Why this section matters

A lot of product quality is determined by what happens between actions, not just within them.

Handoffs are the moments where sideBar moves users from one part of a workflow to another: from assistant to note, from search result to action, from notification to destination, from one platform or context into another. If these transitions are clumsy, users lose context and momentum. If they are well designed, sideBar feels joined up and intelligent.

For sideBar, handoffs are especially important because the assistant is likely to initiate, suggest, or accelerate actions that end in other parts of sideBar.

## What we need to produce

A `handoffs.md` document that defines how sideBar should move users between contexts while preserving meaning, momentum, and control.

It should explain:

- which transitions count as core handoffs
- what context must be preserved in each case
- when a handoff should be direct versus suggestive
- how the UI should prepare users for the next step
- how handoffs should work across platforms and future features

## Areas to cover

- assistant to notes
- assistant to tasks
- assistant to saved content
- assistant to files
- search to action
- notification to destination
- cross-platform continuation
- future app-to-app or feature-to-feature handoffs

## Questions for Sean

- Where should the assistant initiate or suggest the next step?
- What context must never be lost during transitions?
- When should handoffs be direct versus lightweight suggestions?
- Which handoffs are most important to make feel seamless?
- Where do we most want sideBar to feel joined up rather than conversational?

## Questions for the AI coding agent

- What handoffs already exist in sideBar?
- Where are users dropped into a destination without enough context?
- Where does context get duplicated, lost, or reset?
- Which transitions are currently awkward or fragmented?
- Which handoffs already work well enough to become standard patterns?

## Good output for this section

A handoff guide that answers:

- What information must travel with the user into the next screen or state?
- Should the handoff happen automatically, through a suggestion, or through explicit confirmation?
- How should the destination acknowledge where the user came from and why they are there?
- How do we keep assistant-driven actions from feeling disconnected from the rest of sideBar?
- Which handoff pattern should the agent reuse for similar flows?

The final output should make transitions feel purposeful, lightweight, and context-preserving.

---

# 16. AI assistant UI

## Why this section matters

The assistant is not just another feature. It changes how sideBar behaves.

It affects copy, feedback, onboarding, handoffs, editing flows, and user trust. If assistant-led moments feel inconsistent with the rest of sideBar, sideBar will feel split in two: one part native productivity app, one part floating AI layer. This section exists to stop that from happening.

It should define how the assistant appears, how proactive it should be, how it communicates uncertainty, when it should ask before acting, and how it should hand work back into sideBar. The aim is for assistant interactions to feel like a natural extension of sideBar rather than a separate system pasted on top.

## What we need to produce

An `ai-assistant-ui.md` document that defines the UI rules for assistant-driven and AI-supported moments.

It should cover:

- how assistant interactions are framed in the UI
- how suggestions, actions, previews, and confirmations should work
- when the assistant should feel reactive versus proactive
- how confidence, uncertainty, and work-in-progress should be communicated
- how assistant interactions should map back into notes, tasks, files, saved content, and future features
- how sideBar’s character should appear in assistant-led moments

## Areas to cover

- assistant framing in the UI
- suggestion chips and actions
- confidence and uncertainty language
- generation states
- editable vs auto-applied changes
- previews before action
- memory/context disclosures where relevant
- assistant handoffs into product features

## Questions for Sean

- How visible should the assistant be in the overall product?
- When should the assistant feel proactive versus reactive?
- Where should users always stay in control?
- What should the assistant never do silently?
- Where should assistant UI feel fully native versus visibly distinct?
- How much explanation is useful versus distracting in AI-led moments?
- How much character should the assistant show in product interactions?
- Where should sideBar feel expressive versus restrained?

## Questions for the AI coding agent

- What assistant UI patterns already exist?
- Where are AI actions consistent and where are they not?
- Are there unclear distinctions between suggestion, automation, and execution?
- Which AI flows need a more explicit pattern library?
- Where does current assistant UI diverge from the wider app language?
- Which assistant interactions already feel strong enough to standardise?
- Where does the existing product already imply a distinct assistant personality?

## Good output for this section

An assistant UI guide that answers:

- When should the assistant suggest, preview, ask, confirm, or act?
- How should assistant actions be represented in the interface?
- How do we communicate uncertainty without undermining trust?
- Which actions require explicit user review or approval?
- How should the assistant hand users into the rest of sideBar without losing context?
- How should sideBar’s voice and character appear differently in chat, UI chrome, errors, help, and automation?

The final output should make assistant-led UI feel coherent, safe, product-native, and recognisably sideBar, while still acknowledging that it behaves differently from ordinary interface elements.

---

# 17. AI-agent implementation rules

## Why this section matters

The design system only becomes operational when the AI coding agent can use it consistently.

That means the system needs more than principles and examples. It needs implementation rules: naming, structure, reuse rules, decision boundaries, and clear defaults. Without that layer, the agent will keep making reasonable but inconsistent choices.

This section is where we turn the design system into something executable. It should tell the agent how to behave when building new UI, extending existing UI, and deciding between native components, wrappers, and custom implementations.

## What we need to produce

A set of docs in `agent-rules/` that define how the AI coding agent should consume and apply the design system.

These docs should explain:

- how components, tokens, and files should be named
- when the agent should reuse, extend, or create something new
- which defaults the agent should prefer on Apple platforms
- what must be documented when introducing a new UI pattern
- which decisions require human judgement rather than autonomous choice

## Questions for Sean

- How prescriptive do we want these rules to be?
- Should the agent be allowed to create new variants, or only use approved ones?
- What level of freedom should the agent have when designing new UI?
- When should the agent ask for human judgement rather than deciding on its own?
- Which Apple-native defaults should the agent treat as preferred options?
- Where do we want to encourage speed, and where do we want to enforce discipline?

## Questions for the AI coding agent

- What naming patterns currently exist in the codebase?
- How are components organised today?
- What file structures are already in place?
- What implementation guidance would reduce inconsistency the most?
- How can docs be written so they are easiest to consume programmatically?
- How should the agent decide between native components, wrappers, and custom implementations?
- Where does the current codebase encourage duplication or one-off UI?

## Good output for this section

A set of agent rules that answer:

- What should the agent reach for first when building new UI?
- When is it acceptable to create a new component or variant?
- What needs to be documented before a new UI pattern is considered part of the system?
- Which decisions can the agent make independently and which need human approval?
- How do we keep velocity high without letting the system drift?

The final output should include docs covering:

- naming conventions
- token usage rules
- component creation rules
- composition rules
- when to extend vs create new
- required doc format for any new component
- feature UI checklist
- prompt templates for the coding agent
- a default preference for native Apple components where appropriate

---

# 18. Design-to-code parity

## Why this section matters

A design system only stays useful if the docs and sideBar continue to reflect each other.

If the documentation says one thing and the implementation does another, the system quickly stops being trusted. Design-to-code parity is what keeps the design system grounded in real components, real tokens, and real behaviour rather than turning into a parallel universe of nice intentions.

For sideBar, parity matters even more because the design system is meant to feed an AI coding agent. If the connection between documentation and implementation is loose, the agent will fill gaps with guesswork.

## What we need to produce

A `design-to-code-parity.md` document that defines how design docs, code, and future Figma work should stay aligned.

It should explain:

- what counts as the source of truth for different kinds of decisions
- how tokens, components, variants, and states should map to implementation
- how inherited Apple behaviours should be documented without over-designing them
- how experiments and exceptions should be handled without polluting the core system
- how parity drift should be identified and corrected

## Questions for Sean

- How important is it that future Figma work maps directly to code?
- Do we want every documented component and variant to have a code counterpart?
- What level of design exploration do we want outside the system?
- How should inherited Apple behaviours be represented in Figma and docs without over-designing them?
- Where do we want the system to stay strict, and where can it remain lightweight?

## Questions for the AI coding agent

- Which documented concepts already map cleanly to code?
- Where are code implementations too loose or inconsistent to support parity?
- Which component props, states, or tokens should become part of the public system contract?
- What would make design drift easiest to detect?
- Which platform behaviours should be documented as inherited rather than redesigned?
- Where are there already mismatches between documentation language and implementation reality?

## Good output for this section

A parity guide that answers:

- What is the source of truth for this decision?
- Does this documented component actually exist in code?
- How should an inherited native behaviour be represented in docs and design artefacts?
- How do we document experiments without implying they are part of the core system?
- How do we know when the design system has drifted from the shipped product?

The final output should keep the system honest, lightweight, and closely tied to what is actually built.

---

# 19. Current UI audit

## Why this section matters

This is where the design system stops being aspirational and becomes grounded in the real product.

Before we standardise anything, we need a clear picture of what already exists across sideBar: which screens feel coherent, which component families are fragmented, where the platform fit is strong, and where the UI has drifted. This section should surface both problems and strengths.

It should also help us avoid unnecessary redesign work. Some parts of sideBar may already be good enough to elevate into the design system with minimal change.

## What we need to produce

A practical audit of the current product that identifies:

- the major screens, flows, and component families
- the strongest and weakest areas of the UI
- token usage and hard-coded styling drift
- places where Apple-native frameworks are being used well
- places where custom UI is fighting the platform
- the highest-value clean-up opportunities

This section should create the backlog that turns the workbook into action.

## Questions for the AI coding agent

- What are the main screens, flows, and shared components in sideBar?
- What tokens or pseudo-tokens already exist?
- What are the clearest areas of inconsistency?
- Which parts of sideBar already look and feel coherent?
- Which quick wins would improve polish fastest?
- Which component families are most fragmented?
- Where are the biggest gaps between SwiftUI and web?
- Where are we making good use of Apple’s frameworks already?
- Where are we bypassing Apple-native patterns without a strong reason?
- Which parts of the UI seem hardest to maintain because of one-off decisions?

## Questions for Sean

- Which screens or flows are highest priority?
- Which parts of sideBar do you feel proud of already?
- Which parts feel rough, dated, or inconsistent?
- Which areas are most important for first impressions?
- Which areas are most commercially or strategically important?
- Which parts already feel the most Apple-native and polished?
- Which parts most need simplification rather than embellishment?

## Good output for this section

Five working docs:

- `current-ui-audit.md`
- `inconsistency-backlog.md`
- `token-audit.md`
- `component-inventory.md`
- `system-framework-usage-audit.md`

Together, these should answer questions like:

- What should be preserved as-is?
- What should be standardised next?
- What should be simplified, deprecated, or replaced?
- Where can we get the biggest polish gains with the least effort?
- Where should the agent stop inventing and start reusing?

This section should be concrete and evidence-led. It should read like a product review and clean-up plan, not a vague critique.

---

# 20. Prioritisation

## Goal
Avoid trying to solve everything at once.

## Recommended order
1. principles
2. system inheritance
3. platform strategy
4. current UI audit
5. token model
6. foundations
7. voice and content design
8. high-usage components
9. navigation shells, windows, commands, and search
10. wait UX
11. feedback and haptics
12. handoffs
13. AI assistant UI
14. onboarding
15. accessibility
16. agent rules
17. design-to-code parity
18. lower-priority components and refinements
19. Figma library later, if useful

---

## Definition of done for v1

Version 1 of the design system is complete when:

- core principles are documented
- system inheritance rules exist
- platform guidance exists
- token model is documented
- foundations are documented and tokenised
- voice and content rules exist
- the most important shared components are documented
- the main interaction patterns are documented
- navigation shell and command guidance exists
- wait UX rules exist
- feedback and haptics guidance exists
- onboarding guidance exists
- handoff guidance exists
- AI assistant UI rules exist
- accessibility rules exist
- agent implementation rules exist
- a backlog exists for future clean-up and refinement

---

## Notes

- The first version should optimise for usefulness, not completeness.
- It is better to document 70% of the real system clearly than 100% of an imagined one vaguely.
- Figma can come later once the underlying system is stable enough to deserve it.
- The markdown docs are the source of truth. Skills, prompts, and future design assets should consume them rather than replace them.
- The design system should sit on top of Apple’s Human Interface Guidelines for iOS and macOS rather than trying to replace them.
- Where Apple gives us strong native behaviour, appearance, or accessibility support, we should usually inherit it and document that choice clearly.
