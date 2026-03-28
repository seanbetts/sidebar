# Design Principles

- Status: drafted
- Owner: both (agent draft, Sean to review and approve)
- Inputs needed: workbook, product docs, codebase inspection (all read), Sean's product intent
- Outputs: this doc
- Dependencies: current-ui-audit.md (complete)
- Codebase review required: yes (complete)
- Human judgement required: yes - Sean should confirm, extend, or revise the principles based on product intent

---

## Purpose

Define what "good" looks like in sideBar. These principles are practical decision rules, not brand language. They should help resolve questions when there is no obvious right answer.

---

## Why this matters

Without explicit principles, the product accumulates inconsistency: each new screen is built by reasoning from scratch, and the AI coding agent makes arbitrary choices in uncovered territory. Principles give every UI decision a shared starting point.

---

## Note on this draft

These principles are derived from:
- the design workbook
- the product documentation
- the assistant identity and soul documentation
- direct codebase inspection

They represent what the product already implies by how it is built, not a redesign. Sean should confirm, challenge, or extend each one. Principles in draft status should not be treated as final.

---

## Core design principles

### 1. Native by default

sideBar lives on Apple platforms. The system already provides typography, colors, materials, animations, accessibility behaviours, and interaction patterns. We inherit all of this unless there is a clear product reason not to.

**Why it matters**: Building on native frameworks keeps the product maintainable, ensures it responds correctly to system accessibility settings, and makes it feel familiar to users who already know iOS and macOS.

**What it means in practice**:
- Use system semantic colors before defining custom ones.
- Use SF Symbols before adding custom icons.
- Use native sheet, alert, picker, and form components before building custom alternatives.
- Use `List`, `TabView`, and `NavigationStack` before building custom equivalents.
- When adding a new UI element, ask: does Apple already solve this?

**Examples of good application**: The tab bar on iPhone, `Form`-based settings, system sheet presentation, SF Symbols throughout.

**Examples of where we deviate intentionally**: The three-column workspace layout (no system equivalent), the custom search dock (placement above tab bar), the rich text editor (UIKit for capability reasons), the Liquid Glass adoption (first-class on iOS 26).

---

### 2. One product, platform-appropriate

sideBar should feel like one product. The same mental model, the same sections, the same structure. But it should not look or behave identically everywhere. iPhone should be compact and direct. iPad and Mac should use space, sidebars, and keyboard navigation. Web should preserve the mental model without pretending to be native.

**Why it matters**: Users move between platforms and expect consistency in what sideBar is and how it thinks. But they also expect the app to feel at home on each platform, not like a phone app scaled up.

**What it means in practice**:
- Shared product structure (Chat, Notes, Tasks, Websites, Files, Skills Store) across all platforms.
- Navigation model adapts: TabView on iPhone, SidebarRail + WorkspaceLayout on iPad/Mac.
- Touch-sized targets on iPhone; pointer-optimised layouts on Mac.
- Mac-specific features (keyboard shortcuts, window management, menu bar, multiple windows) should be used where they add value.
- iPad should embrace the workspace model, not just be a bigger iPhone.

---

### 3. The assistant is part of the product, not added on top

sideBar's AI assistant is not a chatbot window sitting inside an otherwise normal app. It is the product's intelligence layer. Every section connects to it. Its identity, soul, and working relationship with the user shape how the whole product feels.

**Why it matters**: UI decisions about how the assistant is framed, how skills are presented, how tool use appears inline in chat, and how the assistant's identity is surfaced in Settings all affect whether sideBar feels like a coherent product or a productivity app with a chat feature stapled on.

**What it means in practice**:
- Assistant UI should feel integrated, not bolted on. Chat messages, tool banners, and skill components are part of the product's native visual language.
- Settings for sideBar's identity and soul should be presented with the same quality as any other product settings surface.
- Skill execution should feel like part of the product's natural response, not a loading screen for an external API.
- The assistant's voice should feel consistent whether it appears in chat, empty states, error messages, or onboarding.

---

### 4. Calm and focused

sideBar is a productivity tool. Its UI should support focus, not compete with it. The visual language should be restrained and purposeful. Animation, colour, and motion should add clarity and character, not distract.

**Why it matters**: The product category (assistant + notes + tasks + files + websites) could easily become overwhelming. Visual restraint is what keeps it feeling like a calm working environment rather than a busy dashboard.

**What it means in practice**:
- Limit the number of visual elements competing for attention at once.
- Prefer neutral backgrounds and semantic color over decorative color.
- Use animation to communicate meaning (selection state, transitions, loading) not to add visual flair.
- Respect `reduceMotion` not just by removing animation but by ensuring the UI is clear without it.
- Error states should explain clearly without alarming. Success states should be quiet unless the action was significant.

---

### 5. Precision over completeness

When something is unclear, do less and do it well. A single well-executed interaction is better than many mediocre ones. This applies to features, copy, components, and visual design.

