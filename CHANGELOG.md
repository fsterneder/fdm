# Changelog

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
