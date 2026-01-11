# Design System Implementation Plan

**Date**: 2026-01-11
**Status**: Planning
**Timeline**: 1-2 weeks (big push)
**Objective**: Centralize and standardize design patterns before UI refinement phase

---

## Executive Summary

### Current Problem
- **180+ lines** of duplicated panel header code across 4 files
- **40+ instances** of platform-specific color code duplication
- **Magic numbers** throughout (spacing, sizing, radius)
- **Inconsistent patterns** that will multiply as we add features
- **High friction** for UI refinement and iteration

### Solution
Create a progressive design system in 4 phases:
1. **Design Tokens** - Centralized values (spacing, colors, sizing)
2. **Reusable Components** - Shared UI building blocks
3. **Utilities & Extensions** - Common helpers and formatters
4. **Style Modifiers** - Consistent styling patterns

### Expected Outcomes
- **300-500 lines removed** through deduplication
- **Zero magic numbers** - all values named and semantic
- **Consistent UI** across all platforms (macOS/iPad/iPhone)
- **Fast iteration** - change design in one place
- **Foundation** for future features

---

## Phase 1: Design Tokens (Foundation)

**Time Estimate**: 3-4 hours
**Priority**: Critical
**Dependencies**: None

### 1.1 Create Design Tokens File

**File**: `ios/sideBar/sideBar/Design/DesignTokens.swift`

**Structure**:
```swift
public enum DesignTokens {
    enum Spacing { }
    enum CornerRadius { }
    enum Size { }
    enum IconSize { }
    enum Typography { }
    enum Colors { }
    enum Animation { }
}
```

**What to Define**:

#### Spacing
- `xxs = 4pt` - Tightest spacing (between icons and text)
- `xs = 6pt` - Very small spacing
- `sm = 8pt` - Small spacing
- `md = 12pt` - Medium spacing
- `lg = 16pt` - **Default** spacing (most common)
- `xl = 20pt` - Large spacing (content padding)
- `xxl = 24pt` - Extra large spacing

#### Corner Radius
- `xs = 2pt` - Brand divider (SiteHeaderBar)
- `sm = 6pt` - Small elements
- `md = 8pt` - Buttons, rail icons
- `lg = 10pt` - Search fields, cards
- `xl = 12pt` - Larger cards
- `xxl = 16pt` - Chat bubbles, input bar

#### Size Constants
- `touchTargetMin = 28pt` - Current minimum (should upgrade to 44pt eventually)
- `touchTargetStandard = 44pt` - HIG standard
- `iconButtonSm = 32pt` - Rail icons, small buttons
- `railWidth = 56pt` - Left sidebar rail
- `leftPanelWidth = 280pt` - Sidebar panel
- `rightSidebarDefault = 360pt` - Right sidebar default
- `rightSidebarMin = 280pt` - Minimum right sidebar
- `mainContentMin = 320pt` - Minimum main area
- `contentMaxWidth = 800pt` - Reading width (notes, websites)
- `panelHeaderMinHeight = 88pt` - From LayoutMetrics

#### Icon Sizes
- `sm = 14pt` - Small icons (panel header actions)
- `md = 16pt` - Medium icons (action buttons)
- `lg = 18pt` - Large icons (section headers, rail)
- `xl = 20pt` - Extra large
- `xxl = 22pt` - Avatar size in rail

#### Colors (Semantic, Platform-Adaptive)

**Backgrounds**:
- `windowBackground` - Primary window/view background
- `panelBackground` - Sidebar/panel background
- `cardBackground` - Cards, tertiary surfaces
- `fieldBackground` - Search fields, inputs

**Selection**:
- `selectionBackground(ColorScheme)` - Inverted (white in dark, black in light)
- `selectionText(ColorScheme)` - Inverted text color
- `rowBackground(ColorScheme)` - Unselected row bg

**Borders & Separators**:
- `separator` - Dividers, borders
- `fieldBorder` - Input field borders

**Text**:
- `textPrimary` - Main text
- `textSecondary` - Secondary text
- `textTertiary` - Least prominent text

**Interactive**:
- `buttonTint` - Accent color for buttons
- `destructive` - Destructive actions

**Status**:
- `success` - Green for success
- `warning` - Orange for warnings
- `error` - Red for errors

#### Animation
- `quick = 0.2s easeOut` - Fast transitions (chat scroll)
- `standard = 0.3s easeInOut` - Default animations
- `slow = 0.4s easeInOut` - Deliberate animations

