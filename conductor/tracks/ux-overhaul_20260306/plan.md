# Implementation Plan: UX Overhaul

**Track ID:** ux-overhaul_20260306
**Spec:** [spec.md](./spec.md)
**Created:** 2026-03-06
**Status:** [x] Complete

## Overview

Incrementally transform the Water Tracker UI from its current utilitarian design to a polished, delightful experience. Work is phased to keep the app functional at each stage — the popover layout and core visualization come first, then feedback/interactions, then data features, and finally the settings migration.

## Phase 1: Core Visual Overhaul — Progress Ring & Popover Layout

Replace the cup visualization with a circular progress ring and rework the popover layout.

### Tasks

- [x] Task 1.1: Create `ProgressRingView` — circular ring with `.trim(from:to:)` animated fill, gradient stroke (light blue to deep blue), and numerical overlay (current ml / goal ml) in center
- [x] Task 1.2: Add wave fill animation inside the progress ring — sine-wave `Shape` using `TimelineView` at 30fps, clipped to the ring interior
- [x] Task 1.3: Widen `PopoverContentView` to ~320px, apply `.thinMaterial` background
- [x] Task 1.4: Replace `WaterCupView` with `ProgressRingView` in the popover layout (~160pt diameter, centered)
- [x] Task 1.5: Add preset bottle size buttons — horizontal row of 3-4 quick-log buttons (e.g. 250ml, 350ml, 500ml, 750ml) below the ring, each logging that amount on click
- [x] Task 1.6: Update `AppSettings` model with `presetBottleSizes: [Int]` field (default: [250, 350, 500, 750]), migrate existing data
- [x] Task 1.7: Keep the existing "Log Bottle" flow working as the primary/default size, preset buttons as additional options

### Verification

- [ ] Popover opens at ~320px wide with frosted material background
- [ ] Progress ring animates smoothly when water is logged
- [ ] Wave animation runs inside the ring at all fill levels
- [ ] All preset buttons log the correct amount
- [ ] Existing single-bottle logging still works

## Phase 2: Micro-Interactions & Feedback

Add satisfying feedback for every logging action and celebration for goal completion.

### Tasks

- [x] Task 2.1: Add sound feedback on log — play a subtle system sound (`NSSound`) on successful entry, respect system sound preference
- [x] Task 2.2: Add button scale animation — brief scale-up (1.2x) then back (1.0x) over 300ms with spring easing when a preset button is tapped
- [x] Task 2.3: Add progress ring fill animation — smooth `.spring(response: 0.6, dampingFraction: 0.7)` transition when intake changes
- [x] Task 2.4: Create celebration animation — confetti/splash effect (CAEmitterLayer or SwiftUI particles) triggered when daily goal is first reached, auto-dismiss after ~2 seconds
- [x] Task 2.5: Add undo toast — brief overlay at bottom of popover after logging, showing "Logged Xml" with "Undo" button, auto-dismiss after 4 seconds
- [x] Task 2.6: Remove the right-click context menu "Undo Last Bottle" (replaced by the toast)

### Verification

- [ ] Sound plays on each log action (respects system setting)
- [ ] Buttons bounce on tap
- [ ] Progress ring animates smoothly, no jumps
- [ ] Confetti plays once when goal is first reached, not on subsequent logs
- [ ] Undo toast appears, undo actually removes the entry, toast auto-dismisses

## Phase 3: Dynamic Menu Bar Icon & Global Shortcut

Make the menu bar icon informative and add a keyboard shortcut for power users.

### Tasks

- [x] Task 3.1: Create dynamic menu bar icon — render SF Symbol `drop.fill` with variable fill level based on daily progress (empty, quarter, half, three-quarter, full), update reactively
- [x] Task 3.2: Keep existing blue tint when webcam detection is active (layer on top of fill level)
- [x] Task 3.3: Add global keyboard shortcut for quick-logging default bottle size — register via `NSEvent.addGlobalMonitorForEvents` or `KeyboardShortcuts` SPM package
- [x] Task 3.4: Show brief menu bar icon bounce animation when quick-log shortcut is used (confirms action even without popover open)
- [x] Task 3.5: Add keyboard shortcut configuration to settings (default: Ctrl+Shift+W or similar)

### Verification

- [ ] Menu bar icon visually reflects 0%, 25%, 50%, 75%, 100% fill states
- [ ] Icon still shows blue tint during active webcam detection
- [ ] Global shortcut logs a drink from anywhere, icon bounces to confirm
- [ ] Shortcut is configurable in settings

## Phase 4: Streak Tracking & Weekly Chart

Add gamification and historical data visualization.

### Tasks

- [x] Task 4.1: Add streak calculation to `DailyProgressStore` — compute current streak (consecutive days meeting goal) and longest streak ever
- [x] Task 4.2: Persist streak data — add `longestStreak: Int` and `lastGoalMetDate: Date?` to `AppSettings` (or compute from `WaterEntry` history)
- [x] Task 4.3: Display streak on main popover — flame icon + "X day streak" below the progress ring, subtle styling
- [x] Task 4.4: Create `WeeklyChartView` using Swift Charts — `BarMark` for 7 days, bars colored by completion (blue partial, green complete, gray missed), `RuleMark` for daily goal line
- [x] Task 4.5: Add expandable/collapsible weekly chart section to the popover — disclosure group or toggle, collapsed by default to keep popover compact
- [x] Task 4.6: Show weekly average as a summary stat in the chart section header

### Verification

- [ ] Streak count is accurate across multiple days of data
- [ ] Streak resets correctly when a day is missed
- [ ] Weekly chart shows correct data for the past 7 days
- [ ] Chart section expands/collapses smoothly
- [ ] Popover remains compact when chart is collapsed

## Phase 5: Settings Window & Detection Log Migration

Move settings to a proper window and relocate the detection log.

### Tasks

- [x] Task 5.1: Create `SettingsWindow` using SwiftUI `Settings` scene with `TabView` — tabs: General, Goal & Bottles, Reminders, Camera
- [x] Task 5.2: Migrate existing settings fields to the new window — bottle size, daily goal, drink interval, camera selection, calibration launch
- [x] Task 5.3: Add new settings: preset bottle sizes editor, sound toggle, keyboard shortcut configuration
- [x] Task 5.4: Move detection log to its own tab or accessible section (e.g. "Camera" tab with sub-section)
- [x] Task 5.5: Update popover footer — replace Settings gear button to open the new Settings window (Cmd+,)
- [x] Task 5.6: Remove old embedded `SettingsView` from popover and the view-switching logic in `PopoverContentView`
- [x] Task 5.7: Ensure Settings window works correctly as a menu-bar-only app (handle Dock icon visibility if needed)

### Verification

- [ ] Settings window opens via gear icon and Cmd+, shortcut
- [ ] All existing settings are preserved and functional in the new window
- [ ] New settings (presets, sound, shortcut) work correctly
- [ ] Detection log is accessible and scrollable in the Camera tab
- [ ] Popover no longer switches to settings mode
- [ ] Settings window behaves correctly without a Dock icon

## Final Verification

- [ ] All 12 acceptance criteria met
- [ ] Tests passing (unit tests for streak logic, preset sizes, model migrations)
- [ ] App builds and runs on macOS 14+
- [ ] Existing SwiftData entries are not lost after migration
- [ ] Webcam detection and auto-logging still work correctly
- [ ] Manual end-to-end test on a real Mac

---

_Generated by Conductor. Tasks will be marked [~] in progress and [x] complete._
