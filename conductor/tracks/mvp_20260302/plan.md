# Implementation Plan: Water Tracker MVP

**Track ID:** mvp_20260302
**Spec:** [spec.md](./spec.md)
**Created:** 2026-03-02
**Status:** [~] In Progress

## Overview

Build the MVP in six focused phases: project scaffolding and data models first,
then the menu bar UI with the animated cup, then settings, then the reminder
timer, and finally the continuous webcam detection. Each phase is independently
buildable and testable before the next begins.

---

## Phase 1: Project Foundation

Set up the Xcode project, configure entitlements, and wire up the
`MenuBarExtra`-based app entry point with a placeholder popover.

### Tasks

- [x] Task 1.1: Create macOS Xcode project targeting macOS 14+, SwiftUI + SwiftData, bundle ID `com.lucasprim.water-tracker`
- [x] Task 1.2: Add required entitlements: `NSCameraUsageDescription`, `NSUserNotificationsUsageDescription`
- [x] Task 1.3: Implement `@main` `App` struct using `MenuBarExtra` with a placeholder popover
- [x] Task 1.4: Set a basic menu bar icon (SF Symbol `drop.fill`)
- [x] Task 1.5: Verify the app launches, appears in the menu bar, and popover opens/closes

### Verification

- [x] App runs on macOS 14+, menu bar icon visible, popover opens with placeholder text

---

## Phase 2: Data Layer

Define and implement all SwiftData models and core business logic for logging
and daily progress. Write unit tests for calculations.

### Tasks

- [x] Task 2.1: Define `WaterEntry` model (`id`, `timestamp`, `volumeMl: Double`)
- [x] Task 2.2: Define `AppSettings` model (`bottleSizeMl`, `dailyGoalMl`, `drinkIntervalMinutes`) with sensible defaults (500 ml bottle, 2 000 ml goal, 15 min interval)
- [x] Task 2.3: Implement `DailyProgressStore` — observable class that computes today's total ml logged and goal-completion percentage from SwiftData
- [x] Task 2.4: Implement `func logBottle()` on `DailyProgressStore` that inserts a new `WaterEntry`
- [x] Task 2.5: Write unit tests for daily total calculation, goal-completion detection, and midnight reset behaviour

### Verification

- [x] Unit tests pass; `DailyProgressStore` correctly totals today's entries and resets at midnight

---

## Phase 3: Menu Bar Popover UI

Build the main popover: animated water cup, progress text, and "Log Bottle"
button. The cup is the centrepiece — invest in a smooth, pleasing animation.

### Tasks

- [x] Task 3.1: Build `WaterCupView` using SwiftUI `Canvas` + `TimelineView`; draw a cup outline with a sine-wave fill that sloshes continuously and rises to match the fill percentage
- [x] Task 3.2: Animate fill level transitions with a spring animation when progress changes
- [x] Task 3.3: Add progress label below the cup: `"1 200 / 2 000 ml"` in a clean sans-serif
- [x] Task 3.4: Add a primary "Log Bottle" button; tapping it calls `DailyProgressStore.logBottle()` and triggers a fill-level animation
- [x] Task 3.5: Show a "Goal reached 🎉" state when daily goal is met (hide the Log button, swap to a completion message)
- [x] Task 3.6: Wire `DailyProgressStore` into the popover so the cup and label update in real time

### Verification

- [x] Popover shows animated cup at the correct fill %; tapping "Log Bottle" updates fill smoothly; goal-reached state displays correctly

---

## Phase 4: Settings Screen

Add a minimal settings view accessible from the popover with clean native macOS styling.

### Tasks

- [x] Task 4.1: Create `SettingsView` as a SwiftUI `Form` with fields: Bottle size (ml stepper/text field), Daily goal (ml stepper), Drink interval (minutes stepper)
- [x] Task 4.2: Persist all settings via `AppSettings` SwiftData model; changes propagate immediately to `DailyProgressStore`
- [x] Task 4.3: Add a "Settings" button/link at the bottom of the popover that opens `SettingsView` (in the same popover or as a sheet)
- [x] Task 4.4: Validate inputs (e.g. bottle size > 0, goal > bottle size, interval ≥ 1 min)

