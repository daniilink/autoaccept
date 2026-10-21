**English** · [Русский](README.ru.md) · [Українська](README.uk.md)

# DotaAccept

Auto-accepts the **Dota 2 match found** window and **party invitations** on Windows, and can notify your phone. It works in the background, does not take over your mouse and does not touch the game's memory.

## How it works

Dota 2 started with the launch option `-condebug` writes a plain-text `console.log`. The script reads that file and reacts to what the game itself reports:

| Event in the log | What the script does |
|---|---|
| ready-check (match found) | finds the ACCEPT button and clicks it |
| party invitation | clicks ACCEPT in the popup |
| the game confirms your click (`k_EMsgGCReadyUp`, `k_EMsgGCPartyInviteResponse`) | stops; if there is no confirmation, tries the next candidate |

The click is first sent **straight to the game window without moving your cursor**. Only if the game does not confirm it, a real mouse click is made and the cursor goes back to where it was. Every action is written to `dota_log.txt` (in English).

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

On first run the script adds itself to Windows startup (turn it off in the tray menu). If the launch option is missing, the script shows **one quiet Windows notification** with the fix (at most three times in total) and the tray icon changes to the "pause" symbol.

## Use

- `Ctrl+Alt+P` — pause / resume.
- **Tray icon** (right click): auto-accept of matches on/off, auto-accept of party invites on/off, phone notifications on/off, copy the ntfy topic, send a test notification, start with Windows, open the log, exit.
- **The tray icon tells you the state:** the green **H** means armed; the **II** (pause) means paused or something is wrong. Hover to read the reason (for example, Dota was started without `-condebug`, or Dota's log has been silent for 5+ minutes).
- `dota_log.txt` (next to the script) — every action with timings, e.g. `ACCEPTED match no mouse … Dota confirmed in 125 ms`, plus an `alive` line every 15 minutes.

## Phone notifications (optional)

The script can send two kinds of notifications through **[ntfy](https://ntfy.sh)**:

- **Match found and accepted.**
- **Match found, auto-accept did not work — accept it yourself!** (if nothing was accepted within 5 seconds).

Set up: install the ntfy app, choose **Subscribe to topic**, and paste the topic. The topic is created randomly on first run and kept in `dota_accept.ini`; use the tray item **Copy ntfy topic**. Treat it like a password: on the public server anyone who knows the topic can read and write it. The public ntfy.sh server has a daily message quota, which is why only two notifications per match are sent.

## Limits — please read

- Tested on **2560×1440**, windowed/borderless, English client. Button positions are stored as fractions of the window, so other resolutions should work, but other aspect ratios are untested.
- The script finds buttons by reading screen pixels, so **it cannot see a popup while another window covers Dota** (it keeps retrying party invites for 40 seconds, so they are accepted once Dota is visible again).
- Without `-condebug` the script cannot see matches at all (see Install).
- The script was developed on one machine; expect rough edges.

## Disclaimer

An unofficial hobby tool, not affiliated with Valve. It does not read or modify game memory and does not inject anything: it reads the text log the game writes and posts mouse events to the game window. Automation can still be against the rules of a service or tournament, and Valve's position is not something this project can promise. **Use at your own risk.**