**Why it matters**: The product is built largely by a solo developer with an AI coding agent. Scope discipline is essential. It also shapes quality: a small number of polished patterns creates a better impression than a large number of rough ones.

**What it means in practice**:
- Before adding a new component, ask whether an existing one can be adapted.
- Before adding UI copy, ask whether the action speaks for itself.
- When a UI element is unclear, simplify the behaviour rather than explain it with more text.
- Prefer the well-documented standard component over the novel custom one.

---

### 6. Tokens and patterns before custom code

The design system exists to make new UI faster and more consistent. When building something new, reach for the token layer and the component library before writing new values or building new patterns. If what you need doesn't exist in the system, that's a signal to add it to the system.

**Why it matters**: Each one-off decision fragments the product. Each system contribution compounds.

**What it means in practice**:
- Use `DesignTokens.Spacing.*`, `DesignTokens.Radius.*`, `DesignTokens.Colors.*` in all new UI.
- Use `.appFont(style)` for all text.
- Use `SelectableRow`, `PanelHeader`, `EmptyStateView`, `SearchField`, and other established components where they fit.
- If you write a new spacing value, radius, or color that isn't in the token system, add the token first.
- If the same layout or interaction pattern appears twice, it should become a component.

---

### 7. sideBar's character is part of the design

sideBar has a voice, a set of values, and an identity that it manages itself. This shapes not just what it says in conversations but how the whole product feels. Empty states, error messages, onboarding, placeholder copy, and waiting states are all opportunities for the product's character to come through.

**Why it matters**: Copy is part of the experience. A well-written empty state makes the product feel alive. A clumsy error message erodes trust. A consistent voice across the app, docs, support, and marketing builds recognition.

**What it means in practice**:
- Empty states should be useful, not just informational. They should tell the user what to do next.
- Error messages should be honest and direct. They should not be alarming or vague.
- Loading states and waiting moments should feel considered, not abandoned.
- When writing UI copy, refer to the voice and content guide (to be created).
- sideBar's product voice is distinct from the assistant's self-authored identity. The product voice is the developer-authored layer. The assistant's voice emerges from its identity and soul.

---

## Signature product character

These are observations from the current codebase and product docs about what already makes sideBar feel distinctive. They should be preserved and extended, not overwritten.

- **The workspace model**: The two-pane workspace with resizable panels and a persistent sidebar rail is distinctive and functional. It lets users hold two things open at once. This is worth preserving and evolving.
- **The search dock**: On iPhone, the floating search dock above the tab bar is unusual and product-specific. It keeps search accessible without occupying permanent screen space.
- **Integrated intelligence**: Skills run inside the chat thread. Tool execution is visible inline. The assistant's identity is a genuine product surface, not a feature flag.
- **Liquid Glass**: The adoption plan positions Liquid Glass as a first-class design primitive. The floating action dock is already there. The planned adoption across chrome surfaces will define a distinctive visual character for iOS 26.

---

## Where we are native by default

This is a summary of the native-first policy. For full detail see `system-inheritance.md`.

| Area | Policy |
|---|---|
| Navigation (iPhone) | TabView - native |
| Navigation (iPad/Mac) | Custom three-column layout (native alternatives insufficient) |
| Lists | Native SwiftUI List |
| Settings | Native Form with grouped style |
| Sheets / modals | Native .sheet / .fullScreenCover |
| Alerts | Native .alert |
| Colors (iOS) | System semantic UIColor values |
| Colors (macOS) | Custom NSColor palette (documented) |
| Typography | System text style sizes as base, custom scaling applied |
| Icons | SF Symbols as default |
| Accessibility | System accessibility behaviours inherited |
| Materials | System Liquid Glass on iOS 26 / macOS 26 |
| Motion | easeInOut with reduce motion respect |

---

## First-pass note on voice and character

sideBar's product voice and the assistant's self-authored identity are separate things. This is documented in the product docs and should not be collapsed.

- **Product voice** (developer-authored): The tone used in UI copy, docs, support, and marketing. This is what the design system can specify.
- **Assistant identity** (self-managed): The name, tone, values, and boundaries sideBar defines for itself in Settings. This evolves over time.
- **User-controlled settings**: Communication style and working relationship. Controlled by the user.

For design system purposes, the product voice is in scope. The assistant's own identity is not developer-specified beyond the product model it runs on. This distinction must be maintained.

Full definition of the product voice belongs in `voice-and-content.md`.

---

## Open questions

- Should "calm and focused" be more explicit about visual density? (Is sideBar aiming for sparse or dense layouts?)
- How should the workspace model evolve for new sections or content types?
- Are there specific moments in the product where more delight or character should appear, and where should it stay restrained?
- What does the product voice sound like in a few words? (Sean's input needed.)

---

## Related docs

- `system-inheritance.md`
- `platform-strategy/overview.md`
- `voice-and-content.md`
- `audits/current-ui-audit.md`