#### Convenience Extensions
```swift
public extension CGFloat {
    static let spacingLG = DesignTokens.Spacing.lg
    static let radiusLG = DesignTokens.CornerRadius.lg
    // etc.
}
```

### 1.2 Migration Checklist

**Files to Update** (do incrementally, not all at once):

- [ ] `SidebarPanels.swift` - Replace all magic numbers in panel headers
  - Padding: `.padding(16)` → `.padding(.spacingLG)`
  - Radius: `.cornerRadius(10)` → `.cornerRadius(.radiusLG)`
  - Colors: Replace all computed color vars with `DesignTokens.Colors.*`

- [ ] `ChatView.swift` - Chat bubble styling
  - Border radius: `16` → `.radiusXXL`
  - Colors: Use semantic colors

- [ ] `SiteHeaderBar.swift` - Header styling
  - Padding, sizing → tokens

- [ ] `SidebarRail.swift` - Rail sizing
  - Width: `56` → `DesignTokens.Size.railWidth`
  - Icon size: `18` → `DesignTokens.IconSize.lg`

**Success Criteria**:
- ✅ DesignTokens.swift created with all values
- ✅ Zero hardcoded colors in 5+ files
- ✅ All spacing uses tokens in new code
- ✅ Easy to change app-wide spacing/colors

---

## Phase 2: Reusable Components

**Time Estimate**: 6-8 hours
**Priority**: High
**Dependencies**: Phase 1

### 2.1 PanelHeader Component ⭐ HIGHEST VALUE

**File**: `ios/sideBar/sideBar/Design/Components/PanelHeader.swift`

**Problem**:
- Same header duplicated in 4 files (180 lines)
- ConversationsPanel: 129-175
- NotesPanel: 357-410
- FilesPanel: 785-838
- WebsitesPanel: 1155-1191

**API Design**:
```swift
public struct PanelHeader: View {
    let title: String
    let searchPlaceholder: String
    @Binding var searchQuery: String
    let actions: [HeaderAction]

    public enum HeaderAction {
        case add(action: () -> Void, label: String)
        case folder(action: () -> Void, label: String)
        case custom(icon: String, action: () -> Void, label: String)
    }
}
```

**Usage Example**:
```swift
// Before (47 lines)
private var header: some View {
    VStack(alignment: .leading, spacing: 16) {
        HStack(spacing: 12) {
            Text("Notes")
                .font(.subheadline.weight(.semibold))
            Spacer()
            Button { } label: { Image(systemName: "folder") }
            Button { } label: { Image(systemName: "plus") }
        }
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
            TextField("Search notes", text: $searchQuery)
            // ... 20 more lines
        }
    }
    .padding(16)
}

// After (4 lines)
PanelHeader(
    title: "Notes",
    searchPlaceholder: "Search notes",
    searchQuery: $viewModel.searchQuery,
    actions: [
        .folder(action: { }, label: "Add folder"),
        .add(action: { }, label: "Add note")
    ]
)
```

**Migration Checklist**:
- [ ] Create PanelHeader.swift with full implementation
- [ ] Test in ConversationsPanel first
- [ ] Migrate NotesPanel
- [ ] Migrate FilesPanel
- [ ] Migrate WebsitesPanel
- [ ] Remove old header code from all panels

**Impact**: ~150 lines removed, consistent behavior

---

### 2.2 SearchField Component

**File**: `ios/sideBar/sideBar/Design/Components/SearchField.swift`

**Problem**: Custom search field pattern repeated 5x

**API Design**:
```swift
public struct SearchField: View {
    let placeholder: String
    @Binding var text: String
    var onClear: (() -> Void)? = nil
}
```

**Features**:
- Magnifying glass icon
- Clear button (x) when text present
- Proper styling with DesignTokens
- Accessibility labels

**Note**: If PanelHeader includes search, this becomes part of it. Otherwise standalone.

---

### 2.3 SelectableRow Component

**File**: `ios/sideBar/sideBar/Design/Components/SelectableRow.swift`

**Problem**: Selection styling duplicated in 6 row types

**API Design**:
```swift
public struct SelectableRow<Content: View>: View {
    let isSelected: Bool
    @ViewBuilder let content: () -> Content

    @Environment(\.colorScheme) private var colorScheme

    public var body: some View {
        content()
            .listRowBackground(
                isSelected
                    ? DesignTokens.Colors.selectionBackground(colorScheme)
                    : DesignTokens.Colors.rowBackground(colorScheme)
            )
            .foregroundStyle(
                isSelected
                    ? DesignTokens.Colors.selectionText(colorScheme)
                    : DesignTokens.Colors.textPrimary
            )
    }
}
```

