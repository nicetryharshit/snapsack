# SnapSack

Carry a screenshot on your cursor, system-wide on macOS. Inspired by
[@rrrima_'s thread](https://x.com/rrrima_/status/2118562181713195251): the cursor is the one thing that's in
every app, so it's the right place to keep things that don't belong to any app yet.

<video src="docs/demo.mp4" controls muted width="100%"></video>

[Watch the demo](docs/demo.mp4)

| | |
|---|---|
| **⌃⌥S** (default) | Drag over anything on screen (Space switches to window mode). The screenshot joins your hand and rides your cursor. Press it again for more, up to 8 (a ninth replaces the oldest). |
| **Double-click** | With one card, it floats to where you clicked, then it's pasted and your clipboard is put back. With several, they fan out in the air around the click. |
| **Click a card** | In the fan: that card floats to the field and pastes, and the rest go back on the cursor. Click empty space to put them all back. |
| **Shake** | Let the whole hand go. |
| **Esc** | Closes the fan, or puts away the newest card. |

It lives in the menu bar (no Dock icon). Dropped screenshots are kept in
`~/Library/Application Support/SnapSack/Drops` for a week so a pasted file path keeps working, then pruned.

## Install

SnapSack isn't signed or notarized by Apple, so you build it yourself on your Mac. It takes a minute.

1. Install the command line tools if you don't have them: `xcode-select --install`
2. In this folder, run:
   ```
   ./scripts/snapsack.sh install
   ```
   This builds `SnapSack.app` and copies it to `~/Applications`.
3. Open SnapSack from Spotlight or Finder. Its icon appears in the menu bar.
4. Grant Accessibility and Screen Recording when asked (System Settings > Privacy & Security).
5. Optional: open its menu and turn on **Open at Login**.

Because you build it on your own Mac, macOS doesn't block it. If you download a copy from somewhere else, you may
need to right-click it and choose **Open** the first time.

## Settings

Open **Settings…** from the menu bar (⌘,). Click **Record**, then press the combination you want. It needs ⌘, ⌃
or ⌥; Esc cancels. If macOS or another app already uses the combination, SnapSack keeps the old one and tells you.
**Reset to Default** goes back to ⌃⌥S. The choice is saved in UserDefaults under `screenshotShortcut`.

## Build

Needs macOS 14+ and Xcode or the command line tools (`xcode-select --install`).

```
./scripts/snapsack.sh run        # build SnapSack.app, quit any old copy, launch
./scripts/snapsack.sh install    # copy to ~/Applications (use this one for "Open at Login")
./scripts/snapsack.sh icon       # redraw the app icon (pip3 install pillow)
```

You can also `open Package.swift` in Xcode, but build the app with the script so it gets a bundle, an icon and
a stable signature.

## Permissions

SnapSack asks for two things the first time you use it:

- **Accessibility**: to catch the double-click and Esc while a screenshot is on the cursor, and to press ⌘V.
- **Screen Recording**: so your selection contains other apps' pixels and not just the wallpaper.

macOS usually wants the app relaunched after you grant Screen Recording. If either gets stuck,
`./scripts/snapsack.sh reset-permissions` clears SnapSack's grants.

## How it feels (and where to tune it)

- The thumbnail is a small, fixed-size card (same area every time; the shape follows the screenshot). It glides
  after the cursor with a soft ease and tilts a few degrees at most when you move fast. It slides to the other
  side of the cursor near screen edges.
- Several cards hang as a tight accordion: the newest is on top, and each one behind sits a fixed few points
  further back, catching up with a slight delay. The tail is bounded, so it doesn't stretch out when you move fast.
  In the fan the cards grow to about twice their size so you can tell them apart.
- Toss is a short drift and fade. Drop is a quarter-second float into the field, then the paste.
- Double-click always drops. SnapSack doesn't check whether the field accepts images, so if the paste does nothing
  there, the card is still gone.
- Every tunable (size, follow easing, tilt, damping, fan size and curve, max cards) is in `Sources/SnapSack/Card.swift`, under `Tune`.
- Shake sensitivity is in `Sources/SnapSack/ShakeDetector.swift` (`minTravel`, `window`, `reversalsNeeded`).

## Layout

```
Sources/SnapSack/
  SnapSackApp.swift     entry point
  AppDelegate.swift     menu bar item, shortcut switching, first-run welcome
  SettingsWindow.swift  the settings window and shortcut recorder
  Shortcut.swift        the shortcut: key, modifiers, display, saving
  HotKey.swift          global shortcut registration (no extra permission)
  Carrier.swift         the interaction: capture → hold → drop / fan / pick / toss / cancel
  Hand.swift            the cards you're holding: stack, trailing, fan, hit-testing, exits
  Card.swift            one screenshot's state, and all the tuning numbers
  CarryPanel.swift      the floating window that draws one card
  ClickTap.swift        event tap alive only while holding (double-click, fan clicks, Esc)
  ShakeDetector.swift   shake recognition
  Dropper.swift         paste + restore clipboard
  Capture.swift         system region picker
  Permissions.swift, LoginItem.swift, MenuBarIcon.swift
Resources/              Info.plist, AppIcon.png (ink-sketch icon)
scripts/bundle.sh       builds and signs build/SnapSack.app
scripts/snapsack.sh     run / install / icon / reset-permissions / clean
tools/make_icon.py      draws the icon
```
