# Changelog

## 0.15.1

- Use regular-weight BPM numerals in the main view, widget, and inline editor.
- Show Gap as a dash when off, numbers for fixed intervals, and shuffle arrows for Random.

## 0.15.0

- Add a third main metric for Gap, draggable through Off, 1, 2, 4, and Random audible bars.
- Use a palette-specific Gap accent; show the silent-bar countdown in its own slot.
- Replace Tap in the right control column with a first-beat Accent toggle.
- Move Tap beside Volume in Settings; keep Beats and Gap Length in Settings.

## 0.14.0

- Keep the audio clock running when tempo, sound, accent, or subdivision changes; apply edits on the next beat.
- Apply meter and gap changes at the next bar without resetting the beat count.
- Render clicks directly on the audio thread so UI activity cannot drain a queued buffer.
- Drive beat lights and gap countdown from the configuration actually playing.
- Add portable transport regression tests.

## 0.13.0

- Implement the approved balanced right-hand control column: Widget, Settings, Tap, Speaker, Play.
- Center the metric and beat rows together and preserve the pre-enlargement mockup's proportions.
- Slim the widget to 40 points, align the bpm unit to the number, tighten grouping, and use a flat expand control.
- Keep widget BPM read-only and preserve accent coloring and bar-based gaps.
- Rename the package, app, executable, archive, and cask to fdm while retaining the bundle identifier and saved settings.

## 0.12.0

- Adopt the approved logo-free layout with larger metric values, spaced beat lights, and four flat bottom controls.
- Keep the original inward widget arrows in the upper-right native toolbar.
- Color the first beat with the Play accent when Accent is enabled, in both main and widget views.
- Measure Gap Length and its countdown in whole bars (1–8); preserve subdivision-aligned transitions.
- Migrate saved beat-length gaps to whole bars, rounded up, without reinterpreting them on later launches.

## 0.11.0

- Make the widget BPM read-only; BPM dragging remains available in the main window.

- Separate Accent Yes/No from Beats (1–9); migrate legacy No Accent to four beats with Accent off.
- Add Gap Length from 1–8 silent beats, independently of how often a gap occurs.
- Keep subdivisions muted for every silent beat and choose random audible runs once per cycle.
- Replace the main subdivision readout with remaining/total silent beats, then restore it after the gap.
- Persist both new settings and keep visual beat counting independent of accent.

## 0.10.2

- Reduce the main window from 376 to 308 points tall by tightening vertical spacing and the metric row.
- Keep large beat circles and 44-point playback/mute hit areas.
- Use flat speaker and Start/Stop controls, with playback accent on the foreground.
- Add a small bpm unit in the widget without increasing its dimensions.

## 0.10.1

- Remove the tempo slider and beat adjustment buttons.
- Make BPM and subdivision vertically draggable; choose Beats and Gap in Settings.
- Keep beat indicators read-only while preserving cumulative progress.
- Keep the logo neutral and use the accent background only during playback.
- Use double-click for optional BPM entry and request focus after the field attaches to its window.
- Reduce the widget to a single row of draggable BPM, beat progress, and the expand control.

## 0.10.0

- Adopt the modern interface: ordinary typography, equal-width tempo and subdivision/GAP fields, and prominent round beat lights.
- Keep completed beats filled and highlight the current beat; preserve the No Accent pulse.
- Replace the wheel with a slider and direct BPM scrubbing: drag up to increase, down to decrease; click to type.
- Preserve numeric entry, keyboard shortcuts, settings, sounds, and gap timing.
- Use the same scaled readout in the main window and floating widget.
- Replace the icon with the four-beat motif for every theme, with equal 100-pixel padding around an 824-pixel square tile.

## 0.9.4

- Match the mockup's animated metronome symbol: a tapered case with rounded corners and a round pendulum pivot.
- Keep the arm inside the case and retain beat-synchronized motion in both display sizes.

## 0.9.3

- Enlarge the tempo-wheel marker.
- Color the idle Start symbol and fdm-3 logo with the theme's playback accent.
- Keep active Stop filled with the accent color and regular buttons neutral.
- Replace subdivision notation with GAP during silent bars in both display sizes.

## 0.9.2

