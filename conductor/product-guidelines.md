# Product Guidelines — Water Tracker

## Voice and Tone

Friendly and approachable. UI text and documentation should feel warm, encouraging, and easy to understand — never clinical or intimidating.

## Design Principles

1. **User Experience above all** — Every decision prioritizes how the user feels using the app. Friction is the enemy.
2. **Modern APIs over universality** — Prefer the latest Apple frameworks (SwiftUI, SwiftData, Vision, etc.) over legacy compatibility layers. Target recent macOS versions.
3. **Configurability** — Key behaviors (reminder intervals, bottle sizes, daily goals) should be user-configurable. Sensible defaults must be provided.
4. **Performant** — The app should feel instant. No jank, no lag, no unnecessary resource usage. A hydration tracker should never slow down the user's Mac.

## Additional Standards

- Use metric units exclusively (milliliters, liters). No imperial units.
- Privacy-first: all data stays on-device. No analytics, no telemetry, no accounts required.
- Minimal UI surface — the app should be unobtrusive and easy to dismiss.