**Usage Example**:
```swift
// Before (in each row)
.listRowBackground(
    viewModel.selectedConversationId == conversation.id
        ? selectionBackground
        : unselectedRowBackground
)
.foregroundStyle(isSelected ? selectedTextColor : primaryTextColor)

// After
SelectableRow(isSelected: viewModel.selectedConversationId == conversation.id) {
    ConversationRowContent(conversation: conversation)
}
```

**Migration Checklist**:
- [ ] ConversationRow
- [ ] NotesTreeRow
- [ ] FilesIngestionRow
- [ ] WebsiteRow
- [ ] MemoryRow
- [ ] Any other custom rows

---

### 2.4 EmptyStateView Component

**File**: `ios/sideBar/sideBar/Design/Components/EmptyStateView.swift`

**Problem**: Multiple empty state implementations (SidebarPanelPlaceholder, PlaceholderView, inline VStacks)

**API Design**:
```swift
public struct EmptyStateView: View {
    let icon: String?
    let title: String
    let subtitle: String?
    let action: EmptyStateAction?

    public struct EmptyStateAction {
        let title: String
        let action: () -> Void
    }
}
```

**Usage Example**:
```swift
// Simple
EmptyStateView(
    icon: "doc.text",
    title: "No notes yet",
    subtitle: nil,
    action: nil
)

// With action
EmptyStateView(
    icon: "globe",
    title: "No websites saved",
    subtitle: "Tap + to add your first website",
    action: .init(title: "Add Website") { showAddSheet = true }
)
```

**Migration**: Replace SidebarPanelPlaceholder and PlaceholderView

---

### 2.5 LoadingView Component

**File**: `ios/sideBar/sideBar/Design/Components/LoadingView.swift`

**API Design**:
```swift
public struct LoadingView: View {
    let message: String?

    public init(message: String? = nil) {
        self.message = message
    }
}
```

**Usage**: Replace ProgressView instances that appear in full-screen contexts

---

## Phase 3: Utilities & Extensions

**Time Estimate**: 2-3 hours
**Priority**: Medium
**Dependencies**: Phase 1

### 3.1 Date Formatters

**File**: `ios/sideBar/sideBar/Design/Extensions/DateFormatter+SideBar.swift`

**Problem**: Formatters defined in multiple files
- ChatView: 1000-1019 (3 formatters)
- MemoriesView: 183-188 (1 formatter)
- SidebarPanels: references another

**Centralized Definition**:
```swift
public extension DateFormatter {
    /// Short time only (3:45 PM)
    static let chatTimestamp: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    /// Medium date (Jan 11, 2026)
    static let chatList: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    /// Medium date + short time (Jan 11, 2026 at 3:45 PM)
    static let chatHeader: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    /// Long date (January 11, 2026)
    static let publishedDate: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .none
        return f
    }()
}
```

**Migration**: Replace all DateFormatter definitions with shared formatters

---

### 3.2 String Utilities

**File**: `ios/sideBar/sideBar/Design/Extensions/String+SideBar.swift`

**Problem**: `.trimmed` extension duplicated 3x

**Centralized Definition**:
```swift
public extension String {
    /// Trims whitespace and newlines
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Removes file extension (.md, .txt, etc.)
    func stripFileExtension() -> String {
        if let dotIndex = lastIndex(of: ".") {
            return String(prefix(upTo: dotIndex))
        }
        return self
    }
}
```

**Migration**: Remove duplicated extensions, use shared versions

---

### 3.3 Image Loading Helper

**File**: `ios/sideBar/sideBar/Design/Extensions/Image+SideBar.swift`

**Problem**: Profile image loading duplicated in SidebarRail and SettingsView

**Centralized Definition**:
```swift
public extension Image {
    static func profileImage(from data: Data) -> Image? {
        #if os(macOS)
        guard let image = NSImage(data: data) else { return nil }
        return Image(nsImage: image)
        #else
        guard let image = UIImage(data: data) else { return nil }
        return Image(uiImage: image)
        #endif
    }
}
```

**Usage**:
```swift
if let image = Image.profileImage(from: data) {
    image.resizable().scaledToFill()
}
```

---

### 3.4 File Stripping Helper

**File**: Include in `String+SideBar.swift`

**Problem**: `stripFileExtension()` function duplicated

**Add to String extension** (see 3.2 above)

