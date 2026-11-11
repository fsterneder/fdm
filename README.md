# fdm-3
Vibe coded metronome based on the KDM-3

## App: fdm-3

A native macOS 13+ metronome inspired by the feel of a dedicated desktop instrument. Independent project; no Korg branding or sound samples.

## First run on your Mac

1. Put this folder in Downloads and open Terminal (Applications → Utilities → Terminal).
2. Install Apple's free Command Line Tools if you do not have them:

   ```sh
   xcode-select --install
   ```

   Wait for the installation to finish. Full Xcode is optional. A Swift 5.9+ toolchain and macOS SDK are required; if the installed tools are older, update them in System Settings → Software Update or install current Xcode.

3. In Terminal type `cd ` (including the space), drag the fdm-3 folder onto Terminal, and press Return.
4. Run:

   ```sh
   bash scripts/build.sh
   open dist/fdm-3.app
   ```

The build script compiles for your Mac's architecture, creates an app bundle, signs it locally, and makes a ZIP in `dist`. It does not install dependencies or change your security settings. You can move the app into Applications using Finder.

The build embeds a pre-rendered, multi-resolution macOS app icon for Finder and the Dock. The running app also loads this icon explicitly. The icon is stored as base64 in `Assets/AppIcon.icns.base64` and decoded with the built-in macOS base64 utility; no icon generation step or dependencies are needed. The full window is now 320 points wide with tighter spacing and no decorative speaker grille. The bundle identifier is retained so existing tempo and sound preferences carry over.

## Visual design

Version 0.4.0 replaces the default bordered buttons with rounded hardware-style controls, a grey transport button that uses the theme accent during playback, a compact sound dropdown, compact pattern menus, a hardware-style grey-green LCD with symmetric vector seven-segment tempo and beat digits, a voice number, and triangular beat markers, and a calibrated tempo dial. Beat indicators use the same playback state in both window modes. The main LCD follows the KDM-3 reference layout: TEMPO, BEAT, and VOICE (1–5 for Click/Wood/Bright/Clave/Soft Pulse). Triangular markers fill through the current beat and return to outlines when stopped. In No accent mode, the single triangle flashes on every pulse in both the main LCD and widget, without changing the sound. The small metronome symbol swings with each audible beat, including when no accent is selected, and rests upright when stopped. Tempo digits and the BEAT label have separate columns to prevent overlap. The widget uses the same segmented digits and triangular markers in a compact LCD. The bundled icon and build number are updated; quit any older running copy before opening the rebuilt app.

## Controls

Drag the dial up or right to increase tempo; down or left to decrease it. Use the +/− buttons to change beats per bar through No accent, then 2–9 beats. The redundant one-beat option is omitted; saved one-beat settings open as No accent. The dial and arrow keys adjust tempo. Space starts/stops, T taps tempo, Up/Down adjust tempo by 1 BPM, and Left/Right adjust it by 10 BPM while the app is active. Left/Right take priority over focused sliders and pickers. Tap two or more times; the last six taps are averaged. A pause longer than 2.1 seconds starts a fresh tap sequence.

The +/− buttons set the number of quarter-note pulses per bar (0 means no accent). Division adds 1–4 clicks per pulse. The first pulse has a higher pitch; subdivisions are quieter. Volume includes mute. Settings are remembered. Tempo and pattern changes restart the bar immediately. The app continues playing when another app is active, and quits completely when its main window closes. Switching to widget mode shows the floating panel before hiding the main window and keeps playback running. Automatic termination for the last window is disabled; the main window’s explicit close handler quits the app. The instrument window is retained for restoration from widget mode. The widget context menu also offers Quit.

Audio clicks use AVAudioPlayerNode sample positions and a half-second scheduling horizon. The display follows playback completion and may lag audio by roughly the click length. Audio device switching and sleep/wake behavior need testing on real hardware. This first version does not include a tuner, clave patterns, or every KDM-3 function.

## Gap practice (0.4.0)

The GAP dropdown replaces the Beats dropdown; use +/− for beat counts. The first settings row is Division / Gap and the second is Sound / Theme.

Choose Off (default), After 1 bar, After 2 bars, After 4 bars, or Random. Each cycle plays the selected number of audible bars, then exactly one silent bar, and repeats. In Random, every cycle independently chooses 1, 2, or 4 audible bars with equal probability, followed by one silent bar. It never randomizes individual clicks or the duration of the silent bar. Gap values now describe audible bars before silence (changed from 0.3.0). The audio sample clock continues through silence; all subdivision clicks are silenced. The LCD displays GAP during the silent bars in both window modes, while beat indicators and the pendulum continue.

