**English** · [Русский](README.ru.md) · [Українська](README.uk.md)

# DotaAccept

A small Windows tool for Dota 2 (AutoHotkey v2) that

- **accepts the "match found" window** for you, and **party invitations**;
- optionally **picks your hero** from your own priority list in the first pick round;
- optionally **notifies your phone** (via [ntfy](https://ntfy.sh)) that the match was found and accepted, or that it could not accept it;
- lives in the tray with a **settings window** (checkboxes, hero list), no config files to edit.

It works in the background and does not take over your mouse. It does not read or touch the game's memory.

## How it works

Dota 2 started with the launch option `-condebug` writes a plain-text `console.log`. The script reads that file and reacts to what the game itself reports (match found, party invite, the hero selection stage starting). To find a button it looks at the pixels of the Dota window, and the click is first **posted straight to the game window without moving your cursor**; only if the game does not confirm it, a real mouse click is made and the cursor goes back. Every action is written to `dota_log.txt` (the interface and the log are in English).

The client language does not matter: the script reads internal message names and recognises screens by icons, and hero names are English in the Russian and Ukrainian clients too.

## Install

1. Install **[AutoHotkey v2](https://www.autohotkey.com/)** (64-bit Windows).
2. Download these files into one folder (not Program Files): `DotaAccept.ahk`, `heroes_map.txt`, `myheroes_tpl.txt`.
3. In Steam: right-click **Dota 2 → Properties → Launch Options** and enter

   ```
   -condebug
   ```

   (keep your other options, e.g. `-novid -condebug`). Restart Dota 2.
4. Double-click `DotaAccept.ahk`. It waits while Dota is closed and arms itself when Dota starts. On first run it adds itself to Windows startup (switch it off in the settings).

If the launch option is missing, the script shows **one quiet Windows notification** with the fix (at most three times) and the tray icon changes to the "pause" symbol.

## Settings window

Right-click the tray icon → **Settings…** (or double-click it).

- **General:** auto-accept of matches and party invites, phone notifications (copy the topic, send a test), start with Windows, open the log.
- **Auto-pick:** switch on, delay, and the **hero list**: tick heroes, set their order with ▲ ▼. `Ctrl+Alt+P` pauses everything.

The tray icon is the game's own icon when all is well, and AutoHotkey's built-in "II" when paused or when something is wrong (hover to read why: launch option missing, Dota's log silent for 5+ minutes, …).

## Hero auto-pick (off by default)

When the hero selection stage starts, the script waits (15 s by default, so you keep some time on the clock), then reads the screen and picks **the first hero in your list that is not banned and not taken**. It clicks the card and then LOCK IN, and checks the result on the screen:

- if clicking a card does not select it (gray/taken), it moves on to the next hero;
- if a hero is selected but LOCK IN stays dim (someone in your team already picked, the second round has not started), it **waits until the button lights up** and locks the same hero in;
- if the hero card turns gray or banned while waiting, it takes the next one;
- it only starts new attempts until about second 24 of the stage (the first round's timer is 0:25); `deadline_ms` in `dota_accept.ini` changes it;
- if someone is at the PC (mouse or keyboard moved in the last 6 s) it waits instead of interfering.

Two screens are supported, detected automatically: the **standard grid** (sort: *Attributes*) uses your hero list; the **"MY HEROES" strip** (sort: *Custom Layout*, English client only) takes the strip left to right. Hero positions are computed from `heroes_map.txt`, which `tools/build_hero_map.py` builds from Dota's own files (read-only; run it again after a patch that adds heroes; needs Python).

## Phone notifications (optional)

Install the ntfy app, subscribe to your topic (settings → "Copy ntfy topic"). Two messages per match at most: **"Match found and accepted"** and **"Match found, auto-accept did not work — accept it yourself!"** (nothing accepted within 5 s). The topic is generated randomly on first run and kept in `dota_accept.ini`; treat it like a password. The public ntfy.sh server has a daily message quota, which is why so few messages are sent.

## Limits — please read

- Developed on **2560×1440** and checked on one more laptop (standard hero grid, bot matches). Positions are stored as fractions of the window. **Auto-pick supports 16:9 windows only**; other proportions are refused (see the log).
- The script finds buttons by reading screen pixels, so it **cannot see a popup while another window covers Dota**; use "Borderless window" rather than exclusive fullscreen if the screen reads as black.
- Not verified live yet: the gray look of a hero taken by the other team (the script also verifies picks through the game's own reaction), the party-invite button at other resolutions, the "MY HEROES" strip beyond the author's account, and the on-screen fallback that accepts a re-queued match when the log is silent.
- Without `-condebug` the script cannot see matches at all.
- This is a hobby project developed on one machine; expect rough edges.

## Files

`DotaAccept.ahk` (the script), `heroes_map.txt` (hero names and grid order, generated from the game), `myheroes_tpl.txt` (template of the "MY HEROES" label), `tools/build_hero_map.py` (regenerates the map). Created at run time next to the script: `dota_accept.ini` (settings, private topic), `dota_log.txt`, `snapshots/` (last 12 pick-screen frames for debugging).

## Disclaimer

An unofficial hobby tool, not affiliated with Valve. It does not read or modify game memory and does not inject anything: it reads the text log the game writes, looks at screen pixels and posts mouse events to the game window. **Automation can still be against the rules of a service or tournament; Valve's position on it is not something this project can promise, and hero auto-pick (an action inside the game) is more sensitive than accepting a match.** Auto-pick is therefore off by default. **Use at your own risk.**
