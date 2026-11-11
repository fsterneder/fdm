# fdm-3

A compact macOS metronome with round beat lights, tap tempo, subdivisions, gap practice, five sounds, and IDE/Vim themes.

<img src="docs/images/fdm-3.svg" alt="Dracula interface preview" width="352">

## Build and run

Requires macOS 13+ and Apple Command Line Tools with Swift 5.9+. Full Xcode is optional.

```sh
xcode-select --install
bash scripts/build.sh
open dist/fdm-3.app
```

## Controls

- **BPM / subdivision:** drag up/down. Double-click BPM for optional numeric entry.
- **Bottom row:** Tap, Settings, Mute, and Start/Stop. The upper-right arrows open the widget.
- **Settings:** Beats (1–9), Accent, Gap, Gap Length (1–8 bars), Sound, Theme, and volume.
- **Space:** Start/Stop. **T:** tap. **M:** mute.
- **↑/↓:** tempo ±1. **←/→:** tempo ±10. **Shift + ↑/↓:** beats.
- **Tab or &#92;:** switch to the floating widget.

Completed beats stay filled. With Accent enabled, the first indicator uses the Play accent; other active beats use the current-beat color. The widget shows read-only BPM and beat progress.

## Gap practice

Play 1, 2, or 4 audible bars, then 1–8 silent bars. **Random** chooses a fresh audible run length each cycle. The subdivision slot shows silent bars remaining, such as **2/2 → 1/2**.

Existing beat-based gap lengths round up to whole bars. Accent is independent of meter. Closing the main window quits the app.

The Dock icon follows the selected theme; Finder uses Default. Homebrew installation is not published yet. See [CHANGELOG.md](CHANGELOG.md).
