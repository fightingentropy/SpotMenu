# SpotMenu

**Music Folder & Apple Music in your macOS menu bar**

A minimalist menu bar utility that displays your currently playing track with playback controls, keyboard shortcuts, and a beautiful native UI. Built with Swift and SwiftUI.

![Demo](https://github.com/user-attachments/assets/4b6b8e15-7180-44f1-abf7-796566a02fbb)

---

## Features

- **Menu Bar Integration** — View artist and song title directly in your menu bar
- **Playback Controls** — Hover overlay with play/pause, skip, and album art
- **Keyboard Shortcuts** — Global hotkeys for playback control
- **Compact View** — Toggle between full and compact display modes
- **Live Updates** — Automatically syncs with playback changes
- **Local Library Playback** — Select a folder and play local audio files
- **Metadata & Artwork** — Reads title/artist/cover data from local files
- **Multi-Player Support** — Auto-detect or manually select Music Folder / Apple Music
- **Fully Customizable** — Configure visuals, shortcuts, and behavior

---

## Installation

### Download

Get the latest release from [GitHub Releases](https://github.com/fightingentropy/SpotMenu/releases/latest) and open `SpotMenu.app.zip`.

The app is signed and notarized, and includes automatic updates via Sparkle.

### Build from Source

**Requirements:** macOS 13+ (Ventura), Xcode 15+

```bash
git clone https://github.com/fightingentropy/SpotMenu.git
cd SpotMenu
open SpotMenu.xcodeproj
```

---

## Preferences

Access via right-click on the menu bar icon → **Preferences...**

### Music Player

Choose your music player:

- **Automatic** — Uses Apple Music when active, otherwise Music Folder
- **Music Folder**
- **Apple Music**

You can choose a local folder (default: `~/Music`) and SpotMenu will index supported files (`mp3`, `m4a`, `aac`, `wav`, `aiff`, `flac`, `alac`, `caf`).

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

---

## License

MIT License. See [LICENSE](LICENSE) for details.
