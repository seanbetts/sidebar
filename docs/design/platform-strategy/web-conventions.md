# Platform Strategy: Web Conventions

- Status: not started
- Owner: both
- Inputs needed: web frontend codebase inspection (not done), Sean's web design intent
- Outputs: this doc (when complete)
- Dependencies: platform-strategy/overview.md
- Codebase review required: yes (not yet done)
- Human judgement required: yes

---

## Purpose

Document web-specific design conventions for sideBar. This covers how the web app should behave relative to the native Apple apps, and what browser-native patterns should be used.

---

## Current state

**This doc is a placeholder.** The web frontend (likely in `frontend/`) was not inspected in the Phase 1 audit. This section cannot be drafted without a separate web codebase inspection.

---

## What is known from product context

- The marketing website is SvelteKit 5 with Svelte 5 runes, deployed to Cloudflare Pages (trysidebar.ai).
- A web app exists (likely separate from the marketing site).
- The web app should preserve the same mental model as the native apps without pretending to be a native Apple app.

---

## Guiding principles for future drafting

These are drawn from the workbook and principles.md. They should govern the web conventions doc once the inspection is done:

1. Same six sections, same mental model, same assistant.
2. Browser-native patterns for navigation, input, and accessibility.
3. Do not replicate iOS or macOS visual chrome (no fake tab bars, no simulated system chrome).
4. Respect the browser scroll model, focus order, and semantic HTML.
5. WCAG AA accessibility as a minimum target.
6. The same token vocabulary should inform the web layer (colors, spacing, typography scale).

---

## Open questions

- What is the web app's current technology stack?
- Does the web app share design tokens with the native apps or define its own?
- Is the web app's navigation model sidebar-based, tab-based, or something else?
- What is the current component state on the web?
- Are there known quality gaps between web and native?

---

## Action needed

Inspect the web frontend codebase and return to draft this document. Likely source: `frontend/src/`.

---

## Related docs

- `platform-strategy/overview.md`
- `platform-strategy/ios-conventions.md`
- `platform-strategy/macos-conventions.md`
