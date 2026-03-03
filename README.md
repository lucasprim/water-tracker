# Water Tracker

A native macOS menu bar app that tracks your daily water intake. Logs drinks with one click and can detect drinking automatically using your webcam.

Built with SwiftUI and SwiftData. All data stays on your Mac — no accounts, no cloud.

## Features

- **Menu bar app** — lives in your menu bar, one click to log a drink
- **Bottle tracking** — configurable bottle sizes (metric, ml/L)
- **Daily goal** — set a target and track progress throughout the day
- **Webcam detection** — optionally detects when you're drinking using your camera
- **Calibration tools** — capture baseline/drinking photos, tune color matching with a live testing panel
- **Reminders** — gentle screen-edge nudges when you haven't logged water in a while

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 16+
- Swift 6

## Build & Run

```bash
git clone https://github.com/lucasprim/water-tracker.git
cd water-tracker
xcodebuild -scheme WaterTracker -destination 'platform=macOS' build
```

The built app will be at:
```
~/Library/Developer/Xcode/DerivedData/WaterTracker-*/Build/Products/Debug/Water Tracker.app
```

Or open `WaterTracker.xcodeproj` in Xcode and hit Run.

## Download

Pre-built DMG releases are available on the [Releases](https://github.com/lucasprim/water-tracker/releases) page.

Since the app is not notarized, macOS will block it on first launch. To open it:
1. Right-click the app and choose **Open**
2. Or go to **System Settings > Privacy & Security** and click **Open Anyway**

## Privacy

Water Tracker requests camera access for the optional drinking detection feature. All processing happens locally on your Mac — no images or data are sent anywhere.

## License

MIT
