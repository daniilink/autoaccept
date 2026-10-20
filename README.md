**English** · [Русский](README.ru.md) · [Українська](README.uk.md)

# DotaAccept

Auto-accepts the **Dota 2 match found** window and **party invitations** on Windows. It works in the background, does not take over your mouse and does not touch the game's memory.

## How it works

Dota 2 started with the launch option `-condebug` writes a plain-text `console.log`. The script reads that file and reacts to what the game itself reports:

| Event in the log | What the script does |
|---|---|
| ready-check (match found) | finds the ACCEPT button and clicks it |
| party invitation | clicks ACCEPT in the popup |
| the game confirms your click (`k_EMsgGCReadyUp`, `k_EMsgGCPartyInviteResponse`) | stops; if there is no confirmation, tries the next candidate |

The click is first sent **straight to the game window without moving your cursor**. Only if the game does not confirm it, a real mouse click is made and the cursor goes back to where it was. Every action is written to `dota_log.txt`.

The game language does not matter: the script reads internal message names, not text on screen.

## Install

1. Install **[AutoHotkey v2](https://www.autohotkey.com/)** (Windows).
2. Download `DotaAccept.ahk` from this repository.
3. In Steam: right-click **Dota 2 → Properties → Launch Options** and enter

   ```
   -condebug
   ```

   (keep your other options, e.g. `-novid -condebug`). Restart Dota 2.
4. Double-click `DotaAccept.ahk`. That is all: it waits while Dota is closed and arms itself when Dota starts.

On first run the script adds itself to Windows startup. Turn it off in the tray icon menu.

## Use

- `Ctrl+Alt+P` — pause / resume.
- Tray icon, right click — pause, exit, autostart on/off.
- `dota_log.txt` (next to the script) — every action with timings, e.g. `ПРИНЯЛ матч без мыши … дота подтвердила за 125 мс` ("accepted the match without the mouse … the game confirmed in 125 ms"). A heartbeat line `жив` ("alive") is written every 15 minutes. The log messages are in Russian.

## Limits — please read

- Tested on **2560×1440**, windowed/borderless, English client. Button positions are stored as fractions of the window, so other resolutions should work, but other aspect ratios are untested.
- Without `-condebug` the script falls back to an older screen-colour mode. It needs manual calibration (hotkeys are listed at the top of the `.ahk`) and is much less reliable. Use `-condebug`.
- The comments inside the script are in Russian.

## Disclaimer

An unofficial hobby tool, not affiliated with Valve. It does not read or modify game memory and does not inject anything: it reads the text log the game writes and posts mouse events to the game window. Automation can still be against the rules of a service or tournament, and Valve's position is not something this project can promise. **Use at your own risk.**