### Verification

- [x] Settings persist across app restarts; changing bottle size/goal immediately updates progress display

---

## Phase 5: Reminder Timer & Notifications

Implement the countdown timer that fires an alert when the user has not drunk water within the configured interval.

### Tasks

- [x] Task 5.1: Implement `DrinkTimerManager` — an `ObservableObject` that holds a countdown (`timeRemaining`) and fires when it reaches zero
- [x] Task 5.2: Display the countdown in the menu bar icon label (e.g. `"12:34"` next to the drop icon) using `MenuBarExtra`'s label view
- [x] Task 5.3: Request `UNUserNotificationCenter` authorisation on first launch
- [x] Task 5.4: When the timer fires, post a `UNNotificationRequest` alert: *"Time to drink water! 💧"*
- [x] Task 5.5: Reset the timer on every manual `logBottle()` call
- [x] Task 5.6: Stop the timer and clear the menu bar countdown when the daily goal is met
- [x] Task 5.7: Write unit tests for `DrinkTimerManager` reset and expiry logic

### Verification

- [x] Timer counts down in menu bar; alert fires when expired; timer resets after logging; stops at goal

---

## Phase 6: Webcam Drinking Detection

Add continuous, non-exclusive webcam monitoring using `AVCaptureSession` and `Vision` to detect drinking gestures and auto-log + reset the timer.

### Tasks

- [x] Task 6.1: Implement `WebcamMonitor` — a class that starts a low-resolution (320×240), low-frame-rate (5 fps) `AVCaptureSession` without requesting exclusive access
- [x] Task 6.2: Add a `AVCaptureVideoDataOutput` delegate that feeds frames into a `VNDetectHumanBodyPoseRequest` to detect raised wrist/hand near face (drinking heuristic)
- [x] Task 6.3: Implement debounce logic (e.g. 3 consecutive positive frames) to avoid false positives
- [x] Task 6.4: On confirmed detection: call `DailyProgressStore.logBottle()`, reset `DrinkTimerManager`, and flash the menu bar icon blue for 2 seconds
- [x] Task 6.5: Stop `WebcamMonitor` session when daily goal is met; restart each new day
- [x] Task 6.6: Handle camera permission denial gracefully (show an in-popover message with a link to System Settings)
- [x] Task 6.7: Verify that FaceTime / Zoom can use the camera simultaneously while `WebcamMonitor` is active

### Verification

- [x] Webcam runs in background; simulated drinking gesture auto-logs and resets timer; other camera apps work concurrently; denial is handled gracefully

---

## Phase 7: Polish & Final Verification

Tighten up animations, assets, and edge cases; run manual end-to-end testing.

### Tasks

- [x] Task 7.1: Design and export app icon + menu bar icon assets (drop/cup motif, works in both light and dark menu bars)
- [x] Task 7.2: Tune `WaterCupView` animation: wave speed, amplitude, colour (blue gradient), cup stroke style
- [x] Task 7.3: Review all popover layouts for spacing, typography, and dark/light mode correctness
- [x] Task 7.4: Handle midnight rollover: reset daily entries and restart the timer automatically
- [x] Task 7.5: Test on macOS 14 and macOS 15 (Sequoia); fix any compatibility issues
- [ ] Task 7.6: Manual end-to-end test of the full flow: launch → settings → log manually → wait for reminder → simulate webcam detection → hit daily goal

### Verification

- [ ] All acceptance criteria from spec.md are met
- [ ] App looks polished in both light and dark mode
- [ ] No crashes or data loss observed in end-to-end testing
- [ ] Ready for App Store submission prep

---

_Generated by Conductor. Tasks will be marked [~] in progress and [x] complete._