---

## Phase 4: Style Modifiers

**Time Estimate**: 3-4 hours
**Priority**: Medium-Low
**Dependencies**: Phases 1-3

### 4.1 Glass Button Style

**File**: `ios/sideBar/sideBar/Design/Styles/GlassButtonStyle.swift`

**Problem**: Button styling repeated in SiteHeaderBar, SidebarRail

**Implementation**:
```swift
public struct GlassButtonStyle: ButtonStyle {
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(6)
            .background(
                RoundedRectangle(
                    cornerRadius: DesignTokens.CornerRadius.lg,
                    style: .continuous
                )
                .fill(DesignTokens.Colors.cardBackground)
            )
            .overlay(
                RoundedRectangle(
                    cornerRadius: DesignTokens.CornerRadius.lg,
                    style: .continuous
                )
                .stroke(DesignTokens.Colors.separator, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}

public extension ButtonStyle where Self == GlassButtonStyle {
    static var glass: GlassButtonStyle { GlassButtonStyle() }
}
```

**Usage**:
```swift
Button { action() } label: {
    Image(systemName: "arrow.left.arrow.right")
        .frame(width: 28, height: 28)
}
.buttonStyle(.glass)
```

---

### 4.2 Card Style Modifier

**File**: `ios/sideBar/sideBar/Design/Styles/CardModifier.swift`

**For**: Chat message bubbles, cards, contained content

**Implementation**:
```swift
public struct CardModifier: ViewModifier {
    public func body(content: Content) -> some View {
        content
            .padding(12)
            .background(DesignTokens.Colors.cardBackground)
            .overlay(
                RoundedRectangle(
                    cornerRadius: DesignTokens.CornerRadius.xxl,
                    style: .continuous
                )
                .stroke(DesignTokens.Colors.separator, lineWidth: 1)
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: DesignTokens.CornerRadius.xxl,
                    style: .continuous
                )
            )
    }
}

public extension View {
    func cardStyle() -> some View {
        modifier(CardModifier())
    }
}
```

---

### 4.3 Pill Style Modifier

**File**: `ios/sideBar/sideBar/Design/Styles/PillModifier.swift`

**For**: Role pills in ChatView (You, sideBar)

**Implementation**:
```swift
public struct PillModifier: ViewModifier {
    let background: Color
    let foreground: Color
    let bordered: Bool

    public func body(content: Content) -> some View {
        content
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(background)
            .foregroundStyle(foreground)
            .overlay(
                bordered
                    ? Capsule().stroke(DesignTokens.Colors.separator, lineWidth: 1)
                    : nil
            )
            .clipShape(Capsule())
    }
}

public extension View {
    func pillStyle(
        background: Color,
        foreground: Color,
        bordered: Bool = false
    ) -> some View {
        modifier(PillModifier(
            background: background,
            foreground: foreground,
            bordered: bordered
        ))
    }
}
```

---

## Implementation Sequence

### Week 1: Foundation & High-Value Wins

**Day 1-2: Phase 1 (Design Tokens)**
- [ ] Create `Design/` folder structure
- [ ] Create `DesignTokens.swift` with all values
- [ ] Add convenience extensions
- [ ] Test by migrating SidebarPanels.swift colors
- [ ] Validate across light/dark mode, all platforms

**Day 3-4: Phase 2.1 (PanelHeader)**
- [ ] Create `Design/Components/` folder
- [ ] Implement PanelHeader component
- [ ] Test with ConversationsPanel (validate API)
- [ ] Migrate NotesPanel
- [ ] Migrate FilesPanel
- [ ] Migrate WebsitesPanel
- [ ] Remove old header code
- [ ] Test all panels work identically

**Day 5: Phase 2.2-2.5 (Other Components)**
- [ ] Create SelectableRow component
- [ ] Migrate 2-3 row types to test
- [ ] Create EmptyStateView component
- [ ] Replace SidebarPanelPlaceholder usage
- [ ] Create LoadingView component
- [ ] Test all components

### Week 2: Utilities & Polish

**Day 6-7: Phase 3 (Utilities)**
- [ ] Create `Design/Extensions/` folder
- [ ] Create DateFormatter+SideBar.swift
- [ ] Migrate all formatters
- [ ] Create String+SideBar.swift
- [ ] Migrate string utilities
- [ ] Create Image+SideBar.swift
- [ ] Test all utilities

