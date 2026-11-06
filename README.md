**English** · [Русский](README.ru.md) · [Українська](README.uk.md)

# DotaAccept

A small Windows tool for Dota 2 (AutoHotkey v2) that

- **accepts the "match found" window** for you, and **party invitations**;
- optionally **picks your hero** from your own priority list in the first pick round;
- optionally **notifies your phone** (via [ntfy](https://ntfy.sh)) that the match was found and accepted, or that it could not accept it;
- lives in the tray with a **settings window** (checkboxes, hero list), no config files to edit.

It works in the background and does not take over your mouse. It does not read or touch the game's memory.

## How it works

Dota 2 started with the launch option `-condebug` writes a plain-text `console.log`. The script reads that file and reacts to what the game itself reports (match found, party invite, the hero selection stage starting). To find a button it looks at the pixels of the Dota window, and the click is first **posted straight to the game window without moving your cursor**; only if the game does not confirm it, a real mouse click is made and the cursor goes back. If you are moving the mouse when the match is found, the script clicks for real at once, because a silent click did not go through at such moments. Every action is written to `dota_log.txt` (in the language you chose, see [Language](#language)).

The client language does not matter: the script reads internal message names and recognises screens by icons, and hero names are English in the Russian and Ukrainian clients too.

## Install

1. Install **[AutoHotkey v2](https://www.autohotkey.com/)** (64-bit Windows).
2. Download these files into one folder (not Program Files): `DotaAccept.ahk`, `lang.tsv`, `heroes_map.txt`, `myheroes_tpl.txt`.
3. In Steam: right-click **Dota 2 → Properties → Launch Options** and enter

   ```
   -condebug
   ```

   (keep your other options, e.g. `-novid -condebug`). Restart Dota 2.
4. Double-click `DotaAccept.ahk`. It waits while Dota is closed and arms itself when Dota starts. On first run it adds itself to Windows startup (switch it off in the settings).

If Dota is running without the launch option, the tray icon changes to the "pause" symbol and the script **reminds you**: a Windows notification at every Dota start, repeated every 10 minutes while the problem lasts. The text says whether Steam has no such option for the current account, or it is set but this Dota was started around it (it restarted itself, or was not started with the Play button).

Launch options are stored **per Steam account**: if you use several accounts, add `-condebug` for each of them. Optionally the script can do it for you: Settings → General → "Launch options in Steam" adds `-condebug` to the *other* Steam accounts of this PC (only accounts Steam is not running under at that moment; a copy `localconfig.vdf.bak_dotaaccept` is left next to the edited file). Further flags, e.g. `-novid`, can be listed in `dota_accept.ini`, section `[steam]`, `flags=-novid -condebug`. It is off by default and it edits Steam's own file `userdata\<id>\config\localconfig.vdf`, so it is at your own risk.

The account you are logged in with is held in memory by Steam, so it can only be edited while Steam is closed. When the script starts (Dota not running) and this account has no `-condebug`, a window offers to do it: the script closes Steam (`steam.exe -shutdown`), writes the option and starts Steam again, which takes about half a minute. "Not now" shows the usual reminder, "Do not ask again" switches the window off. The same is available any time as the button "Add -condebug now (restarts Steam)" in Settings → General. Nothing is done while Dota is running.

## Settings window

Right-click the tray icon → **Settings…** (or double-click it).

- **General:** auto-accept of matches and party invites, phone notifications (copy the topic, send a test), start with Windows, open the log, interface language.
- **Auto-pick:** switch on, delay, and the **hero list**: tick heroes, set their order with ▲ ▼. `Ctrl+Alt+P` pauses everything.
- **Steam accounts:** launch options for other accounts and your Dota settings profile (see [Several Steam accounts](#several-steam-accounts)).

The tray icon is the game's own icon when all is well, and AutoHotkey's built-in "II" when paused or when something is wrong (hover to read why: launch option missing, Dota's log silent for 5+ minutes, …).

## Language

The interface (settings window, tray menu, messages, phone notifications and the log) comes in **English, Russian and Ukrainian**. On the first start the language follows Windows: Russian or Ukrainian Windows gets that language, anything else gets English. To change it, open Settings → General → *Language / Язык / Мова*: the script restarts itself and reopens the settings in the new language. The choice is kept in `dota_accept.ini` (`[options]`, `lang = auto | ru | en | uk`).

All texts live in `lang.tsv` next to the script: one line per text, with the Russian, English and Ukrainian versions separated by tabs. It is a plain text file, so a translation can be fixed (or a language added) without programming; the translations were not checked by native speakers, so corrections are welcome. If `lang.tsv` is missing the script still works, in English.

## Several Steam accounts

Launch options and Dota's settings are both stored **per Steam account**. If you use several accounts on one PC, the *Steam accounts* tab of the settings helps:

- **Launch options** — adds `-condebug` to the other accounts and, on request, to the current one (details in [Install](#install)).
- **My Dota settings (profile)** — *Save settings of this account* copies the settings files of Dota (keys, interface, video, hero grid, item builds; **not** statistics, friends or voice bans) from the account you are logged in with into `profile\` next to the script. While you play under that account the profile refreshes itself whenever Dota closes. When Steam moves to an account that is **new to the script** (accounts that already exist when the feature first runs do not count), the script offers to transfer the profile into it, switch Steam Cloud off for Dota (so your settings do not end up in that account's cloud) and write the launch options. Steam is closed and started again for this, because it holds that account's files in memory; nothing is done while Dota is running. Replaced files are kept in `bak_profile\`. The same is available any time as the button *Transfer the profile to this account*. If switching Steam Cloud off fails, the script says so and shows the manual steps (Steam → Dota 2 → Properties → General).

`profile\` and `bak_profile\` hold your own settings, so they are listed in `.gitignore`.

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

`DotaAccept.ahk` (the script), `lang.tsv` (all interface texts in Russian, English and Ukrainian), `heroes_map.txt` (hero names and grid order, generated from the game), `myheroes_tpl.txt` (template of the "MY HEROES" label), `tools/build_hero_map.py` (regenerates the map). Created at run time next to the script: `dota_accept.ini` (settings, private topic), `dota_log.txt`, `profile/` and `bak_profile/` (your Dota settings profile and replaced files), `snapshots/` (last 12 pick-screen frames for debugging).

## Disclaimer

An unofficial hobby tool, not affiliated with Valve. It does not read or modify game memory and does not inject anything: it reads the text log the game writes, looks at screen pixels and posts mouse events to the game window. **Automation can still be against the rules of a service or tournament; Valve's position on it is not something this project can promise, and hero auto-pick (an action inside the game) is more sensitive than accepting a match.** Auto-pick is therefore off by default. **Use at your own risk.**
