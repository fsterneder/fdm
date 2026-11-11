# fdm

A compact macOS metronome with round beat lights, tap tempo, subdivisions, gap practice, five sounds, and IDE/Vim themes.

<img src="docs/images/fdm.svg" alt="Dracula interface preview" width="396">

<img src="docs/images/widget.svg" alt="Compact widget preview" width="281">

## Build and run

Requires macOS 13+ and Apple Command Line Tools with Swift 5.9+. Full Xcode is optional.

```sh
xcode-select --install
bash scripts/build.sh
open dist/fdm.app
```

## Controls

- **BPM / subdivision / gap:** drag up/down. Gap cycles Off, 1, 2, 4, Random audible bars. Double-click BPM for optional numeric entry.
- **Right column:** Widget, Settings, Accent, Mute, and Start/Stop.
- **Settings:** Beats (1–9), Gap Length (1–8 bars), Sound, Theme, volume, and Tap.
- **Space:** Start/Stop. **T:** tap. **M:** mute.
- **↑/↓:** tempo ±1. **←/→:** tempo ±10. **Shift + ↑/↓:** beats. **Shift + ←/→:** gap.
- **Tab or &#92;:** switch to the floating widget.

Completed beats stay filled. With Accent enabled, the first indicator uses the Play accent; other active beats use the current-beat color. Beat-count and accent edits appear immediately; their audio changes follow the boundaries below. The widget shows read-only BPM and beat progress, with a flat expand control.

Tempo, sound, accent, and subdivision changes take effect on the next beat. Beats per bar and gap changes take effect on the next bar, without restarting playback.

## Gap practice

Play 1, 2, or 4 audible bars, then 1–8 silent bars. **Random** chooses a fresh audible run length each cycle. The Gap slot shows silent bars remaining, such as **2/2 → 1/2**.

Existing beat-based gap lengths round up to whole bars. Accent is independent of meter. Closing the main window quits the app.

The Dock icon follows the selected theme; Finder uses Default. Homebrew installation is not published yet. See [CHANGELOG.md](CHANGELOG.md).

