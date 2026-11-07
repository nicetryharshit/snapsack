# SnapSack

Carry screenshots on your cursor, system-wide on macOS. Inspired by
[@rrrima_'s thread](https://x.com/rrrima_/status/2118562181713195251): the cursor is the one thing that's in
every app, so it's the right place to keep things that don't belong to any app yet.

https://github.com/user-attachments/assets/4d9b88c8-8367-4c74-95a1-3f958166ce35

## Features

- **Carry screenshots on the cursor.** Capture with the shortcut and the cards ride the pointer as a stack, holding up to 4 to 8 (you choose in Settings).
- **Drop anywhere.** Double-click to drop one card where you clicked, or several at once, fanned out in the air.
- **Fan and pick.** Click a fanned card or press 1–8 to drop it. Drag any card out of the fan to put it wherever you let go.
- **Folders.** Drop onto a folder in Finder to save the screenshot inside it. Drop onto a Finder window's background to save it in that window's folder.
- **Toss and undo.** Shake to let the whole hand go, and ⌘Z brings back the last drop or toss.
- **Esc your way.** Put away the newest card, clear the hand, close only the fan, or pass Esc through to the app (Settings › Controls).
- **Sounds.** Quiet sounds for capture, drop, toss and the fan. Turn them off in Settings › General.
- **Settings.** Shortcut, clipboard restore, how long drops are kept, open at login, card size, distance from the cursor, animation speed, Reduce Motion, tilt, and fan lift. The version is shown at the bottom.
- **Drops folder.** Dropped screenshots are kept for a week so pasted file paths keep working. The menu has **Show Drops Folder**.
- **Menu bar only.** No Dock icon.

## Controls

| | |
|---|---|
| **⌃⌥S** (default) | Drag over anything on screen (Space switches to window mode). The screenshot joins your hand and rides your cursor. Press it again for more, up to 8 (a ninth replaces the oldest). |
| **Double-click** | With one card, it floats to where you clicked, then it's pasted and your clipboard is put back. With several, they fan out in the air around the click. |
| **Click a card** | In the fan: that card floats to the field and pastes, and the rest go back on the cursor. Click empty space to put them all back. |
| **Shake** | Let the whole hand go. |
| **Esc** | Set in Settings › Controls. By default it puts away the newest card (closing the fan first if it's open). It can also clear the whole hand, close only the fan, or pass through to the app. |
| **1–8** | In the fan, picks that numbered card, the same as clicking it. |
| **Drag** a card in the fan | Drops it wherever you let go, not where the fan opened. SnapSack clicks there first so the caret lands, so releasing on a button presses it. Esc during the drag puts the card back in the fan. |
| **⌘Z** | Puts back the last dropped or tossed screenshots. The menu has **Undo Last Drop or Toss** too. It can't take back a paste that already landed, and a file saved to a folder stays there. |

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
5. Optional: open **Settings…** (General) and turn on **Open at login**.

Because you build it on your own Mac, macOS doesn't block it. If you download a copy from somewhere else, you may
need to right-click it and choose **Open** the first time.

## Settings

Open **Settings…** from the menu bar (⌘,). It has three tabs, and every change applies straight away.

- **General**: the screenshot shortcut (click **Record**, then press the combination; it needs ⌘, ⌃ or ⌥, and Esc cancels), whether your clipboard is put back after a paste, how long dropped files are kept (1, 7 or 30 days), whether SnapSack opens at login, and whether sounds play.
- **Controls**: what Esc does while you hold screenshots (put away the newest, clear the whole hand, close only the fan, or pass through to the app, which then gets Esc as usual), shake to toss and its sensitivity, how many screenshots you can hold (4 to 8), card size, and how far cards hang from the cursor (close, medium or far).
- **Animation**: animate cards on or off, Reduce motion (follows macOS by default), speed (0.5× to 2×), tilt (off, subtle or full), and whether the card under the pointer lifts in the fan.

**Reset All to Defaults** puts everything back, the shortcut included. Choices are saved in UserDefaults.

Run `swift test` to check the shake recognition for each sensitivity.

## Build

Needs macOS 14+ and Xcode or the command line tools (`xcode-select --install`).

```
./scripts/snapsack.sh run        # build SnapSack.app, quit any old copy, launch
./scripts/snapsack.sh install    # copy to ~/Applications (use this one for "Open at login")
./scripts/snapsack.sh icon       # redraw the app icon (pip3 install pillow)
```

You can also `open Package.swift` in Xcode, but build the app with the script so it gets a bundle, an icon and
a stable signature.

## Permissions

SnapSack asks for these the first time it needs them. You can review them later in System Settings › Privacy & Security.

- **Accessibility** (required). SnapSack uses it to see the double-click, Esc, the number keys and ⌘Z while it holds
  screenshots, to press ⌘V and click where you dropped, and to read what's under the pointer so a drop onto a Finder
  folder lands inside it. Without it, holding and dropping won't work.
- **Screen Recording** (required). Capture needs it so your selection contains other apps' pixels and not just the
  wallpaper. macOS usually wants SnapSack relaunched after you grant it.
- **Automation (Finder)** (asked when needed). To find the folder of the Finder window in front, SnapSack asks Finder
  over AppleScript. If you say no, a drop onto a Finder window's background won't go into that window's folder.
- **Login Items** (only for **Open at login**). macOS may ask you to approve SnapSack under System Settings › General › Login Items.

If either permission gets stuck, `./scripts/snapsack.sh reset-permissions` clears SnapSack's grants.

When a drop lands somewhere unexpected, SnapSack writes what it found under the pointer to
`~/Library/Application Support/SnapSack/finder-probe.log`. Include that file when you report it.

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
- Every tunable (size, follow easing, tilt, damping, fan size and curve) is in `Sources/SnapSack/Card.swift`, under `Tune`. The choices you can change are in `Sources/SnapSack/Settings.swift`.
- Shake sensitivity is set in Settings (Controls). Its presets are `ShakeSensitivity` in `Sources/SnapSack/Settings.swift`.

## Layout

```
Sources/SnapSack/
  SnapSackApp.swift     entry point
  AppDelegate.swift     menu bar item, shortcut switching, first-run welcome
  SettingsWindow.swift  the settings window (General, Controls, Animation) and shortcut recorder
  Shortcut.swift        the shortcut: key, modifiers, display, saving
  Settings.swift        every setting: its choices, defaults and saving
  HotKey.swift          global shortcut registration (no extra permission)
  Carrier.swift         the interaction: capture → hold → drop / fan / pick / toss / cancel
  Hand.swift            the cards you're holding: stack, trailing, fan, hit-testing, exits
  Card.swift            one screenshot's state, and all the tuning numbers
  CarryPanel.swift      the floating window that draws one card
  ClickTap.swift        event tap alive only while holding (double-click, fan clicks, drags, Esc, 1–8, ⌘Z)
  FinderDrop.swift      what's under the pointer in Finder (folders, windows), via Accessibility
  Sounds.swift          the quiet sound effects, behind the Settings toggle
  ShakeDetector.swift   shake recognition
  Dropper.swift         paste + restore clipboard
  Capture.swift         system region picker
  Permissions.swift, LoginItem.swift, MenuBarIcon.swift
Resources/              Info.plist, AppIcon.png (ink-sketch icon), Sounds/*.wav
Tests/SnapSackTests/    shake recognition tests (run with swift test)
scripts/bundle.sh       builds and signs build/SnapSack.app
scripts/snapsack.sh     run / install / icon / reset-permissions / clean
tools/make_icon.py      draws the icon
```
