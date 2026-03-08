# SpotMenu

**Local music playback in your macOS menu bar**

A minimalist menu bar utility that displays your currently playing track with playback controls, keyboard shortcuts, and a beautiful native UI. Built with Swift and SwiftUI.

---

## Features

- **Menu Bar Integration** — View artist and song title directly in your menu bar
- **Playback Controls** — Hover overlay with play/pause, skip, and album art
- **Keyboard Shortcuts** — Global hotkeys for playback control
- **Compact View** — Toggle between full and compact display modes
- **Live Updates** — Automatically syncs with playback changes
- **Local Library Playback** — Select a folder and play local audio files
- **Metadata & Artwork** — Reads title/artist/cover data from local files
- **Fully Customizable** — Configure visuals, shortcuts, and behavior

---

## Installation

### Download

Get the latest release from [GitHub Releases](https://github.com/fightingentropy/SpotMenu/releases/latest) and open `SpotMenu.app.zip`.

The app is signed and notarized, and includes automatic updates via Sparkle.

### Build from Source

**Requirements:** macOS 13+ (Ventura), Xcode 15+ (GUI optional)

```bash
git clone https://github.com/fightingentropy/SpotMenu.git
cd SpotMenu
make build
make run
```

If you want a local `/Applications/SpotMenu.app` install with stable local signing and Sparkle disabled:

```bash
make local
```

Common terminal workflows:

```bash
make build                     # Debug build
make local                     # Local /Applications install, Sparkle disabled
make test                      # Run test targets
make run                       # Build and launch SpotMenu.app
make clean                     # Remove local derived data
make build CONFIGURATION=Release
```

Local installs use a local `SpotMenu` code-signing identity and intentionally omit Sparkle feed settings so the installed app does not drift from the published release feed.

Release builds should inject Sparkle settings at build time instead of storing them in the project. Use:

```bash
SPARKLE_PRIVATE_KEY=... TAG_NAME=v2.3.12 GITHUB_REPOSITORY=fightingentropy/SpotMenu make sparkle-release
```

That script derives `SPARKLE_PUBLIC_ED_KEY` from `SPARKLE_PRIVATE_KEY`, injects the feed URL during the Release build, and generates a signed appcast in `.codex-build/sparkle-release/dist/`.

Use the same `SPARKLE_PRIVATE_KEY` for future releases if you want existing users to keep receiving Sparkle updates without a manual reinstall.

If you need a non-default feed URL, pass `SPARKLE_FEED_URL=...` when invoking the script.

---

## Preferences

Access via right-click on the menu bar icon → **Preferences...**

### Music Library

Choose a local folder (default: `~/Music`) and SpotMenu indexes supported files (`mp3`, `m4a`, `aac`, `wav`, `aiff`, `flac`, `alac`, `caf`).

### Playback Appearance

Customize the player overlay:

- Hover Tint Color
- Foreground Color
- Blur Intensity
- Hover Tint Opacity

### Menu Bar

Configure display options:

- Show/hide artist and song title
- Show liked icon and app icon
- Compact view mode
- Max width (40–300pt)

### Shortcuts

Set global hotkeys for:

- Play / Pause
- Next / Previous Track

---

## Usage

| Action         | Result                   |
| -------------- | ------------------------ |
| Left-click     | Show/hide playback panel |
| Right-click    | Open context menu        |
| Hover on panel | Reveal playback controls |

---

## Support

If you find SpotMenu useful, open an issue or PR on this repository.
