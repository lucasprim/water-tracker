# Tech Stack — Water Tracker

## Primary Language

- **Swift** (latest stable) — native Mac development

## UI Framework

- **SwiftUI** — declarative, modern UI framework for macOS

## Persistence

- **SwiftData** — Apple's modern persistence framework, replaces Core Data for new projects

## Key Apple Frameworks

- **Vision / AVFoundation** — webcam-based drinking detection
- **UserNotifications** — local reminders and hydration nudges
- **MenuBarExtra** — persistent menu bar presence for quick logging
- **AppKit** (where SwiftUI falls short) — fallback for advanced Mac-specific UI needs

## No Backend

All data is stored locally. No server, no cloud sync, no accounts required.
Optional CloudKit sync may be considered in the future.

## Distribution

- **Mac App Store** — primary distribution channel
- **Direct download** — notarized DMG for users outside the App Store

## Target Platform

- macOS 14 (Sonoma) and later — to leverage latest SwiftUI and SwiftData capabilities
