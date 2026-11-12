# Changelog

## 0.18.5

- Remap Shift + Up/Down to increase/decrease Gap.
- Use Shift + Left/Right for previous/next sound, wrapping through the available voices.
- Keep Shift shortcuts disabled in widget mode and during value drags.

## 0.18.4

- Remove double-click BPM typing and its inline editor; keep drag and keyboard adjustment.
- Add A to toggle first-beat Accent in the main window and widget, with one toggle per press.
- Suppress the shortcut while editing or dragging a value and show it in the Accent tooltip.

## 0.18.3

- Keep the Gap-off symbol at the same full theme color as the other Gap options.
- Fill every silent widget beat on the lower half, whether accented or not.

## 0.18.2

- Keep accented beats solid accent color while current, replacing the two-color split in both views.
- Preserve current-beat colors on other beats and the widget’s silent-gap half-fills.

## 0.18.1

- Replace the blended active-accent gradient with a crisp split: accent above, current-beat color below.
- Apply the split in both windows while preserving silent-gap half-fills and outlined upcoming beats.

## 0.18.0

- Add Blue, Everforest (dark/medium), and Zenwritten (dark) using their original Vim/Neovim palettes.
- Apply each new palette to the main view, widget, accents, gradients, and themed Dock icon.
- Keep Default first and alphabetize the remaining themes; document palette sources.

## 0.17.1

- Give Default a coral first-beat/Play accent (#FF8370) and blue current beat (#70A5FF), including its bundled and themed icons.
- Remove GitHub Light and Monokai; migrate their saved selections to PaperColor Light and Dracula respectively.

## 0.17.0

- Add 1/1 and 1/2 note modes: click every four or two beats while all visual beats continue.
- Keep note spacing continuous across odd meters and gap bars, with live changes at the next beat.
- Preserve existing subdivision preferences and extend the drag selector to the new note values.

## 0.16.11

- Reduce the main window’s width and horizontal control spacing while retaining the four-beat alignment and text sizes.
- Limit the meter to 1–7 beats in settings, shortcuts, and audio playback.
- Restore saved 8- or 9-beat meters as 7 while preserving Accent.

## 0.16.10

- Align the main metrics to a four-beat reference: BPM over beat one, Subdivision between beats two and three, Gap over beat four.
- Keep metric positions fixed when changing meter, with other beat counts centered below.

## 0.16.9

- Make the widget speaker always visible and clickable to mute or restore the previous volume.
- Match the speaker and expand symbols’ rendered height and center them in identical button frames.

## 0.16.8

- Balance the main control column’s icon sizes and use a consistent medium stroke weight, including a larger widget-mode symbol.

## 0.16.7

- Align widget tempo, beats, and controls in explicit fixed-width groups with balanced spacing.
- Keep the beat row stationary across two- and three-digit tempos, mute changes, and beat counts.

## 0.16.6

- Add a neutral mute indicator beside the widget’s expand control, with a reserved slot to keep its layout stable.
- Keep normal theme colors and accent gradients during widget gaps; distinguish silence using the existing half-fills.

## 0.16.5

- Half-fill current and completed widget gap beats: upper half for the accented first beat, lower half otherwise.
- Disable Shift + arrow shortcuts for meter and Gap in widget mode, including menu commands.
- Restore those shortcuts automatically on return to the main window.

## 0.16.4

- Use the theme’s Gap color for all widget beat circles during silent bars, preserving filled progress and outlined upcoming beats.
- Keep normal widget colors when only muted, and restore them when audible bars resume.

## 0.16.3

- Show the third beat as current in the Dock and bundled app icons.
- Color the first beat with the theme accent only when it differs from the current-beat color; otherwise keep it neutral.

## 0.16.2

- Keep Random's chosen audible run hidden in the bar preview and accessibility text; show only an unknown-run symbol and silent-bar progress.
- Blend accent and current-beat colors with a gradient when they coincide, in both windows.

## 0.16.1

- Keep the Gap value and label fixed at the selected setting during silence.
- Reserve an unconditional slot for the bar preview so toggling Gap never shifts the other rows.

## 0.16.0

- Show a small neutral bar-sequence row below the beat indicators when Gap is enabled.
- Mark the current bar brightest, other audible bars softer, and silent bars faint.
- Follow actual audio-cycle positions, including the chosen audible run in Random mode.
- Keep the widget compact and preserve existing Gap controls and countdown.

## 0.15.2

- Preview beat-count and accent edits immediately in both windows while preserving audio timing.
- Add Shift + Left/Right to step Gap through Off, 1, 2, 4, and Random.
- Replace the Gap-off dash with a smaller slashed-circle symbol.
- Enlarge the widget and all its contents uniformly by 15%.

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

