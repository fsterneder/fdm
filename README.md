# fdm-3

A compact macOS metronome with round beat lights, tap tempo, subdivisions, gap practice, five sounds, and IDE/Vim themes.

<img src="docs/images/fdm-3.svg" alt="Dracula interface preview" width="304">

## Build and run

Requires macOS 13+ and Apple Command Line Tools with Swift 5.9+. Full Xcode is optional.

```sh
xcode-select --install
bash scripts/build.sh
open dist/fdm-3.app
```

## Controls

- **BPM:** drag up/down to adjust (30–252). Double-click for optional numeric entry.
- **Subdivision:** drag up/down through quarter notes, eighths, triplets, and sixteenths.
- **Settings:** Beats (1–9), Accent (Yes/No), Gap, Gap Length (1–8 beats), Sound, Theme, and volume.
- **Space:** Start/Stop. **T:** tap. **M:** mute.
- **↑/↓:** tempo ±1. **←/→:** tempo ±10. **Shift + ↑/↓:** beats.
- **Tab or &#92;:** switch to the floating widget.

Completed beats stay filled; the current beat uses the theme's highlight. A one-beat pattern flashes each beat. Accent controls first-beat emphasis independently of the beat count.

The main window shows subdivision or a silent-beat countdown; the single-row widget shows read-only BPM and beat progress. Speaker and Start/Stop use flat styling. Closing the main window quits the app.

## Gap practice

Play 1, 2, or 4 bars' worth of audible beats, then 1–8 silent beats. **Random** chooses a fresh audible run length each cycle with equal probability. Beat counting continues throughout.

During silence, the subdivision slot shows beats remaining out of the gap length, such as **2/2 → 1/2**, then returns to the subdivision.

The old No Accent setting migrates to four beats with Accent off. Existing gap lengths default to one bar, capped at eight beats.

The Dock icon follows the selected theme; Finder uses Default. Homebrew installation is not published yet. See [CHANGELOG.md](CHANGELOG.md).
