# Glucose

A macOS menu bar app that fetches Dexcom Share glucose data and graphs it, in mmol/L.

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 16 or later (currently built with Xcode 26.3)
- A Dexcom Share account (Outside US: `shareous1.dexcom.com`)

## Build & run

```sh
xcodebuild -project Glucose.xcodeproj -scheme Glucose -configuration Debug \
    -derivedDataPath ./build CODE_SIGNING_ALLOWED=NO build

open build/Build/Products/Debug/Glucose.app
```

Or just open `Glucose.xcodeproj` in Xcode and hit Run.

The app has no Dock icon — look for the value in your menu bar.

## First-run setup

1. Click the menu bar item — a popover appears asking you to sign in.
2. Click **Open Settings…** and enter your Dexcom Share username & password.
3. Hit **Save & Connect**. Credentials are stored in the macOS Keychain (service `se.kalasjocke.glucose.dexcom`).
4. The menu bar item will start showing your latest mmol/L value within 5 minutes.

## What's where

```
Glucose/
├── GlucoseApp.swift              # @main + MenuBarExtra wiring
├── Models/
│   ├── GlucoseReading.swift
│   ├── TimeRange.swift           # 1hr / 3hr / 6hr / 12hr / 24hr
│   └── TrendDirection.swift      # Dexcom trend enum + arrow glyphs
├── Services/
│   ├── DexcomShareClient.swift   # actor; auth + fetch + auto re-auth
│   ├── GlucoseStore.swift        # @Observable; polling, state
│   └── KeychainStore.swift       # credential persistence
└── Views/
    ├── GraphView.swift           # Swift Charts line + hypo/hyper bands
    ├── MenuBarLabel.swift        # arrow + value in the status bar
    ├── PopoverView.swift         # popover layout
    └── SettingsView.swift        # credential entry form
```

## Wipe credentials

```sh
security delete-generic-password -s se.kalasjocke.glucose.dexcom
```