**Day 8-9: Phase 4 (Styles)**
- [ ] Create `Design/Styles/` folder
- [ ] Create GlassButtonStyle
- [ ] Create CardModifier
- [ ] Create PillModifier
- [ ] Migrate existing usage
- [ ] Test all styles

**Day 10: Cleanup & Documentation**
- [ ] Remove all old duplicated code
- [ ] Ensure zero magic numbers
- [ ] Test on all platforms (macOS, iPad, iPhone)
- [ ] Test light/dark mode
- [ ] Create DesignSystem.md documentation
- [ ] Add usage examples
- [ ] Mark this plan as Complete

---

## Testing Checklist

After each phase, verify:

### Functional Testing
- [ ] All views render correctly
- [ ] Selection still works
- [ ] Search still works
- [ ] Buttons still work
- [ ] Navigation still works

### Visual Testing
- [ ] Light mode looks correct
- [ ] Dark mode looks correct
- [ ] macOS renders properly
- [ ] iPad renders properly
- [ ] iPhone renders properly
- [ ] No visual regressions

### Platform Testing
- [ ] macOS (regular & compact if applicable)
- [ ] iPad (regular & compact)
- [ ] iPhone (compact)
- [ ] Rotation works (iPad/iPhone)

### Accessibility Testing
- [ ] VoiceOver announces correctly
- [ ] Touch targets adequate
- [ ] Color contrast maintained
- [ ] Dynamic Type works

---

## Success Metrics

### Quantitative
- ✅ **300-500 lines** of code removed
- ✅ **Zero magic numbers** in Views/ folder
- ✅ **4 panels** use shared PanelHeader
- ✅ **6+ row types** use SelectableRow
- ✅ **All colors** use semantic DesignTokens

### Qualitative
- ✅ **Consistent UI** - All panels look/behave identically
- ✅ **Easy theming** - Can change colors in one place
- ✅ **Fast iteration** - UI changes take minutes not hours
- ✅ **New features** - Can build new panels in <30 min
- ✅ **Maintainable** - Future self/team can understand design patterns

---

## Post-Implementation

### Documentation to Create

**File**: `docs/DesignSystem.md`

Contents:
1. Overview of design tokens
2. Component catalog with examples
3. Usage guidelines
4. Color palette reference
5. Spacing scale reference
6. Typography scale
7. When to create new components (3+ uses rule)

### Future Enhancements

**Not in scope for this plan** (consider later):

1. **Swipe Actions** - Add to list items for quick actions
2. **Context Menus** - Long-press menus on items
3. **Haptics** - Feedback for actions (iOS)
4. **Animations** - Shared transition styles
5. **Sound Effects** - Audio feedback (if desired)
6. **Native .searchable()** - Replace custom search (iOS 15+)
7. **Grid Layouts** - If you add grid views
8. **Data Tables** - If you add table views

---

## Rollback Plan

If something goes wrong:

### Per Phase
- Keep old code commented until migration complete
- Git commit after each phase
- Can revert individual phases

### Complete Rollback
- Design/ folder is additive (doesn't break existing code)
- Can remove Design/ folder entirely if needed
- Old code still works during migration

### Git Strategy
- Create branch: `feature/design-system`
- Commit after each phase completion
- Merge to main when all phases done
- Tag release: `v1.0-design-system`

---

## Questions & Decisions

### Answered
- ✅ Timeline: 1-2 weeks (big push)
- ✅ Approach: All 4 phases sequentially
- ✅ Priority: Do now before UI refinement
- ✅ Scope: Complete design system

### To Decide During Implementation
- Component API details (validate with first use)
- Which magic numbers to keep (rare exceptions)
- Style modifier scope (create as needed)

---

## Notes

- **Don't over-engineer** - If a component is only used 2x, maybe don't extract it yet
- **Validate early** - Test PanelHeader with one panel before migrating all 4
- **Keep it working** - App should compile and run after every commit
- **Document as you go** - Add comments to Design/ files about usage
- **Future-proof** - Think about iPad/iPhone variants when designing components

---

## Status Tracking

- [ ] **Phase 1**: Design Tokens
- [ ] **Phase 2**: Reusable Components
- [ ] **Phase 3**: Utilities & Extensions
- [ ] **Phase 4**: Style Modifiers
- [ ] **Documentation**: DesignSystem.md created
- [ ] **Testing**: All platforms verified
- [ ] **Cleanup**: Old code removed
- [ ] **Complete**: Ready for UI refinement phase

---

**Ready to start?** Begin with Phase 1: Create `Design/DesignTokens.swift` and let's centralize those colors and spacing values!
