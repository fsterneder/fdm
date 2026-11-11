# fdm-3
Vibe coded metronome based on the KDM-3

## App: Metronom

A native macOS 13+ metronome inspired by the feel of a dedicated desktop instrument. Independent project; no Korg branding or sound samples.

## First run on your Mac

1. Put this folder in Downloads and open Terminal (Applications → Utilities → Terminal).
2. Install Apple's free Command Line Tools if you do not have them:

   ```sh
   xcode-select --install
   ```

   Wait for the installation to finish. Full Xcode is optional. A Swift 5.9+ toolchain and macOS SDK are required; if the installed tools are older, update them in System Settings → Software Update or install current Xcode.

3. In Terminal type `cd ` (including the space), drag the Metronom folder onto Terminal, and press Return.
4. Run:

   ```sh
   bash scripts/build.sh
   open dist/Metronom.app
   ```

The build script runs the tests, compiles for your Mac's architecture, creates an app bundle, signs it locally, and makes a ZIP in `dist`. It does not install dependencies or change your security settings. You can move the app into Applications using Finder.

## Controls

Drag the dial up or right to increase tempo; down or left to decrease it. Use +/− for single steps. Space starts/stops, T taps tempo, and Up/Down adjust tempo while the app is active. Tap two or more times; the last six taps are averaged. A pause longer than 2.1 seconds starts a fresh tap sequence.

Beats sets the number of quarter-note pulses per bar (0 means no accent). Division adds 1–4 clicks per pulse. The first pulse has a higher pitch; subdivisions are quieter. Volume includes mute. Settings are remembered. Tempo and pattern changes restart the bar immediately. The app continues playing when another app is active, and stops when its window closes.

Audio clicks use AVAudioPlayerNode sample positions and a half-second scheduling horizon. The display follows playback completion and may lag audio by roughly the click length. Audio device switching and sleep/wake behavior need testing on real hardware. This first version does not include a tuner, clave patterns, or every KDM-3 function.

## Homebrew distribution

There is no published tap or binary yet. Do not expect `brew install metronom` to work.

After testing the app on your Mac:

1. Host the exact `dist/Metronom-0.1.0.zip` file at an HTTPS URL (for example, a GitHub release).
2. Generate a cask using that URL:

   ```sh
   bash scripts/make-cask.sh https://YOUR-HOST/Metronom-0.1.0.zip
   ```

3. Put the generated `dist/Casks/metronom.rb` in a GitHub repository named `homebrew-metronom` under its `Casks` folder.
4. Users can then run `brew install --cask YOUR-GITHUB-NAME/metronom/metronom`.

The archive targets the architecture of the Mac that builds it. An Intel build and Apple Silicon build require separate releases/cask architecture declarations, or a universal build. Local ad-hoc signing is sufficient for development. For smooth public distribution, sign with Developer ID and notarize with Apple **before** creating the release ZIP and generating its checksum. A downloaded, unnotarized build can be blocked by Gatekeeper; this project does not bypass that protection.

## Validation status

Source prepared on Linux, where Apple's SwiftUI/AVFoundation SDKs are unavailable. Native compilation, Swift tests, listening tests, and UI checks have not run here. `scripts/build.sh` performs compilation and tests on your Mac; the included GitHub Actions workflow does the same on a macOS runner when uploaded to a repository.