- Restore Default's green LCD, dark monochrome display ink, charcoal controls, and orange wheel pointer.
- Use a neutral logo and neutral regular controls across every theme; retain the active Start/Stop color.
- Fill beat indicators cumulatively through each bar in both the main window and widget.
- Keep the unaccented single indicator pulsing on each beat.

## 0.9.1

- Replace the icon with the approved LCD, left wheel, and four-button layout.
- Show two filled beat triangles and one empty triangle, with no numbers or labels.
- Keep controls neutral except active Stop; use a square Stop symbol.
- Use the same icon artwork for every theme in the Dock, and Default's sage LCD for Finder.
- Generate the bundle icon from the same drawing as the Dock icon.
- Remove tempo-wheel tick marks in both the app and icon.

## 0.9.0

- Define six consistent color roles for every theme: background, neutral, tempo, beat, playing beat, and action.
- Match the tempo wheel indicator to the tempo digits.
- Color the f/d/m/-/3 logo by tempo/beat/playing-beat/neutral/action.
- Use neutral inactive beat outlines and highlight only the current beat.
- Derive surfaces and borders from background and neutral; use the action role for all button highlights and Start/Stop.

## 0.8.4

- Enlarge the icon's metronome symbol and separate its pendulum from the base.
- Place the pendulum at three quarters of its rightward swing.
- Update the running Dock icon when the selected theme changes; keep Finder's icon Dracula.
- Resize icon images with sips at explicit pixel dimensions to avoid bitmap scaling and clipping.

## 0.8.3

- Simplify the icon to the LCD metronome symbol in Dracula purple and pink, with its pendulum leaning right.
- Generate the Finder icon with Apple's iconutil on every build and validate decoding.
- Load the source PNG directly for the running Dock icon and register the rebuilt bundle.

## 0.8.2

- Use neutral LCD colors for the animated metronome and subdivision notation.
- Thicken beat marker outlines in both window modes.
- Match the logo to the tempo color across themes.
- Replace the app icon with Dracula artwork.

## 0.8.1

- Match the approved LCD mockup's aspect ratio, digit proportions, label positions, and bottom-row symbols at both sizes.
- Group theme colors into tempo, beats, and supporting symbols, with neutral labels.
- Give every button the same finish except active Start/Stop.

## 0.8.0

- Give IDE/Vim themes distinct colors for tempo, beats, labels, markers, pendulum, notes, and gap status.
- Color related controls consistently; playback uses each theme's green or primary action color.
- Match the widget status light to the Start/Stop color.
- Keep Default's original hardware colors.

## 0.7.0

- Use one proportionally scaled LCD layout in both the main window and widget.
- Remove Voice from the LCD and its accessibility description.
- Include beat count, pendulum, subdivision note, and gap status in the widget.
- Align the bottom-row symbols and reduce the LCD height.
- Enlarge the widget slightly while keeping its controls outside the LCD.

## 0.6.0

- Compact the main window to its header, LCD, wheel, and four round controls.
- Place Tap, Settings, and widget controls in the header.
- Put beat up/down, mute, and themed Start/Stop beside the wheel.
- Move subdivision, gap, sound, theme, and volume into the Settings popover.
- Update the native app icon to match the four-button layout.

## 0.5.0

- Move the larger tempo wheel to the left.
- Stack circular beat controls on the right: up triangle above down triangle.
- Update the app icon to reflect the same hardware layout.
- Package the multi-resolution icon directly as an ICNS asset.

## 0.4.0

- Gap now sets how many audible bars play before exactly one silent bar.
- Add Random: each cycle chooses 1, 2, or 4 audible bars, then silences one bar.
- Keep whole-bar boundaries, sample timing, subdivisions, and No accent behavior.
- Reset random planning on transport and pattern changes.

## 0.3.0

- Add repeating gap practice: one audible bar, then 1, 2, or 4 silent bars.
- Move Division to the left and put Gap on the right; beat count stays on +/−.
- Keep playback and visual beat tracking running through silent bars.
- Show GAP in both LCD modes during silence.
- Use four-pulse gap bars when No accent is selected.
- Update app bundle and release archive version to 0.3.0 (build 4).