No accent uses four-pulse bars for the gap cycle, without adding an audible accent. Changing gap, tempo, beats, or division restarts from the first audible bar. Gap is saved between launches. Swift tests cover fixed bar boundaries, subdivisions, exactly one silent bar, no-accent mode, deterministic random cycles, draw frequency, and transport reset; they require the macOS/Xcode test environment.

## Themes

The settings use a 2 × 2 grid: Division / Gap, then Sound / Theme. Each card displays both its label and its selected value; clicking opens a native menu directly, with a checkmark on the current choice. The THEME dropdown offers Default (the existing default), Dracula, GitHub Light, Gruvbox, Monokai, Nord, Solarized Dark, and Solarized Light. Default is first and all alternatives are sorted alphabetically. IDE palettes now use their standard background/surface colors rather than added color tints, and color the body, controls, dial, dropdowns, and LCD. Selection updates the full instrument and floating widget immediately and is remembered across launches. GitHub Light uses dark text and light controls. Previous generic theme preferences migrate to the corresponding new palettes. Default keeps the original green hardware LCD. IDE themes use their editor background and syntax accent colors on the LCD too, with flat palette-based controls. The active Start/Stop button uses the theme accent with a contrasting label. The widget status light indicates playing/stopped. Changing theme does not restart playback.

Palette references: [Dracula specification](https://spec.draculatheme.com/), [Nord palettes](https://www.nordtheme.com/docs/colors-and-palettes/), [Gruvbox](https://github.com/morhetz/gruvbox), [GitHub VS Code theme](https://github.com/primer/github-vscode-theme), [Monokai in VS Code](https://github.com/microsoft/vscode/blob/main/extensions/theme-monokai/themes/monokai-color-theme.json), and [Solarized](https://ethanschoonover.com/solarized/).

## Voices

The SOUND dropdown shows only the selected voice; open it to choose from all five voices. The current choice is checked in the menu. The LCD VOICE number identifies the selected sound:

1. Click — original digital click.
2. Wood — original lower wooden tone.
3. Bright — original high click.
4. Clave — a short, bright wooden strike with inharmonic resonance.
5. Soft Pulse — a low, rounded sine tone with smooth attack and release.

All voices have a higher, louder first beat and quieter subdivisions. Existing voice numbers and saved selections remain compatible. New voices taper to silence and stay below the shortest subdivision interval. Waveform tests cover valid levels, silent endpoints, accent levels, and supported sample rates; they run with the macOS test workflow.

## Widget mode

Click the Mini button beside fdm-3, or press Shift–Command–M, to switch to a 196 × 82 floating window that displays the tempo, current beat indicators, and a visible expand button. It stays above ordinary app windows, including while another app is active. Drag the background to move it. Playback continues when switching modes.

The widget has a small status light: grey while stopped and red while playing. Click the expand button below it to return to the full window. Use Space while focused or the context menu to start/stop playback. Right-click the widget for Start/Stop, Tap Tempo, or Show Full fdm-3. Shift–Command–M also returns to the full instrument. Keyboard shortcuts apply while a metronome window is focused; they are not system-wide shortcuts. Space overrides focused button activation and holding it does not repeatedly toggle playback.

## Homebrew distribution

There is no published tap or binary yet. Do not expect `brew install --cask fdm-3` to work.

After testing the app on your Mac:

1. Host the exact `dist/fdm-3-0.4.0.zip` file at an HTTPS URL (for example, a GitHub release).
2. Generate a cask using that URL:

   ```sh
   bash scripts/make-cask.sh https://YOUR-HOST/fdm-3-0.4.0.zip
   ```

3. Put the generated `dist/Casks/fdm-3.rb` in a GitHub repository named `homebrew-fdm-3` under its `Casks` folder.
4. Users can then run `brew install --cask YOUR-GITHUB-NAME/fdm-3/fdm-3`.

The archive targets the architecture of the Mac that builds it. An Intel build and Apple Silicon build require separate releases/cask architecture declarations, or a universal build. Local ad-hoc signing is sufficient for development. For smooth public distribution, sign with Developer ID and notarize with Apple **before** creating the release ZIP and generating its checksum. A downloaded, unnotarized build can be blocked by Gatekeeper; this project does not bypass that protection.

## Validation status

Source prepared on Linux, where Apple's SwiftUI/AVFoundation SDKs are unavailable. Native compilation, Swift tests, listening tests, and UI checks have not run here. `scripts/build.sh` compiles and packages the app on your Mac. Tests run separately with `swift test` using full Xcode, which provides XCTest; Command Line Tools alone may not include it. The included GitHub Actions workflow runs tests before building on a macOS runner.
