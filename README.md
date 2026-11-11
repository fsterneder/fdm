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

The build also generates a custom macOS app icon for Finder and the Dock. The full window is now 320 points wide with tighter spacing and no decorative speaker grille. The bundle identifier is retained so existing tempo and sound preferences carry over.

## Controls

Drag the dial up or right to increase tempo; down or left to decrease it. Use +/− for single steps. Space starts/stops, T taps tempo, and Up/Down adjust tempo while the app is active. Tap two or more times; the last six taps are averaged. A pause longer than 2.1 seconds starts a fresh tap sequence.

Beats sets the number of quarter-note pulses per bar (0 means no accent). Division adds 1–4 clicks per pulse. The first pulse has a higher pitch; subdivisions are quieter. Volume includes mute. Settings are remembered. Tempo and pattern changes restart the bar immediately. The app continues playing when another app is active, and stops when its window closes.

Audio clicks use AVAudioPlayerNode sample positions and a half-second scheduling horizon. The display follows playback completion and may lag audio by roughly the click length. Audio device switching and sleep/wake behavior need testing on real hardware. This first version does not include a tuner, clave patterns, or every KDM-3 function.

## Widget mode

Click the small widget icon beside fdm-3, or press Shift–Command–M, to switch to a 168 × 72 floating window that displays the tempo with a visible expand button. It stays above ordinary app windows, including while another app is active. Drag the background to move it. Playback continues when switching modes.

Click the expand button to return to the full window. Right-click the widget for Start/Stop, Tap Tempo, or Show Full fdm-3e. Shift–Command–M also returns to the full instrument. Keyboard shortcuts apply while a metronome window is focused; they are not system-wide shortcuts. Space overrides focused button activation and holding it does not repeatedly toggle playback.

## Homebrew distribution

There is no published tap or binary yet. Do not expect `brew install --cask fdm-3` to work.

After testing the app on your Mac:

1. Host the exact `dist/fdm-3-0.1.0.zip` file at an HTTPS URL (for example, a GitHub release).
2. Generate a cask using that URL:

   ```sh
   bash scripts/make-cask.sh https://YOUR-HOST/fdm-3-0.1.0.zip
   ```

3. Put the generated `dist/Casks/fdm-3.rb` in a GitHub repository named `homebrew-fdm-3` under its `Casks` folder.
4. Users can then run `brew install --cask YOUR-GITHUB-NAME/fdm-3/fdm-3`.

The archive targets the architecture of the Mac that builds it. An Intel build and Apple Silicon build require separate releases/cask architecture declarations, or a universal build. Local ad-hoc signing is sufficient for development. For smooth public distribution, sign with Developer ID and notarize with Apple **before** creating the release ZIP and generating its checksum. A downloaded, unnotarized build can be blocked by Gatekeeper; this project does not bypass that protection.

## Validation status

Source prepared on Linux, where Apple's SwiftUI/AVFoundation SDKs are unavailable. Native compilation, Swift tests, listening tests, and UI checks have not run here. `scripts/build.sh` compiles and packages the app on your Mac. Tests run separately with `swift test` using full Xcode, which provides XCTest; Command Line Tools alone may not include it. The included GitHub Actions workflow runs tests before building on a macOS runner.
