---
paths:
  - "FPL/Views/**"
  - "FPL/Assets.xcassets/**"
---

# UI

## Theme

- `Theme` colors: `background` #0F0F23, `surface` #1B1B30 (cards, rows, tab bar, popover), `border`, `text`, `secondaryText`, `accent` #22C55E (also `AccentColor`), `onAccent`, `warning`, `danger`, `yourRow`. All text colors pass 4.5:1.
- Screens `.themedScreen()`, list and form rows `.themedRow()`. Sheets `.presentationBackground(Theme.background)`, popovers `Theme.surface`.
- Don't use `foregroundStyle(_:_:)` on a container: it turns `ContentUnavailableView` descriptions white.
- SF Pro with Dynamic Type text styles only; no custom fonts.

## Tab bar

- Custom `FloodlightsTabBar`, not the system one. Tabs live in a `ZStack` (hidden ones get opacity 0, no hit testing, no accessibility), so each keeps its state but stays alive while hidden: don't start loading until a tab is first shown.
- The bar's safe area inset doesn't reach lists inside each tab's `NavigationStack`, so `ContentView` passes its height as the `tabBarClearance` environment value and `themedScreen()` adds it as a bottom margin. It's 0 in sheets.
- Keep five tabs or fewer; secondary screens go inside a tab's stack. Unbuilt tabs show a `ContentUnavailableView`.
- Profile, Notes and the other top-level tabs hide their navigation bar. With it hidden iOS doesn't draw the refresh spinner, so show your own `ProgressView` row while refreshing.

## Toasts

- One component (`Toast.swift`). A screen keeps `@State var toast: Toast?`, adds `.toast($toast)` after `themedScreen()`, and sets `toast = Toast("…", style: .warning)` or `Toast("Note deleted", action: .init("Undo") { … })`.
- Screens add no timers, transitions or announcements: the modifier handles timing (3s, 5s with an action, 30s with an action under VoiceOver), replacement, dismissal and VoiceOver.
- **Always at the bottom above the tab bar.** Don't add top or per-screen positions. State stays per screen.

## Pull to refresh

- Run the work in its own `Task` and await it from `.refreshable`: SwiftUI cancels the action's task when the screen redraws mid-refresh.
- A failure keeps what's shown and shows `Toast(ProfileRefresh.failedMessage, style: .warning)`. A refresh on returning to the app stays silent.

## Players list

- Search and sort sit at the top (`.searchable` with `.navigationBarDrawer(displayMode: .always)`, a sort `Menu` and an order button): the tab bar owns the bottom. The inline title doubles as the position menu (`.toolbarTitleMenu`).
- Rows are one line: info button (`.buttonStyle(.borderless)`, so the row doesn't open the popover), name with team short name, then fixed-width price and sort-stat columns. The right-hand stat follows the sort.
- Flagged players: name and triangle in `Theme.warning` (1–99% chance) or `Theme.danger` (0%, or news with "Unknown return date"), falling back to status. VoiceOver reads `availabilityDescription`.
- Hide players with `element.isSelectable` false, in the app, not the API: notes still show departed players.

## Stats popover

- Use `statsPopover(isPresented:element:...)` for any place that shows a player: it wraps the popover, the note flow and the model context. The popover closes before the editor sheet opens (`onChange(of:)`), since a sheet can't present over it.
- Popover content doesn't inherit the model container: pass `.modelContext(modelContext)` or its `@Query` comes back empty.
- `.presentationCompactAdaptation(.popover)` keeps it a bubble on iPhone. Missing values show "–".
- Fixtures: the next 3 gameweeks from `is_next`, with difficulty from the player's side. Upcoming means `started == false`, never `!finished`. A blank shows "–"; a double stacks.
