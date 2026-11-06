#Requires AutoHotkey v2.0
#SingleInstance Force
; ──────────────────────────────────────────────────────────────────────
;  AUTO-ACCEPT FOR DOTA 2 MATCHES AND PARTY INVITES.
;
;  Runs while Dota is running; sleeps while Dota is closed.
;
;  HOW IT WORKS
;    Dota 2 started with the -condebug launch option writes a plain-text
;    console.log. The script reads it and reacts to what the game itself
;    reports: "match found", "party invite received". A click is confirmed by
;    the same log (Dota writes that the reply was sent), so a miss costs one
;    extra click, not a lost match. Without -condebug the script does nothing.
;
;  CLICKING
;    First as a message posted to the Dota window, without the mouse (the cursor
;    does not move). If that is not confirmed, a real mouse click is made and
;    the cursor goes straight back.
;
;  CONTROLS
;    Ctrl+Alt+P pauses. Tray icon menu: what to auto-accept (matches, party
;    invites), phone notifications, startup, log. Settings are kept in
;    dota_accept.ini, a record of what was clicked in dota_log.txt (both next
;    to the script).
; ──────────────────────────────────────────────────────────────────────

; ── interface language ───────────────────────────────────────────────
; Everything a person sees (menus, windows, messages, the log) goes through
; Tr("text"): the string in the source is the key, and its translation is looked
; up in lang.tsv next to the script (columns: Russian, English, Ukrainian). The
; language is chosen in the settings (ini: [options] lang = auto | ru | en | uk;
; auto follows the Windows language: Russian or Ukrainian, anything else is
; English). No file or no translation: the source text is shown, nothing breaks.
SRC_LANG := "en"                         ; the language the strings in this file are written in
LANGS := ["ru", "en", "uk"]              ; same order as the columns of lang.tsv
LANG_ITEMS := ["Auto", "Русский", "English", "Українська"]   ; lang-names
LANG_MAP := Map()
LANG_CODE := SRC_LANG
LANG_NOTE := ""
InitLang()

InitLang() {
    global SRC_LANG, LANGS, LANG_MAP, LANG_CODE, LANG_NOTE
    code := IniRead(A_ScriptDir . "\dota_accept.ini", "options", "lang", "auto")
    if !IndexOf(LANGS, code)
        code := WindowsLang()
    LANG_CODE := code
    if code = SRC_LANG
        return
    f := A_ScriptDir . "\lang.tsv"
    if !FileExist(f) {
        LANG_NOTE := "lang.tsv not found next to the script: texts stay in the source language"
        return
    }
    src := IndexOf(LANGS, SRC_LANG), col := IndexOf(LANGS, code)
    for ln in StrSplit(FileRead(f, "UTF-8"), "`n", "`r") {
        if ln = "" || SubStr(ln, 1, 1) = "#"
            continue
        p := StrSplit(ln, "`t")
        if p.Length < Max(src, col) || p[col] = ""
            continue
        k := LangUnesc(p[src])
        if !LANG_MAP.Has(k)           ; the same text in two rows: the first one wins
            LANG_MAP[k] := LangUnesc(p[col])
    }
}

; Windows language: 0419 is Russian, 0422 is Ukrainian, anything else is English.
WindowsLang() {
    id := Integer("0x" . SubStr(A_Language, 3))
    return id = 0x19 ? "ru" : id = 0x22 ? "uk" : "en"
}

Tr(s) {
    global LANG_MAP
    return LANG_MAP.Has(s) ? LANG_MAP[s] : s
}

; In lang.tsv a new line, a tab, a backslash and a space at the edge of a text
; are written as \n \t \\ \s.
LangUnesc(s) {
    if !InStr(s, "\")
        return s
    out := "", i := 1, n := StrLen(s)
    while i <= n {
        c := SubStr(s, i, 1)
        if c = "\" && i < n {
            d := SubStr(s, i + 1, 1)
            out .= d = "n" ? "`n" : d = "t" ? "`t" : d = "r" ? "`r" : d = "s" ? " " : d
            i += 2
        } else {
            out .= c
            i += 1
        }
    }
    return out
}

DOTA_EXE := "dota2.exe"
DOTA_WIN := "ahk_exe dota2.exe"
DOTA_POLL := 200         ; poll interval while Dota is running, ms
DOTA_IDLE := 2000        ; how often to check whether Dota has started, ms
; Lines in Dota's console.log that everything is based on. Compared with the
; closing parenthesis: "k_EMsgGCReadyUpStatus" contains "k_EMsgGCReadyUp",
; and without the parenthesis one would match the other.
CLOG_READY := "(k_EMsgGCReadyUpStatus)"   ; GC: a ready-check is in progress
CLOG_MINE := "(k_EMsgGCReadyUp)"          ; client: accepted (by us or by you)
CLOG_START := "(k_EMsgGCToClientSteamDatagramTicket)"  ; server assigned
; A party invite arrives as a subscription to an Invite object. The token must
; be EXACT: the closing line (CacheUnsubscribedJob) also contains
; "owner=<Invite:", and the script would click at nothing after a decline. The
; client's reply is a separate message; we use it to confirm that we hit.
CLOG_INV := "CacheSubscribedJob(owner=<Invite:"
CLOG_INVOK := "(k_EMsgGCPartyInviteResponse)"
; Every ready-check has its own lobby with its own ID: the exact answer to
; "same match or a new one", instead of guessing by time.
CLOG_LOBBY := "owner=<Lobby:"
CLOG_WAIT := 900        ; how long to wait for a real-click confirmation, ms
CLOG_TRIES := 5         ; candidates tried per ready-check
BTN_MINW := 60          ; the button is at least this many px wide (at 1440p)
; Snapshot size. 256x144 for a 2560x1440 window is exactly 1:10: a 300 px button
; becomes a 30-cell band, and scanning costs tens of milliseconds.
SHOT_W := 256
SHOT_H := 144
; A band wider than this fraction of the window is not a button but a
; full-width panel.
BTN_MAXFRAC := 0.25
; 1.1 s and not less: the confirmation itself reaches the disk in 0.1-0.6 s, and
; a shorter wait would miss the confirmation of a successful silent click.
CLOG_SILENT := 1100      ; how long to wait for a silent-click confirmation, ms
CLOG_HOLD := 0           ; no pause after accepting: we go quiet once confirmed
NTFY_FAIL_MS := 5000     ; not accepted within this many ms: send a phone alert
READY_GAP := 120000      ; fallback timeout: "this is a new ready-check"
RETRY_MS := 4000         ; all candidates missed: retry after this many ms
DOTA_LOGF := A_ScriptDir . "\dota_log.txt"
DOTA_INI := A_ScriptDir . "\dota_accept.ini"
DOTA_LNK := A_AppData . "\Microsoft\Windows\Start Menu\Programs\Startup"
           . "\DotaAccept.lnk"

; Coordinates and colors are SCREEN-relative; otherwise AHK uses the active window.
CoordMode "Mouse", "Screen"
CoordMode "Pixel", "Screen"

dotaPause := false       ; Ctrl+Alt+P
dotaLive := -1           ; 1 Dota running, 0 not running, -1 not checked yet
clogPath := ""           ; path to Dota's console.log
clogPos := 0             ; bytes already read
clogOk := false          ; log found and readable
clogSaid := false        ; the missing-log message was already logged
readyAt := 0             ; last time a ready-check was seen
readyDone := false       ; this ready-check is already accepted
readyTries := 0          ; candidates tried so far
invAt := 0               ; last time a party invite was seen
invDone := false         ; this invite is already answered
invTried := 0            ; candidates tried so far
holdTill := 0            ; (post-accept pause is not used)
curLobby := ""           ; lobby ID of the current ready-check
seenLobbies := Map()     ; lobby IDs already seen: after a match Dota writes the same lobby into the log again
lastTry := 0             ; last time candidates were tried
learned := []            ; remembered successful spots, as window fractions

; What to auto-accept. Stored in the ini file, switched in the tray menu.
optMatch := IniRead(DOTA_INI, "options", "match", "1") != "0"
optInvite := IniRead(DOTA_INI, "options", "invite", "1") != "0"

; Phone notifications via ntfy (https://ntfy.sh). The topic is effectively the
; channel's "password" on the public server: it is generated randomly on first
; run and stored only in dota_accept.ini; it is never logged or shown.
optNtfy := IniRead(DOTA_INI, "options", "ntfy", "1") != "0"
ntfyServer := RTrim(IniRead(DOTA_INI, "ntfy", "server", "https://ntfy.sh"), "/")
ntfyTopic := IniRead(DOTA_INI, "ntfy", "topic", "")
ntfyJobs := []           ; requests in flight, to check their status later

; Steam keeps the launch options of a game separately for every account. If this is
; on, the script adds the missing flags (-condebug by default) to the accounts
; Steam is not running under right now. Off by default.
optSteamFix := IniRead(DOTA_INI, "steam", "fix", "0") != "0"
STEAM_FLAGS := StrSplit(RegExReplace(Trim(IniRead(DOTA_INI, "steam", "flags", "-condebug")), "\s+", " "), " ")
if !IndexOf(STEAM_FLAGS, "-condebug")
    STEAM_FLAGS.Push("-condebug")
readyFail := false       ; the "could not accept" alert was already sent for this ready-check
alertedFor := "-"        ; lobby the alert is already armed for
issues := Map()          ; current problems: key -> text (the tray icon turns into "pause")
dotaSince := 0           ; when Dota was first seen running
lastGrow := 0            ; last time console.log grew
invPending := false      ; invite received, popup not found / not accepted yet
invUntil := 0            ; keep trying until this moment
invRetryAt := 0          ; next retry time
invMissLogged := false   ; the "button not found" message was already logged
lobbyAt := 0             ; when the current lobby appeared
lobbyWatch := false       ; waiting for the ready-check signal; if it never comes, look for the window on screen
lobbyNext := 0           ; next time to look at the screen

; ── hero auto-pick (optional module, off by default) ──────────────
MigratePickIni()
optPick := IniRead(DOTA_INI, "pick", "enabled", "0") != "0"
optPickDelay := Integer(IniRead(DOTA_INI, "pick", "delay_ms", "15000"))
optPickShots := IniRead(DOTA_INI, "pick", "shots", "1") != "0"   ; pick-screen frames in snapshots\
PICK_OUT := A_ScriptDir . "\snapshots"
HERO_NAME := Map()       ; hero key -> English name
HERO_ATTR := Map()       ; hero key -> S/A/I/U
HERO_BYNAME := Map()     ; normalized name/key -> hero key
HERO_ORDER := Map()      ; "S"/"A"/"I"/"U" -> array of keys in grid order
XB := Map("S", 183, "A", 609, "I", 1037, "U", 1464)   ; left edge of the block, 1440p
heroWant := []           ; hero keys from the settings, in priority order
baseSat := Map()         ; card saturation at the start of the pick (to spot "gray" ones)
TPL_ROWS := []           ; template of the "MY HEROES" label
inStage := false         ; the hero selection stage is on
picked := false          ; already tried during this stage
stageUntil := 0
stageAt := 0             ; when the hero selection stage began
pickNote := ""           ; why we are waiting (so the log is not written every 3 s)
; The pick round runs on the on-screen timer: at the start of the stage (the
; HERO_SELECTION log line) it reads 0:25, and at 0:00 the team starts losing gold.
; Measured on matchmaking frames: +0 s = 0:25, +16 s = 0:09. Picking starts after
; optPickDelay (15 s) and only makes sense until the end of the first round: by
; default until second 24 of the stage. Change it in dota_accept.ini: [pick] deadline_ms.
PICK_DEADLINE_MS := Integer(IniRead(DOTA_INI, "pick", "deadline_ms", "24000"))
lastPool := ""
sg := ""                 ; settings window
sgLV := "", sgLB := "", sgFilter := "", sgInfo := ""
sgOrder := [], sgKeys := [], sgBuilding := false

M_SETTINGS := Tr("Settings…")
M_PICK := Tr("Auto-pick hero")
M_NTFY := Tr("Phone notifications (ntfy)")
M_NTFYCOPY := Tr("Copy ntfy topic")
M_NTFYTEST := Tr("Send test notification")
M_MATCH := Tr("Auto-accept matches")
M_INV := Tr("Auto-accept party invites")
M_PAUSE := Tr("Pause  (Ctrl+Alt+P)")
M_RUN := Tr("Start with Windows")
M_LOG := Tr("Open log")

LearnLoad()

Log(txt) {
    global DOTA_LOGF
    try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") . "." . A_MSec . "  " . txt
                   . "`n", DOTA_LOGF, "UTF-8")
}

Note(txt, ms := 2500, force := false) {
    ToolTip txt
    SetTimer () => ToolTip(), -ms
}

Px(x, y) {
    try
        return PixelGetColor(x, y)
    catch
        return -1
}

; The window UNDER THE POINT must be Dota, otherwise there is nothing to read.
Under(x, y) {
    global DOTA_EXE
    hw := DllCall("WindowFromPoint", "int64",
                  (x & 0xFFFFFFFF) | ((y & 0xFFFFFFFF) << 32), "ptr")
    if !hw
        return false
    hw := DllCall("GetAncestor", "ptr", hw, "uint", 2, "ptr")   ; GA_ROOT
    pid := 0
    DllCall("GetWindowThreadProcessId", "ptr", hw, "uint*", &pid)
    if !pid
        return false
    try
        return ProcessGetName(pid) = DOTA_EXE
    catch
        return false
}

; SNAPSHOT of a screen area, immediately scaled down to sw x sh. Returns a
; buffer of sw*sh*4 bytes, four per pixel: B, G, R and padding. StretchBlt with
; HALFTONE averages while shrinking instead of taking every n-th pixel, so a
; thin border does not turn into a band and a large fill stays a fill.
Shot(x, y, w, h, sw, sh) {
    hdcS := DllCall("GetDC", "ptr", 0, "ptr")
    if !hdcS
        return 0
    hdcM := DllCall("CreateCompatibleDC", "ptr", hdcS, "ptr")
    hbm := DllCall("CreateCompatibleBitmap", "ptr", hdcS, "int", sw,
                   "int", sh, "ptr")
    old := DllCall("SelectObject", "ptr", hdcM, "ptr", hbm, "ptr")
    DllCall("SetStretchBltMode", "ptr", hdcM, "int", 4)        ; HALFTONE
    ok := DllCall("StretchBlt", "ptr", hdcM, "int", 0, "int", 0,
                  "int", sw, "int", sh, "ptr", hdcS, "int", x, "int", y,
                  "int", w, "int", h, "uint", 0x00CC0020)      ; SRCCOPY
    px := 0
    if ok {
        bi := Buffer(40, 0)
        NumPut("uint", 40, bi, 0)
        NumPut("int", sw, bi, 4)
        NumPut("int", -sh, bi, 8)      ; negative height: rows run top to bottom
        NumPut("ushort", 1, bi, 12)
        NumPut("ushort", 32, bi, 14)
        px := Buffer(sw * sh * 4, 0)
        if !DllCall("GetDIBits", "ptr", hdcM, "ptr", hbm, "uint", 0,
                    "uint", sh, "ptr", px, "ptr", bi, "uint", 0)
            px := 0
    }
    DllCall("SelectObject", "ptr", hdcM, "ptr", old)
    DllCall("DeleteObject", "ptr", hbm)
    DllCall("DeleteDC", "ptr", hdcM)
    DllCall("ReleaseDC", "ptr", 0, "ptr", hdcS)
    return px
}

; Candidates for the ACCEPT button. Runs once per ready-check, when we already
; know the window is up, so we can search properly instead of probing one pixel.
; Geometry check: the button is a WIDE FLAT BAND of one colour. Grass and panels
; have no such band; the button always does, in any language and at any
; resolution.
FindAccept(wide := true) {
    global DOTA_WIN, BTN_MINW, CLOG_TRIES, SHOT_W, SHOT_H
    global BTN_MAXFRAC, learned
    out := []
    try
        WinGetPos &wx, &wy, &ww, &wh, DOTA_WIN
    catch
        return out
    if !ww || !wh
        return out
    ;    Snapshot of the WHOLE window: the accept button is in the middle, and the
    ;    popups can be at any edge, so one area serves both.
    px := Shot(wx, wy, ww, wh, SHOT_W, SHOT_H)
    if !px
        return out
    kx := ww / SHOT_W, ky := wh / SHOT_H
    ;    Minimum band width in snapshot cells. BTN_MINW is defined for 1440p, so
    ;    convert it to pixels of this window first, then to cells.
    minw := Round((wide ? BTN_MINW : BTN_MINW / 3) * (wh / 1440.0) / kx)
    if minw < 3
        minw := 3
    rows := []
    j := 0
    while j < SHOT_H {
        i := 0, st := -1, sc := 0
        while i < SHOT_W {
            o := (j * SHOT_W + i) * 4
            b := NumGet(px, o, "UChar")
            g := NumGet(px, o + 1, "UChar")
            r := NumGet(px, o + 2, "UChar")
            _green := (g > r + 20 && g > b + 15 && g > 60 && g < 250)
            if _green {
                if st < 0
                    st := i, sc := (r << 16) | (g << 8) | b
            } else if st >= 0 {
                if i - st >= minw
                    rows.Push([st, i - 1, j, sc])
                st := -1
            }
            i++
        }
        if st >= 0 && SHOT_W - st >= minw
            rows.Push([st, SHOT_W - 1, j, sc])
        j++
    }
    if !rows.Length
        return out
    ;    Sort bands by width and merge adjacent rows of the same button into one
    ;    candidate. Within the "normal width" bucket the widest goes first.
    Loop rows.Length - 1 {
        i := A_Index
        Loop rows.Length - i {
            j := A_Index
            if (rows[j][2] - rows[j][1]) < (rows[j + 1][2] - rows[j + 1][1]) {
                _t := rows[j], rows[j] := rows[j + 1], rows[j + 1] := _t
            }
        }
    }
    ;    First collect everyone, then sort into three buckets:
    ;    1) near a remembered successful spot - first,
    ;    2) normal width - by descending width,
    ;    3) wider than a quarter of the window - last; those are panels, not buttons.
    _a := [], _b := [], _c := []
    for e in rows {
        cx := wx + Round((e[1] + e[2]) / 2 * kx)
        cy := wy + Round((e[3] + 0.5) * ky)
        _w := Round((e[2] - e[1] + 1) * kx)
        _dup := false
        for c in _a {
            if Abs(c[2] - cy) < Round(wh * 0.04) && Abs(c[1] - cx) < Round(ww * 0.2)
                _dup := true
        }
        for c in _b {
            if Abs(c[2] - cy) < Round(wh * 0.04) && Abs(c[1] - cx) < Round(ww * 0.2)
                _dup := true
        }
        for c in _c {
            if Abs(c[2] - cy) < Round(wh * 0.04) && Abs(c[1] - cx) < Round(ww * 0.2)
                _dup := true
        }
        if _dup
            continue
        if !Under(cx, cy)
            continue
        _e := [cx, cy, _w, e[4]]
        ; The match accept button is always at the center of the window. Bands at the edges
        ; are side panels of the menu: they go to the end of the list and are never "remembered".
        _fx := (cx - wx) / ww
        if wide && (_fx < 0.3 || _fx > 0.7) {
            _c.Push(_e)
            continue
        }
        _hit := false
        for L in learned {
            ;            ; Match the width too: a 1040 px background panel may now lie where
            ;            ; the old button was. By coordinates it is "ours", by width (a button
            ;            ; is ~0.09 of the window) it is not. Without this check the wrong
            ;            ; candidate went first and ~2.5 s were wasted.
            if Abs((cx - wx) / ww - L[1]) < 0.06
               && Abs((cy - wy) / wh - L[2]) < 0.06
               && Abs(_w / ww - L[3]) < 0.03
                _hit := true
        }
        if _hit {
            _e.Push(1)                  ; 5th element: matches a remembered spot
            _a.Push(_e)
        }
        else if _w <= ww * BTN_MAXFRAC
            _b.Push(_e)
        else
            _c.Push(_e)
    }
    for L in [_a, _b, _c] {
        for e in L {
            out.Push(e)
            if out.Length >= CLOG_TRIES
                return out
        }
    }
    return out
}

; If the accept window is recognised but there is no green, write the whole grid
; to the log. These rows show where the button really is. Once per window,
; otherwise the log would be flooded.
DumpColumn(why := Tr("accept window seen, green button not found")) {
    global DOTA_WIN
    ;    A grid across the middle of the window rather than one column, so the button
    ;    can be told apart from the panels.
    try
        WinGetPos &wx, &wy, &ww, &wh, DOTA_WIN
    catch
        return
    s := ""
    Loop 5 {
        gx := wx + Round(ww * (0.35 + 0.075 * (A_Index - 1)))
        s .= "`n  x=" . gx . ":"
        y := wy + Round(wh * 0.2)
        while y <= wy + Round(wh * 0.8) {
            s .= Format(" {1}:{2:#06x}", y, Px(gx, y))
            y += Round(wh * 0.025)
        }
    }
    Log(why . Tr(". grid:") . s)
}

; ── Dota's console.log ─────────────────────────────────────────────
; The path is taken from the process itself, not guessed: Steam may have a
; second library on another drive. The exe is in game\bin\win64, the log in
; game\dota.
ClogFind() {
    global DOTA_EXE, DOTA_INI
    _p := IniRead(DOTA_INI, "log", "path", "")
    if _p != "" && FileExist(_p)
        return _p
    pid := ProcessExist(DOTA_EXE)
    if !pid
        return ""
    hp := DllCall("OpenProcess", "uint", 0x1000, "int", 0, "uint", pid, "ptr")
    if !hp
        return ""
    buf := Buffer(1040, 0)
    len := 520
    ok := DllCall("QueryFullProcessImageNameW", "ptr", hp, "uint", 0,
                  "ptr", buf, "uint*", &len)
    DllCall("CloseHandle", "ptr", hp)
    if !ok
        return ""
    exe := StrGet(buf, len, "UTF-16")
    _tail := "\bin\win64\" . DOTA_EXE
    if !InStr(exe, _tail)
        return ""
    _log := StrReplace(exe, _tail, "\dota\console.log")
    return FileExist(_log) ? _log : ""
}

; Lobby ID from a chunk of log: take the LAST occurrence, it is the freshest.
LobbyId(txt) {
    global CLOG_LOBBY
    p := InStr(txt, CLOG_LOBBY)
    if !p
        return ""
    Loop {
        q := InStr(txt, CLOG_LOBBY, , p + 1)
        if !q
            break
        p := q
    }
    _s := SubStr(txt, p + StrLen(CLOG_LOBBY))
    e := InStr(_s, ">")
    return e ? SubStr(_s, 1, e - 1) : ""
}

; All the lobbies that are already in the log (the script may start in the middle of a
; Dota session). On 1.11, after a match Dota wrote into the log a lobby the script did
; not remember (it had just been restarted), it passed for a new one, and the "find the
; window on the screen" fallback took a green button of the post-match screen for the
; accept button: five false clicks and a false alarm to the phone.
SeedLobbies(path) {
    global seenLobbies, CLOG_LOBBY
    try {
        f := FileOpen(path, "r")
        txt := f.Read()
        f.Close()
    } catch
        return
    pos := 1
    while pos := InStr(txt, CLOG_LOBBY, , pos) {
        pos += StrLen(CLOG_LOBBY)
        e := InStr(txt, ">", , pos)
        if e && e - pos < 40
            seenLobbies[SubStr(txt, pos, e - pos)] := true
    }
}

; New bytes of the log. Only the tail is read: the file grows by tens of
; kilobytes per session, there is no point in re-reading all of it five times
; a second.
ClogNew() {
    global clogPath, clogPos
    try {
        ;        ; Plain "r". The "-rwd" suffix FORBIDS other processes to read, write
        ;        ; and delete the file in AHK, and Dota keeps it open for writing, so
        ;        ; opening failed and the log was read as empty.
        f := FileOpen(clogPath, "r")
        if !f
            return ""
        ;        ; Dota ERASES console.log on every launch. A file shorter than the
        ;        ; remembered position is therefore a new session, and we stand at its
        ;        ; END, not at the start: from the start we would re-read the whole
        ;        ; session at once and take an old ready-check for a new one.
        if f.Length < clogPos {
            clogPos := f.Length
            f.Close()
            return ""
        }
        if f.Length = clogPos {
            f.Close()
            return ""
        }
        f.Pos := clogPos
        txt := f.Read()
        clogPos := f.Pos
        f.Close()
        return txt
    } catch
        return ""
}

; Remembered successful clicks: window fractions, not pixels, so they carry
; over between resolutions and accounts (the accept window differs with Dota
; Plus). Up to three are kept, newest first.
LearnLoad() {
    global learned, DOTA_INI
    learned := []
    Loop 3 {
        _v := IniRead(DOTA_INI, "learn", "p" . A_Index, "")
        if _v = ""
            continue
        _p := StrSplit(_v, ",")
        ; A remembered spot at the window edge is a mistake (on 30.10 somebody else's click was
        ; counted as the confirmation): the accept button is at the center.
        if _p.Length >= 3 && Abs(_p[1] - 0.5) <= 0.2
            learned.Push([_p[1] + 0, _p[2] + 0, _p[3] + 0])
    }
}

LearnSave(rx, ry, rw) {
    global learned, DOTA_INI
    _new := [[rx, ry, rw]]
    for e in learned {
        ;        ; do not store the same spot twice
        if Abs(e[1] - rx) < 0.03 && Abs(e[2] - ry) < 0.03
            continue
        if _new.Length < 3
            _new.Push(e)
    }
    learned := _new
    Loop 3 {
        if A_Index <= learned.Length
            IniWrite Format("{1:0.4f},{2:0.4f},{3:0.4f}", learned[A_Index][1],
                            learned[A_Index][2], learned[A_Index][3]),
                     DOTA_INI, "learn", "p" . A_Index
    }
}

; ── health: tray icon and launch-option check ─────────────────────
; The script uses AutoHotkey's own built-in icons: "H" means all is well, "II"
; (pause) means paused or something is wrong. No extra icon files are needed.
AddIssue(key, text) {
    global issues
    issues[key] := text
    Status()
}

DelIssue(key) {
    global issues
    if issues.Has(key) {
        issues.Delete(key)
        Status()
    }
}

IssueText() {
    global issues
    for k, v in issues
        return v
    return ""
}

; Icon: when all is well, the game's own icon (taken from its dota2.exe; no icon
; files of our own); paused or a problem: AutoHotkey's built-in "II" icon. If Dota
; is not on the disk: the standard "H".
DotaIconPath() {
    global DOTA_EXE, DOTA_INI
    static cached := ""
    if cached != "" && FileExist(cached)
        return cached
    pid := ProcessExist(DOTA_EXE)
    if pid {
        try {
            p := ProcessGetPath(pid)
            if FileExist(p) {
                IniWrite p, DOTA_INI, "state", "dota_exe"
                return cached := p
            }
        }
    }
    p := IniRead(DOTA_INI, "state", "dota_exe", "")
    if p != "" && FileExist(p)
        return cached := p
    try {
        steam := StrReplace(RegRead("HKCU\Software\Valve\Steam", "SteamPath"), "/", "\")
        p := steam . "\steamapps\common\dota 2 beta\game\bin\win64\dota2.exe"
        if FileExist(p)
            return cached := p
    }
    return ""
}

UpdateIcon() {
    global dotaPause, issues
    static last := ""
    bad := dotaPause || issues.Count
    ex := bad ? "" : DotaIconPath()
    want := bad ? "p" : (ex != "" ? "d" : "h")
    if want = last
        return
    last := want
    try {
        if want = "d"
            TraySetIcon(ex, 1, true)
        else
            TraySetIcon(A_AhkPath, bad ? 4 : 1, true)
    }
}

; A Windows notification at the bottom of the screen. loud = with sound (the first
; reminder), repeats are silent. Without -condebug the script does nothing, so we
; remind at every Dota start, not "at most three times".
Hint(text, loud := false) {
    try TrayTip(text, "Dota auto-accept", loud ? "Icon!" : "Iconi Mute")
}

HINT_TEXT := Tr("Dota 2 was started without the -condebug launch option, so the script cannot see matches. ")
           . Tr("In Steam: Dota 2 → Properties → Launch Options: add -condebug ")
           . Tr("and restart Dota.")

; What exactly is wrong: Steam has no such option for this account (every Steam
; account has its own launch options), or it is set but Dota was started around
; it (it restarted itself, or not with the Play button).
OptsText() {
    global HINT_TEXT
    o := SteamLaunchOptions()
    if o = -1
        return HINT_TEXT
    if InStr(o, "-condebug")
        return Tr("Dota 2 was started without -condebug although it is set in Steam: it was not started ")
             . Tr("with the Play button (or it restarted itself). Close Dota and ")
             . Tr("start it again through Steam.")
    return Tr("Dota 2 was started without -condebug, so the script cannot see matches. In Steam, for ")
         . Tr("this account the option is not set: Dota 2 → Properties → Launch ")
         . Tr("Options → -condebug.")
}

; While Dota runs without -condebug, remind every 10 minutes.
RemindOpts() {
    global issues
    if !issues.Has("opts") {
        SetTimer RemindOpts, 0
        return
    }
    Hint(OptsText())
}

; When Dota is ALREADY running: the process command line is the only reliable
; answer to whether it was started with -condebug.
DotaCmdLine() {
    try {
        for pr in ComObjGet("winmgmts:").ExecQuery(
            "SELECT CommandLine FROM Win32_Process WHERE Name='dota2.exe'")
            return pr.CommandLine
    }
    return ""
}

CheckLaunchOpts() {
    cmd := DotaCmdLine()
    if cmd = ""
        return                          ; could not read it, so do not guess
    if InStr(cmd, "-condebug") {
        DelIssue("opts")
        SetTimer RemindOpts, 0
        return
    }
    AddIssue("opts", Tr("Dota started without -condebug"))
    Log(Tr("Dota was started without -condebug: the script cannot see matches"))
    Hint(OptsText(), true)
    SetTimer RemindOpts, 600000
}

; When Dota is not running yet: what is entered in the launch options in Steam
; (userdata\<id>\config\localconfig.vdf, block of app 570). Returns the options
; string ("" if none) or -1 if it could not be determined.
SteamLaunchOptions() {
    try
        steam := StrReplace(RegRead("HKCU\Software\Valve\Steam", "SteamPath"), "/", "\")
    catch
        return -1
    user := 0
    try user := RegRead("HKCU\Software\Valve\Steam\ActiveProcess", "ActiveUser")
    file := user ? steam . "\userdata\" . user . "\config\localconfig.vdf" : ""
    if !FileExist(file) {
        file := "", newest := 0
        Loop Files steam . "\userdata\*", "D" {
            f := A_LoopFilePath . "\config\localconfig.vdf"
            if FileExist(f) && FileGetTime(f) > newest
                newest := FileGetTime(f), file := f
        }
    }
    if file = ""
        return -1
    try
        txt := FileRead(file, "UTF-8")
    catch
        return -1
    pos := 1
    while pos := RegExMatch(txt, '"570"\s*\{', &m, pos) {
        start := pos + m.Len, depth := 1, i := start
        while depth > 0 && i <= StrLen(txt) {
            ch := SubStr(txt, i, 1)
            if ch = "{"
                depth++
            else if ch = "}"
                depth--
            i++
        }
        if RegExMatch(SubStr(txt, start, i - start), '"LaunchOptions"\s+"([^"]*)"', &o)
            return o[1]
        pos := start
    }
    return ""
}

; Once at script start, while Dota is not running: if Steam has no such option,
; offer to write it right away rather than after the first missed match.
EarlyCheck() {
    global DOTA_EXE
    if ProcessExist(DOTA_EXE)
        return                          ; already running: Tick checks the process
    o := SteamLaunchOptions()
    if o != -1 && !InStr(o, "-condebug")
        Log(Tr("the Dota 2 launch options in Steam do not contain -condebug"))
    SetTimer OfferSteamFix, -8000       ; it decides by itself whether there is anything to offer
}

; ── launch options of other Steam accounts ─────────────────────────
; Steam keeps the launch options of a game separately for every account: in
; userdata\<id>\config\localconfig.vdf, block apps\570. The account Steam is
; running under right now is held in memory and Steam will overwrite its file on
; exit, so only the other accounts are touched. Before the first edit a copy is
; put next to the file (.bak_dotaaccept); after the edit the file is read again
; and, if it does not parse, the edit is rolled back.

VdfPath(a) {
    s := ""
    for k in a
        s .= (A_Index > 1 ? "/" : "") . k
    return s
}

; Parsing a Steam file in VDF format: where in the text the Steam, apps and 570 blocks
; are and the value of the key inside 570. root is the path to the Steam block (lower
; case, separated by "/"). ok = the braces matched up to the end of the file.
VdfScan(txt, root, key) {
    r := Map("steam", 0, "apps", 0, "app", 0, "kPos", 0, "kLen", 0, "val", "", "ok", false)
    depth := [], pend := "", pos := 1
    ; Tokens are found by a plain character search and the closing quote by hand: the
    ; file has JSON strings of tens of kilobytes, and a regular expression hits the
    ; PCRE limit on them and silently stops the parse.
    while pos := RegExMatch(txt, '["{}]', &m, pos) {
        at := pos
        if m[0] = "{" {
            pos++
            depth.Push(StrLower(pend))
            pend := ""
            p := VdfPath(depth)
            if !r["steam"] && p = root
                r["steam"] := pos
            else if !r["apps"] && p = root . "/apps"
                r["apps"] := pos
            else if !r["app"] && p = root . "/apps/570"
                r["app"] := pos
        } else if m[0] = "}" {
            pos++
            if !depth.Length
                return r
            depth.Pop()
        } else {
            q := at + 1
            Loop {
                q := InStr(txt, '"', true, q)
                if !q
                    return r            ; unclosed quote: the file is broken
                b := 0, k := q - 1
                while k > at && SubStr(txt, k, 1) = "\" {
                    b++
                    k--
                }
                if Mod(b, 2) = 0
                    break               ; an even number of backslashes before the quote: it is a real one
                q++
            }
            str := SubStr(txt, at + 1, q - at - 1)
            pos := q + 1
            if pend = "" {
                pend := str
            } else {
                if !r["kPos"] && StrLower(pend) = key
                   && VdfPath(depth) = root . "/apps/570" {
                    r["kPos"] := at, r["kLen"] := q - at + 1, r["val"] := str
                }
                pend := ""
            }
        }
    }
    r["ok"] := !depth.Length && pend = ""
    return r
}

; Writes keyName = val into the apps\570 block (missing blocks are created).
; "" = there is not even a Steam block, nowhere to write.
VdfPut(txt, r, keyName, val) {
    kv := '"' . keyName . '"`t`t"' . val . '"'
    t4 := "`t`t`t`t", t5 := t4 . "`t", t6 := t5 . "`t"
    if r["kPos"]
        return SubStr(txt, 1, r["kPos"] - 1) . '"' . val . '"'
             . SubStr(txt, r["kPos"] + r["kLen"])
    if r["app"]
        return SubStr(txt, 1, r["app"] - 1) . "`n" . t6 . kv . SubStr(txt, r["app"])
    if r["apps"]
        return SubStr(txt, 1, r["apps"] - 1) . "`n" . t5 . '"570"`n' . t5 . "{`n"
             . t6 . kv . "`n" . t5 . "}" . SubStr(txt, r["apps"])
    if r["steam"]
        return SubStr(txt, 1, r["steam"] - 1) . "`n" . t4 . '"apps"`n' . t4 . "{`n"
             . t5 . '"570"`n' . t5 . "{`n" . t6 . kv . "`n" . t5 . "}`n" . t4 . "}"
             . SubStr(txt, r["steam"])
    return ""
}

; Writes out in place of file. A copy is left next to it (.bak_dotaaccept, the first one
; only). The new text is first put into a temporary file and read again: if it does not
; parse or the value is wrong (check), the file stays as it was.
VdfWriteSafe(file, out, root, key, check) {
    bak := file . ".bak_dotaaccept", tmp := file . ".tmp_dotaaccept"
    try {
        if !FileExist(bak)
            FileCopy file, bak
        f := FileOpen(tmp, "w", "UTF-8-RAW")
        f.Write(out)
        f.Close()
        chk := VdfScan(FileRead(tmp, "UTF-8"), root, key)
        if !chk["ok"] || !check(chk["val"]) {
            FileDelete tmp
            return false
        }
        FileMove tmp, file, 1
        return true
    } catch {
        try FileDelete tmp
        return false
    }
}

; Which flags of STEAM_FLAGS are missing from the options string (with a leading space).
MissingFlags(cur) {
    global STEAM_FLAGS
    have := " " . StrLower(RegExReplace(cur, "\s+", " ")) . " "
    add := ""
    for f in STEAM_FLAGS
        if !InStr(have, " " . StrLower(f) . " ")
            add .= " " . f
    return add
}

; 1 = added, 0 = everything is there already or the file is not what we expect, -1 = failed.
PatchLaunchOptions(file, id) {
    try txt := FileRead(file, "UTF-8")
    catch
        return -1
    root := "userlocalconfigstore/software/valve/steam"
    r := VdfScan(txt, root, "launchoptions")
    if !r["ok"] || !r["apps"]
        return 0                        ; account without a games list: do not guess
    cur := r["kPos"] ? r["val"] : ""
    add := MissingFlags(cur)
    if add = ""
        return 0
    out := VdfPut(txt, r, "LaunchOptions", Trim(cur . add))
    if out = "" || !VdfWriteSafe(file, out, root, "launchoptions", (v) => MissingFlags(v) = "")
        return -1
    Log(Tr("Steam: account …") . SubStr(id, -3) . Tr(" - added to the Dota 2 launch options: ") . Trim(add))
    return 1
}

; Steam Cloud for Dota is switched off by the key cloudenabled = 0 in
; userdata\<id>\7\remote\sharedconfig.vdf (block apps\570); Steam overwrites the file of
; the account it is running under, so only while Steam is closed. 1 = off (or already
; was), -1 = failed.
SetCloudOff(id) {
    f := SteamDir() . "\userdata\" . id . "\7\remote\sharedconfig.vdf"
    root := "userroamingconfigstore/software/valve/steam"
    if !FileExist(f) {
        try {
            DirCreate SteamDir() . "\userdata\" . id . "\7\remote"
            h := FileOpen(f, "w", "UTF-8-RAW")
            h.Write('"UserRoamingConfigStore"`n{`n`t"Software"`n`t{`n`t`t"Valve"`n`t`t{`n'
                    . '`t`t`t"Steam"`n`t`t`t{`n`t`t`t`t"apps"`n`t`t`t`t{`n`t`t`t`t`t"570"`n'
                    . '`t`t`t`t`t{`n`t`t`t`t`t`t"cloudenabled"`t`t"0"`n`t`t`t`t`t}`n'
                    . '`t`t`t`t}`n`t`t`t}`n`t`t}`n`t}`n}`n')
            h.Close()
            return 1
        } catch
            return -1
    }
    try txt := FileRead(f, "UTF-8")
    catch
        return -1
    r := VdfScan(txt, root, "cloudenabled")
    if !r["ok"]
        return -1
    if r["kPos"] && r["val"] = "0"
        return 1
    out := VdfPut(txt, r, "cloudenabled", "0")
    if out = "" || !VdfWriteSafe(f, out, root, "cloudenabled", (v) => v = "0")
        return -1
    Log(Tr("Steam: Steam Cloud for Dota switched off for account …") . SubStr(id, -3))
    return 1
}

; Every 5 minutes. seen: the file date of each account as of our last check; while
; Steam has not changed the file we do not read it again. Files younger than a
; minute are left alone: Steam may have just written it on leaving the account.
FixSteamAccounts() {
    global optSteamFix
    static seen := Map()
    SetTimer FixSteamAccounts, -300000
    if !optSteamFix
        return
    try steam := StrReplace(RegRead("HKCU\Software\Valve\Steam", "SteamPath"), "/", "\")
    catch
        return
    active := 0
    if ProcessExist("steam.exe") {
        try active := RegRead("HKCU\Software\Valve\Steam\ActiveProcess", "ActiveUser")
        if !active
            return                      ; Steam is still logging in: later
    }
    Loop Files steam . "\userdata\*", "D" {
        id := A_LoopFileName
        if !RegExMatch(id, "^[1-9]\d*$") || id = active
            continue
        f := A_LoopFilePath . "\config\localconfig.vdf"
        if !FileExist(f)
            continue
        t := FileGetTime(f)
        if (seen.Has(id) && seen[id] = t) || DateDiff(A_Now, t, "Seconds") < 60
            continue
        res := PatchLaunchOptions(f, id)
        if res = -1
            Log(Tr("Steam: could not fix the launch options of account …") . SubStr(id, -3)
                . Tr(" (file left untouched)"))
        seen[id] := FileGetTime(f)
    }
}

; ── writing the options into the account Steam is running under ────
; Steam holds that file in memory and will overwrite it on exit, so the options can
; only be written while Steam is closed. The script offers to close Steam itself
; (steam.exe -shutdown is the standard way), write the options and start it again.
; While Dota is running we do nothing: Steam would close it along with itself.
SteamDir() {
    try return StrReplace(RegRead("HKCU\Software\Valve\Steam", "SteamPath"), "/", "\")
    return ""
}

; Who we write to: the active account, and if Steam is closed, the one whose file
; changed last (SteamLaunchOptions picks it the same way).
SteamTargetId() {
    steam := SteamDir()
    if steam = ""
        return ""
    user := 0
    try user := RegRead("HKCU\Software\Valve\Steam\ActiveProcess", "ActiveUser")
    if user
        return String(user)
    best := "", newest := 0
    Loop Files steam . "\userdata\*", "D" {
        f := A_LoopFilePath . "\config\localconfig.vdf"
        if RegExMatch(A_LoopFileName, "^[1-9]\d*$") && FileExist(f)
           && FileGetTime(f) > newest
            newest := FileGetTime(f), best := A_LoopFileName
    }
    return best
}

FileHasFlags(file) {
    try txt := FileRead(file, "UTF-8")
    catch
        return false
    r := VdfScan(txt, "userlocalconfigstore/software/valve/steam", "launchoptions")
    return r["ok"] && MissingFlags(r["val"]) = ""
}

DoSteamFix(profile := false) {
    global optSteamFix, DOTA_EXE
    static busy := false
    if busy
        return
    steam := SteamDir()
    if steam = "" || !FileExist(steam . "\steam.exe") {
        MsgBox(Tr("Could not find Steam on this PC."), "Dota auto-accept", "Icon!")
        return
    }
    if ProcessExist(DOTA_EXE) {
        MsgBox(Tr("Dota 2 is running. Close it and try again: Steam has to be closed, ")
               . Tr("and it would close Dota along with itself."), "Dota auto-accept", "Icon!")
        return
    }
    busy := true
    target := SteamTargetId()
    was := ProcessExist("steam.exe")
    if was {
        Log(Tr("Steam: closing it to write the launch options"))
        Run('"' . steam . '\steam.exe" -shutdown', , "Hide")
        Loop 80 {
            if !ProcessExist("steam.exe")
                break
            Sleep 500
        }
        if ProcessExist("steam.exe") {
            busy := false
            Log(Tr("Steam: did not close within 40 s - changed nothing"))
            MsgBox(Tr("Steam did not close within 40 seconds, I changed nothing. Close it ")
                   . Tr("yourself (tray icon → Exit) and try again."), "Dota auto-accept", "Icon!")
            return
        }
        Sleep 3000                      ; Steam is still finishing its files
    }
    f := target != "" ? steam . "\userdata\" . target . "\config\localconfig.vdf" : ""
    res := f != "" && FileExist(f) ? PatchLaunchOptions(f, target) : -1
    ok := res = 1 || (res != -1 && f != "" && FileHasFlags(f))
    cloud := 0, nfiles := -1
    if profile && target != "" {
        cloud := SetCloudOff(target)
        nfiles := ApplyProfile(target)
        if nfiles >= 0
            MarkKnown(target)
        Log(Tr("Dota settings profile transferred: ") . nfiles . Tr(" files, Steam Cloud ")
            . (cloud = 1 ? Tr("off") : Tr("could not be switched off")))
    }
    if optSteamFix
        FixSteamAccounts()              ; Steam is closed: the other accounts too
    if was
        Run('"' . steam . '\steam.exe"')
    busy := false
    msg := ""
    if profile {
        msg .= nfiles >= 0
            ? Tr("Dota settings transferred (") . nfiles . Tr(" files); what was there before ")
              . Tr("is saved in the bak_profile folder next to the script. ")
            : Tr("Could not transfer the settings. ")
        msg .= cloud = 1
            ? Tr("Steam Cloud for Dota is switched off. ")
            : Tr("Could not switch Steam Cloud off - do it yourself: Steam → Dota 2 → Properties → ")
              . Tr("General → untick 'Keep game saves in the Steam Cloud for Dota 2'. ")
    }
    msg .= ok ? Tr("Launch options written.") : Tr("Could not write the launch options: add ")
             . Tr("-condebug by hand (Steam → Dota 2 → Properties → Launch Options).")
    Log("Steam: " . msg)
    if ok && (!profile || (nfiles >= 0 && cloud = 1))
        Hint(msg . (was ? Tr(" Steam is starting again.") : ""), true)
    else
        MsgBox(msg . (was ? Tr("`n`nSteam is starting again.") : ""), "Dota auto-accept", "Icon!")
}

; ── Dota settings profile ──────────────────────────────────────────
; "My settings": a copy of the Dota settings files (keys, interface, video, hero grid,
; builds) from the source account. It lives in profile\ next to the script and refreshes
; itself when Dota is closed under the source account. For a Steam account that is new
; to the script, the script offers to set it up: transfer the profile, switch Steam Cloud
; off for Dota and write the launch options. Only settings are copied (list below), not
; statistics, friends, voice bans or anything else that belongs to the account itself.
PROFILE_DIR := A_ScriptDir . "\profile"
PROFILE_FILES := [
    "local\cfg\machine_convars.vcfg", "local\cfg\user_convars_0_slot0.vcfg",
    "local\cfg\user_keys_0_slot0.vcfg", "local\cfg\user_keys_0_slot1.vcfg",
    "local\cfg\user_keys_0_slot2.vcfg", "local\cfg\user_keys_0_slot3.vcfg",
    "local\cfg\video.txt", "remote\user_convars.vcfg", "remote\user_keys.vcfg",
    "remote\cfg\hero_grid_config.json", "remote\cfg\herobuilds.cfg",
    "remote\cfg\hero_facet_config.cfg", "remote\cfg\chat.cfg",
    "remote\cfg\dotakeys_personal.lst", "remote\cfg\saved_sets.kv",
    "remote\cfg\dismissed_help_tips.txt", "remote\scripts\control_groups.txt",
    "remote\scripts\lobby_settings.txt", "remote\scripts\item_suggest_preference.txt",
    "remote\scripts\clientstorage.txt"]

DotaUserDir(id) {
    return SteamDir() . "\userdata\" . id . "\570"
}

ProfileCount() {
    global PROFILE_DIR, PROFILE_FILES
    n := 0
    for rel in PROFILE_FILES
        if FileExist(PROFILE_DIR . "\" . rel)
            n++
    return n
}

; Copies the settings of account id into profile\. Returns the number of files.
SaveProfile(id) {
    global PROFILE_DIR, PROFILE_FILES, DOTA_INI
    n := 0
    for rel in PROFILE_FILES {
        src := DotaUserDir(id) . "\" . rel
        if !FileExist(src)
            continue
        dst := PROFILE_DIR . "\" . rel
        try {
            SplitPath dst, , &dir
            if !DirExist(dir)
                DirCreate dir
            FileCopy src, dst, 1
            n++
        }
    }
    if n {
        IniWrite id, DOTA_INI, "profile", "source"
        IniWrite A_Now, DOTA_INI, "profile", "saved"
    }
    return n
}

; Puts the profile into account id. What was there goes to bak_profile\. Returns the
; number of files or -1.
ApplyProfile(id) {
    global PROFILE_DIR, PROFILE_FILES
    n := 0
    bak := A_ScriptDir . "\bak_profile\" . id . "_" . FormatTime(, "yyyyMMdd-HHmmss")
    for rel in PROFILE_FILES {
        src := PROFILE_DIR . "\" . rel
        if !FileExist(src)
            continue
        dst := DotaUserDir(id) . "\" . rel
        try {
            if FileExist(dst) {
                SplitPath bak . "\" . rel, , &bdir
                if !DirExist(bdir)
                    DirCreate bdir
                FileCopy dst, bak . "\" . rel, 1
            }
            SplitPath dst, , &dir
            if !DirExist(dir)
                DirCreate dir
            FileCopy src, dst, 1
            n++
        } catch
            return -1
    }
    return n
}

; Accounts the script already knows about (they are not "new"). On the first run we
; record all that already lie in userdata.
KnownInit() {
    global DOTA_INI
    if IniRead(DOTA_INI, "profile", "known_init", "") != ""
        return
    ids := ""
    steam := SteamDir()
    if steam != ""
        Loop Files steam . "\userdata\*", "D"
            if RegExMatch(A_LoopFileName, "^[1-9]\d*$")
                ids .= (ids = "" ? "" : ",") . A_LoopFileName
    IniWrite ids, DOTA_INI, "profile", "known"
    IniWrite 1, DOTA_INI, "profile", "known_init"
}

IsKnown(id) {
    global DOTA_INI
    return InStr("," . IniRead(DOTA_INI, "profile", "known", "") . ",", "," . id . ",")
}

MarkKnown(id) {
    global DOTA_INI
    if IsKnown(id)
        return
    k := IniRead(DOTA_INI, "profile", "known", "")
    IniWrite (k = "" ? id : k . "," . id), DOTA_INI, "profile", "known"
}

; Whether it makes sense to offer a settings transfer to account id: a profile is saved,
; the account is new to the script and it is not the source itself.
ProfileNeeded(id) {
    global DOTA_INI
    return id != "" && ProfileCount() > 0 && !IsKnown(id)
           && id != IniRead(DOTA_INI, "profile", "source", "")
}

; After Dota closes: if we are logged in to the source account, refresh the profile
; (Dota writes its settings on exit).
ProfileAutoSave() {
    global DOTA_INI, DOTA_EXE
    src := IniRead(DOTA_INI, "profile", "source", "")
    if src = "" || ProcessExist(DOTA_EXE)
        return
    user := 0
    try user := RegRead("HKCU\Software\Valve\Steam\ActiveProcess", "ActiveUser")
    if String(user) != src
        return
    Log(Tr("Dota settings profile updated: ") . SaveProfile(src) . Tr(" files"))
}

; Every 20 seconds: Steam moved to another account, so offer to set it up. At script
; start the offer is scheduled by EarlyCheck.
WatchAccount() {
    global DOTA_EXE
    static last := 0
    user := 0
    try user := RegRead("HKCU\Software\Valve\Steam\ActiveProcess", "ActiveUser")
    if !user || user = last
        return
    first := !last
    last := user
    if !first && !ProcessExist(DOTA_EXE)
        SetTimer OfferSteamFix, -12000
}

ProfileInfo() {
    global DOTA_INI
    n := ProfileCount()
    if !n
        return Tr("No profile yet.")
    src := IniRead(DOTA_INI, "profile", "source", "")
    t := IniRead(DOTA_INI, "profile", "saved", "")
    return Tr("Profile: ") . n . Tr(" files") . (src != "" ? Tr(" from account …") . SubStr(src, -3) : "")
           . (t != "" ? Tr(", saved ") . FormatTime(t, "dd.MM.yyyy HH:mm") : "") . "."
}

SaveProfileClick() {
    global DOTA_EXE, sgProf
    if ProcessExist(DOTA_EXE) {
        MsgBox(Tr("Dota 2 is running, and it writes its settings on exit. Close it ")
               . Tr("and press again."), "Dota auto-accept", "Icon!")
        return
    }
    id := SteamTargetId()
    n := id != "" ? SaveProfile(id) : 0
    try sgProf.Text := ProfileInfo()
    if n
        MsgBox(Tr("Saved the Dota settings (") . n . Tr(" files) from account …") . SubStr(id, -3)
               . Tr(". From now on the profile updates itself when you close Dota under this ")
               . Tr("account."), "Dota auto-accept", "Iconi")
    else
        MsgBox(Tr("Found no settings files for this account. Start Dota under it at least ")
               . Tr("once and close it."), "Dota auto-accept", "Icon!")
}

ApplyProfileClick() {
    global DOTA_INI
    id := SteamTargetId()
    if ProfileCount() = 0 {
        MsgBox(Tr("No profile yet: first log in to your main account and press 'Save ")
               . Tr("settings of this account'."), "Dota auto-accept", "Icon!")
        return
    }
    if id = IniRead(DOTA_INI, "profile", "source", "") {
        MsgBox(Tr("This is the account the profile was taken from: nothing to transfer to."),
               "Dota auto-accept", "Icon!")
        return
    }
    if MsgBox(Tr("My Dota settings will be written into the account you are logged in with (what ")
              . Tr("is there now will be kept in the bak_profile folder). Steam will be closed and started ")
              . Tr("again, and Steam Cloud for Dota will be switched off. Continue?"), "Dota auto-accept",
              "YesNo Icon?") = "Yes"
        DoSteamFix(true)
}

; The offer window. Scheduled at script start and when Steam moves to another account;
; shows nothing if there is nothing to do. "Do not ask again" is stored in the ini.
OfferSteamFix() {
    global ofg, ofgProf, ofgId, DOTA_INI, DOTA_EXE
    static tries := 0
    if ProcessExist(DOTA_EXE)
        return                          ; Dota is already running: CheckLaunchOpts will say it
    try {
        if WinExist("ahk_id " . ofg.Hwnd)
            return                      ; the window is already on screen
    }
    up := ProcessExist("steam.exe")
    user := 0
    if up {
        try user := RegRead("HKCU\Software\Valve\Steam\ActiveProcess", "ActiveUser")
        if !user {                      ; Steam is still logging in: wait
            if ++tries < 12
                SetTimer OfferSteamFix, -15000
            return
        }
    }
    o := SteamLaunchOptions()
    needFlags := o != -1 && !InStr(o, "-condebug")
    ofgId := SteamTargetId()
    ofgProf := ProfileNeeded(ofgId)
    if !needFlags && !ofgProf
        return
    if IniRead(DOTA_INI, "steam", "ask", "1") = "0" {
        if needFlags
            Hint(OptsText())
        return
    }
    try ofg.Destroy()
    ofg := Gui("+AlwaysOnTop -MaximizeBox", "Dota auto-accept")
    ofg.MarginX := 16, ofg.MarginY := 14
    if needFlags
        ofg.Add("Text", "w440", Tr("In Steam, for the account you are logged in with, the ")
            . Tr("Dota 2 launch options do not contain -condebug, so the script cannot see matches."))
    if ofgProf
        ofg.Add("Text", "w440" . (needFlags ? " y+10" : ""), Tr("This account is new to the script. I can ")
            . Tr("transfer your Dota settings into it and switch Steam Cloud off for Dota so that ")
            . Tr("they do not go to the cloud of this account."))
    ofg.Add("Text", "w440 y+10", up
        ? Tr("For this, Steam will be closed and started again right away (about half a minute). ")
          . Tr("Better close any open games.")
        : Tr("Steam is not running right now, so I will do it at once, no restart needed."))
    b := ofg.Add("Button", "w440 h34 y+14 Default", up ? Tr("Do it and restart Steam") : Tr("Do it"))
    b.OnEvent("Click", (*) => OfferAnswer(1))
    b := ofg.Add("Button", "w214 h30 y+8", Tr("Not now"))
    b.OnEvent("Click", (*) => OfferAnswer(2))
    b := ofg.Add("Button", "w214 h30 x+12 yp", Tr("Do not ask again"))
    b.OnEvent("Click", (*) => OfferAnswer(3))
    ofg.OnEvent("Close", (*) => OfferAnswer(2))
    ofg.Show()
}

AskSteamFix() {
    if MsgBox(Tr("Steam will be closed and started again right away to write -condebug into ")
              . Tr("the account you are logged in with. Continue?"), "Dota auto-accept",
              "YesNo Icon?") = "Yes"
        DoSteamFix()
}

OfferAnswer(n) {
    global ofg, ofgProf, ofgId, DOTA_INI
    try ofg.Destroy()
    if n = 1 {
        DoSteamFix(ofgProf)
        return
    }
    if n = 3 {
        IniWrite 0, DOTA_INI, "steam", "ask"
        MarkKnown(ofgId)
    }
    o := SteamLaunchOptions()
    if o != -1 && !InStr(o, "-condebug")
        Hint(OptsText())
}

; ── ntfy notifications ─────────────────────────────────────────────
; The topic is generated once: 10 random bytes from the system generator.
NtfyInit() {
    global ntfyTopic, DOTA_INI
    if ntfyTopic != ""
        return
    buf := Buffer(10)
    if DllCall("bcrypt\BCryptGenRandom", "ptr", 0, "ptr", buf, "uint", 10,
               "uint", 2) != 0       ; 2 = system RNG; on failure we go without ntfy
        return
    t := "dota-"
    Loop 10
        t .= Format("{:02x}", NumGet(buf, A_Index - 1, "UChar"))
    ntfyTopic := t
    IniWrite ntfyTopic, DOTA_INI, "ntfy", "topic"
    Log(Tr("ntfy: topic created (stored in dota_accept.ini, section [ntfy])"))
}

; Sending does not block the tick: the request is asynchronous, we check the
; result a few seconds later and log only failures. The title is "Dota", not the
; topic: otherwise ntfy would insert the topic and the "password" would end up on
; the lock screen.
Ntfy(text, prio := "default", tags := "") {
    global optNtfy, ntfyServer, ntfyTopic, ntfyJobs
    if !optNtfy || ntfyTopic = ""
        return
    try {
        w := ComObject("WinHttp.WinHttpRequest.5.1")
        w.SetTimeouts(3000, 3000, 5000, 5000)
        w.Open("POST", ntfyServer . "/" . ntfyTopic, true)
        w.SetRequestHeader("Title", "Dota")
        w.SetRequestHeader("Priority", prio)
        if tags != ""
            w.SetRequestHeader("Tags", tags)
        w.Send(text)
        ntfyJobs.Push([w, text])
        SetTimer NtfyReap, -4000
    } catch as e {
        Log(Tr("ntfy: send failed — ") . e.Message)
    }
}

NtfyReap() {
    global ntfyJobs
    jobs := ntfyJobs
    ntfyJobs := []
    for j in jobs {
        try {
            if !j[1].WaitForResponse(0)
                Log(Tr("ntfy: no server response for [") . j[2] . Tr("]"))
            else if j[1].Status != 200
                Log(Tr("ntfy: server answered ") . j[1].Status . Tr(" for [") . j[2] . Tr("]"))
        } catch as e {
            Log(Tr("ntfy: send error for [") . j[2] . Tr("] — ") . e.Message)
        }
    }
}

; Exactly two notifications per match, to avoid burning the daily ntfy quota:
; "found and accepted" (after our click) and "did not work - accept it yourself"
; (if nothing was accepted within NTFY_FAIL_MS). "Found" alone is not sent.
NtfyMatchFail() {
    global readyDone, readyFail, NTFY_FAIL_MS
    if readyDone
        return                          ; already accepted by now
    readyFail := true
    Log(Tr("ntfy: not accepted within ") . Round(NTFY_FAIL_MS / 1000) . Tr(" s - alert"))
    Ntfy(Tr("Match found, auto-accept did not work — accept it yourself!"), "high",
         "rotating_light")
}

; The "not accepted within NTFY_FAIL_MS" alert (or "found but auto-accept is off"):
; armed once per lobby, from whichever path detected the ready-check.
ArmMatchAlert() {
    global curLobby, alertedFor, optMatch, readyFail, NTFY_FAIL_MS
    if curLobby = alertedFor
        return
    alertedFor := curLobby
    if optMatch
        SetTimer NtfyMatchFail, -NTFY_FAIL_MS
    else {
        readyFail := true
        Ntfy(Tr("Match found, auto-accept is off — accept it yourself!"), "high",
             "rotating_light")
    }
}

; Sometimes the lobby has appeared and the accept window is already on screen, but
; there is no ready-check line (7170) in the log yet: after a match was cancelled
; because someone did not load, the line arrived only 23 s later and only after a
; manual click. So 2.5 s after the lobby we look for the window on screen once a
; second, but only at a remembered button spot (with a width check), so that we do
; not click something random in the menu.
LobbyScan() {
    global lobbyWatch, lobbyAt, lobbyNext, readyDone, readyAt, optMatch
    if !lobbyWatch
        return
    age := A_TickCount - lobbyAt
    if readyDone || readyAt > lobbyAt || age > 45000 {
        lobbyWatch := false              ; the signal came: the normal path takes over
        return
    }
    if age < 2500 || A_TickCount < lobbyNext
        return
    lobbyNext := A_TickCount + 1000
    cands := FindAccept(true)
    if !cands.Length || cands[1].Length < 5
        return                          ; no button at a remembered spot
    lobbyWatch := false
    readyAt := A_TickCount
    Log(Tr("MATCH FOUND (by screen: lobby exists but no ready-up signal in the log)"))
    ArmMatchAlert()
    if optMatch
        TryAccept(Tr("match"), true)
}

NtfyCopy() {
    global ntfyTopic
    if ntfyTopic = ""
        return Note(Tr("No topic yet"), 2000, true)
    A_Clipboard := ntfyTopic
    Note(Tr("ntfy topic copied to the clipboard.`nIn the ntfy app: tap + and paste."), 5000, true)
}

NtfyTest() {
    global optNtfy
    if !optNtfy
        return Note(Tr("Notifications are off"), 2000, true)
    Ntfy(Tr("Connection check: notifications from your PC work"), "high", "white_check_mark")
    Note(Tr("Test notification sent"), 2000, true)
}


; ═══ HERO AUTO-PICK ═════════════════════════════════════════════════
;  Works next to the auto-accept and reads the same console.log of Dota.
;  The pick stage in the log:  C:Gamerules: entering state 'DOTA_GAMERULES_STATE_HERO_SELECTION'
;  The end of the stage:       ... 'DOTA_GAMERULES_STATE_STRATEGY_TIME'
;
;  optPickDelay (15 s) after the pick starts it reads the screen, takes the first
;  available hero (not crossed out = not banned, not gray = not taken by someone
;  else) and clicks the card and LOCK IN. If someone is at the PC (the mouse or
;  keyboard moved in the last 6 s) or Dota is covered by another window, it waits
;  and does not touch anything.
;
;  TWO SCREEN MODES (detected automatically, by icons and a label; the client
;  language does not matter: hero names are English in the Russian and Ukrainian
;  clients too, as checked in the game files):
;   - "MY HEROES" (Custom Layout sort): the strip is used left to right; English
;     client only (recognised by the "MY HEROES" label);
;   - standard grid (Attributes sort): the hero list from the settings window is
;     used. A hero's place in the grid comes from heroes_map.txt (built by
;     tools\build_hero_map.py from the game files; inside an attribute block the
;     heroes are alphabetical: Strength/Agility/Intelligence 6 per row, Universal 4).
;
;  Geometry was measured at 2560x1440 (a 16:9 window) and scales with the height:
;    card size 55x98; a crossed-out card has a pink-gray diagonal (RGB ~81,57,62)
;    from the bottom-left corner to the top-right one;
;    LOCK IN is at (0.762 of the width, 0.765 of the height); RANDOM is to its right,
;    do not click it.

; One-time import of the settings of the former stand-alone auto-pick script.
MigratePickIni() {
    global DOTA_INI
    old := A_ScriptDir . "\dota_pick.ini"
    if !FileExist(old) || IniRead(DOTA_INI, "pick", "migrated", "") != ""
        return
    for k in ["enabled", "delay_ms", "heroes"] {
        v := IniRead(old, "pick", k, "")
        if v != ""
            IniWrite v, DOTA_INI, "pick", k
    }
    IniWrite 1, DOTA_INI, "pick", "migrated"
}

LoadPickTemplate() {
    global TPL_ROWS
    f := A_ScriptDir . "\myheroes_tpl.txt"
    if !FileExist(f)
        return
    for rowtxt in StrSplit(FileRead(f), "`n", "`r")
        if rowtxt != ""
            TPL_ROWS.Push(rowtxt)
}

; Start and end of the hero selection stage, from the log lines.
PickEvents(txt) {
    global optPick, optPickDelay, inStage, picked, stageUntil, lastPool, baseSat, heroWant
    global stageAt, pickNote
    if txt = "" || !optPick
        return
    if InStr(txt, "entering state 'DOTA_GAMERULES_STATE_HERO_SELECTION'") {
        inStage := true, picked := false, lastPool := ""
        baseSat.Clear(), heroWant := []
        stageAt := A_TickCount, pickNote := ""
        stageUntil := A_TickCount + 120000
        Log(Tr("hero selection started; picking in ") . Round(optPickDelay / 1000) . Tr(" s"))
        PickShot("_0_start")
        SetTimer DoPick, -optPickDelay
        SetTimer PoolWatch, 1500
    }
    if inStage && InStr(txt, "entering state 'DOTA_GAMERULES_STATE_STRATEGY_TIME'") {
        inStage := false
        SetTimer DoPick, 0
        SetTimer PoolWatch, 0
        Log(Tr("hero selection stage ended") . (picked ? "" : Tr(" (no pick was made)")))
    }
}

; A frame of the Dota window as a BMP (about 15 MB), for analysis if a pick goes
; wrong. The last 12 are kept, older ones are deleted. Turn off: pick / shots = 0.
PickShot(tag) {
    global PICK_OUT, optPickShots
    if !optPickShots
        return
    try {
        DirCreate PICK_OUT
        WinGetPos &wx, &wy, &ww, &wh, "ahk_exe dota2.exe"
        SaveBmp(PICK_OUT . "\pick_" . FormatTime(, "HHmmss") . tag . ".bmp", wx, wy, ww, wh)
        lst := ""
        Loop Files PICK_OUT . "\pick_*.bmp"
            lst .= FileGetTime(A_LoopFilePath) . "|" . A_LoopFilePath . "`n"
        n := 0
        for ln in StrSplit(Sort(RTrim(lst, "`n"), "R"), "`n") {
            if ++n > 12
                try FileDelete(StrSplit(ln, "|")[2])
        }
    }
}

; ═══ SETTINGS WINDOW (right-click the tray icon -> "Settings…") ═══════════
ShowSettings(*) {
    global sg
    if IsObject(sg) {
        try {
            sg.Show()
            return
        }
        sg := ""
    }
    BuildSettings()
}

CloseSettings() {
    global sg
    try sg.Destroy()
    sg := ""
}

HasVal(arr, v) {
    for x in arr
        if x = v
            return true
    return false
}

IndexOf(arr, v) {
    for i, x in arr
        if x = v
            return i
    return 0
}

BuildSettings() {
    global sg, sgLV, sgLB, sgFilter, sgInfo, sgOrder, sgKeys, sgBuilding
    global optMatch, optInvite, optNtfy, optPick, optPickDelay, DOTA_LNK, HERO_NAME
    global optSteamFix, sgProf
    sgOrder := ResolveHeroes()
    sgKeys := []
    sgBuilding := false
    sg := Gui("-MaximizeBox", Tr("Dota auto-accept — settings"))
    sg.MarginX := 14, sg.MarginY := 12
    sg.OnEvent("Close", (*) => CloseSettings())
    tab := sg.Add("Tab3", "w650 h560", [Tr("General"), Tr("Auto-pick"), Tr("Steam accounts")])
    tab.UseTab(1)
    sg.Add("GroupBox", "x28 y48 w620 h130", Tr("Auto-accept"))
    c := sg.Add("Checkbox", "x48 y76 w580", Tr("Auto-accept matches (the match found window)"))
    c.Value := optMatch
    c.OnEvent("Click", (ctl, *) => SetOpt("match", ctl.Value))
    c := sg.Add("Checkbox", "x48 y106 w580", Tr("Auto-accept party invites"))
    c.Value := optInvite
    c.OnEvent("Click", (ctl, *) => SetOpt("invite", ctl.Value))
    c := sg.Add("Checkbox", "x48 y136 w580", Tr("Start with Windows"))
    c.Value := FileExist(DOTA_LNK) ? 1 : 0
    c.OnEvent("Click", (*) => StartupToggle())
    sg.Add("GroupBox", "x28 y190 w620 h150", Tr("Phone notifications (ntfy)"))
    c := sg.Add("Checkbox", "x48 y218 w580", Tr("Send: match found and accepted / auto-accept did not work"))
    c.Value := optNtfy
    c.OnEvent("Click", (ctl, *) => SetOpt("ntfy", ctl.Value))
    b := sg.Add("Button", "x48 y258 w210 h30", Tr("Copy ntfy topic"))
    b.OnEvent("Click", (*) => NtfyCopy())
    b := sg.Add("Button", "x268 y258 w210 h30", Tr("Send test notification"))
    b.OnEvent("Click", (*) => NtfyTest())
    sg.Add("Text", "x48 y300 w580 c808080", Tr("The topic works like the channel password: it is stored in dota_accept.ini and never logged."))
    b := sg.Add("Button", "x28 y360 w160 h30", Tr("Open log"))
    b.OnEvent("Click", (*) => OpenLog())
    sg.Add("Text", "x28 y418 w170", "Language / Язык / Мова:")   ; lang-names
    dd := sg.Add("DropDownList", "x200 y414 w180 Choose" . LangChoice(), LANG_ITEMS)
    dd.OnEvent("Change", (ctl, *) => SetLang(ctl.Value))
    tab.UseTab(2)
    c := sg.Add("Checkbox", "x28 y48 w300", Tr("Enable hero auto-pick"))
    c.Value := optPick
    c.OnEvent("Click", (ctl, *) => SetOpt("pick", ctl.Value))
    sg.Add("Text", "x340 y50 w134", Tr("Pick after (sec):"))
    ed := sg.Add("Edit", "x478 y46 w56 Number", Round(optPickDelay / 1000))
    ed.OnEvent("Change", (ctl, *) => SetPickDelay(ctl.Value))
    sg.Add("Text", "x28 y82 w610 h34", Tr("Attributes grid: tick the heroes; the order in the right-hand list is the priority (the first available one is taken). MY HEROES strip (Custom Layout): no list needed."))
    sg.Add("Text", "x28 y124 w60", Tr("Search:"))
    sgFilter := sg.Add("Edit", "x88 y120 w270")
    sgFilter.OnEvent("Change", (*) => FillHeroLV())
    sgLV := sg.Add("ListView", "x28 y154 w330 h340 Checked -Multi NoSortHdr", [Tr("Hero"), Tr("Attribute")])
    sgLV.OnEvent("ItemCheck", OnHeroCheck)
    sg.Add("Text", "x376 y124 w200", Tr("Pick order:"))
    sgLB := sg.Add("ListBox", "x376 y154 w210 h340")
    b := sg.Add("Button", "x594 y154 w44 h34", "▲")
    b.OnEvent("Click", (*) => MoveHero(-1))
    b := sg.Add("Button", "x594 y194 w44 h34", "▼")
    b.OnEvent("Click", (*) => MoveHero(1))
    b := sg.Add("Button", "x594 y234 w44 h34", "✕")
    b.OnEvent("Click", (*) => RemoveHero())
    b := sg.Add("Button", "x376 y504 w262 h30", Tr("Save hero list"))
    b.OnEvent("Click", (*) => SaveHeroes())
    sgInfo := sg.Add("Text", "x28 y510 w330 c808080", "")
    tab.UseTab(3)
    sg.Add("GroupBox", "x28 y48 w620 h168", Tr("Launch options in Steam"))
    c := sg.Add("Checkbox", "x48 y76 w580", Tr("Add the launch options (-condebug) to other Steam accounts"))
    c.Value := optSteamFix
    c.OnEvent("Click", (ctl, *) => SetOpt("steamfix", ctl.Value))
    sg.Add("Text", "x48 y106 w580 h50 c808080", Tr("Every Steam account has its own launch options. Only accounts Steam is not running under right now are touched; a copy localconfig.vdf.bak_dotaaccept is left next to the file. List of flags: dota_accept.ini, section [steam], flags."))
    b := sg.Add("Button", "x48 y166 w330 h30", Tr("Add -condebug now (restarts Steam)"))
    b.OnEvent("Click", (*) => AskSteamFix())
    sg.Add("GroupBox", "x28 y232 w620 h246", Tr("My Dota settings"))
    sgProf := sg.Add("Text", "x48 y260 w580", ProfileInfo())
    sg.Add("Text", "x48 y288 w580 h74 c808080", Tr("The profile is a copy of your Dota settings (keys, interface, video, hero grid, builds) from the account you are logged in with. While you play under that account it refreshes itself when Dota closes. When Steam moves to an account that is new to the script, the script offers to transfer the profile into it and switch Steam Cloud off for Dota."))
    b := sg.Add("Button", "x48 y376 w330 h30", Tr("Save settings of this account"))
    b.OnEvent("Click", (*) => SaveProfileClick())
    b := sg.Add("Button", "x48 y416 w330 h30", Tr("Transfer the profile to this account (restarts Steam)"))
    b.OnEvent("Click", (*) => ApplyProfileClick())
    tab.UseTab()
    FillHeroLV()
    RefreshOrder()
    sg.Show("w680 h600")
}

; What is selected in the language list: 1 is Auto, then LANGS in order.
LangChoice() {
    global LANGS, DOTA_INI
    i := IndexOf(LANGS, IniRead(DOTA_INI, "options", "lang", "auto"))
    return i ? i + 1 : 1
}

; The menus and windows are already built, so after a change the script
; restarts itself and opens the settings again.
SetLang(n) {
    global LANGS, DOTA_INI
    code := n = 1 ? "auto" : LANGS[n - 1]
    IniWrite code, DOTA_INI, "options", "lang"
    IniWrite 1, DOTA_INI, "state", "reopen"
    Log(Tr("interface language: ") . code)
    Reload
}

SetPickDelay(v) {
    global optPickDelay, DOTA_INI
    n := (v = "") ? 15 : Integer(v)
    n := Min(Max(n, 0), 60)
    optPickDelay := n * 1000
    IniWrite optPickDelay, DOTA_INI, "pick", "delay_ms"
}

FillHeroLV() {
    global sgLV, sgFilter, sgKeys, sgOrder, sgBuilding, HERO_ORDER, HERO_NAME
    f := Norm(sgFilter.Value)
    attrName := Map("S", Tr("Strength"), "A", Tr("Agility"), "I", Tr("Intelligence"), "U", Tr("Universal"))
    sgBuilding := true
    sgLV.Delete()
    sgKeys := []
    for attr in ["S", "A", "I", "U"] {
        if !HERO_ORDER.Has(attr)
            continue
        for key in HERO_ORDER[attr] {
            if f != "" && !InStr(Norm(HERO_NAME[key]), f)
                continue
            sgLV.Add(HasVal(sgOrder, key) ? "Check" : "", HERO_NAME[key], attrName[attr])
            sgKeys.Push(key)
        }
    }
    sgLV.ModifyCol(1, 190)
    sgLV.ModifyCol(2, 100)
    sgBuilding := false
}

OnHeroCheck(ctl, item, checked) {
    global sgKeys, sgOrder, sgBuilding
    if sgBuilding || item > sgKeys.Length
        return
    key := sgKeys[item]
    i := IndexOf(sgOrder, key)
    if checked && !i
        sgOrder.Push(key)
    else if !checked && i
        sgOrder.RemoveAt(i)
    RefreshOrder()
}

RefreshOrder(sel := 0) {
    global sgLB, sgOrder, HERO_NAME
    sgLB.Delete()
    for i, k in sgOrder
        sgLB.Add([i . ". " . HERO_NAME[k]])
    if sel && sel <= sgOrder.Length
        sgLB.Choose(sel)
}

MoveHero(d) {
    global sgLB, sgOrder
    i := sgLB.Value
    j := i + d
    if !i || j < 1 || j > sgOrder.Length
        return
    t := sgOrder[i], sgOrder[i] := sgOrder[j], sgOrder[j] := t
    RefreshOrder(j)
}

RemoveHero() {
    global sgLB, sgOrder, sgLV, sgKeys, sgBuilding
    i := sgLB.Value
    if !i
        return
    key := sgOrder[i]
    sgOrder.RemoveAt(i)
    r := IndexOf(sgKeys, key)
    if r {
        sgBuilding := true
        sgLV.Modify(r, "-Check")
        sgBuilding := false
    }
    RefreshOrder(Min(i, sgOrder.Length))
}

SaveHeroes() {
    global sgOrder, DOTA_INI, heroWant, sgInfo, HERO_NAME
    names := ""
    for k in sgOrder
        names .= (names = "" ? "" : ", ") . HERO_NAME[k]
    IniWrite names, DOTA_INI, "pick", "heroes"
    heroWant := ResolveHeroes()
    sgInfo.Value := Tr("Saved: ") . sgOrder.Length . Tr(" heroes")
    Log(Tr("auto-pick hero list: ") . (names = "" ? Tr("(empty)") : names))
}

Norm(t) {
    t := StrLower(RegExReplace(t, "[^\p{L}\p{N}]"))
    return StrReplace(t, Chr(0x451), Chr(0x435))   ; yo -> ye
}

LoadHeroMap() {
    global HERO_NAME, HERO_BYNAME, HERO_ORDER, HERO_ATTR
    f := A_ScriptDir . "\heroes_map.txt"
    if !FileExist(f)
        return false
    for ln in StrSplit(FileRead(f, "UTF-8"), "`n", "`r") {
        p := StrSplit(ln, "|")
        if p.Length < 4
            continue
        if p[1] = "N" && p.Length >= 6 {
            HERO_NAME[p[2]] := p[4]
            HERO_ATTR[p[2]] := p[3]
            HERO_BYNAME[Norm(p[4])] := p[2]
            HERO_BYNAME[Norm(p[5])] := p[2]
            HERO_BYNAME[Norm(p[6])] := p[2]
            HERO_BYNAME[Norm(StrReplace(p[2], "npc_dota_hero_"))] := p[2]
        } else if p[1] = "O" && p[2] = "en"
            HERO_ORDER[p[3]] := StrSplit(p[4], ",")
    }
    return HERO_ORDER.Count = 4
}

ResolveHeroes() {
    global HERO_BYNAME, HERO_NAME, DOTA_INI
    want := []
    for nm in StrSplit(IniRead(DOTA_INI, "pick", "heroes", ""), ",") {
        n := Norm(Trim(nm))
        if n = ""
            continue
        if HERO_BYNAME.Has(n)
            want.Push(HERO_BYNAME[n])
        else {
            ;            ; typo (1-2 letters): take the closest name, if there is only one such
            best := "", bestd := 99, tie := false
            for cand, key in HERO_BYNAME {
                if Abs(StrLen(cand) - StrLen(n)) > 2
                    continue
                d := EditDist(n, cand)
                if d < bestd
                    bestd := d, best := key, tie := false
                else if d = bestd && key != best
                    tie := true
            }
            if best != "" && !tie && bestd <= (StrLen(n) >= 8 ? 2 : 1) {
                want.Push(best)
                Log(Tr("in the heroes list [") . Trim(nm) . Tr("] was read as [") . HERO_NAME[best] . Tr("] (typo)"))
            } else
                Log(Tr("unknown name in the heroes list: [") . Trim(nm) . Tr("] (use the English name as in the game)"))
        }
    }
    return want
}

; Levenshtein distance between short strings.
EditDist(a, b) {
    la := StrLen(a), lb := StrLen(b)
    prev := []
    Loop lb + 1
        prev.Push(A_Index - 1)
    Loop la {
        i := A_Index
        cur := [i]
        Loop lb {
            j := A_Index
            cost := SubStr(a, i, 1) = SubStr(b, j, 1) ? 0 : 1
            cur.Push(Min(prev[j + 1] + 1, cur[j] + 1, prev[j] + cost))
        }
        prev := cur
    }
    return prev[lb + 1]
}

; 1:1 copy of a screen rectangle; BGRA buffer, rows from top to bottom.
GrabRegion(x, y, w, h) {
    hdcS := DllCall("GetDC", "ptr", 0, "ptr")
    hdcM := DllCall("CreateCompatibleDC", "ptr", hdcS, "ptr")
    hbm := DllCall("CreateCompatibleBitmap", "ptr", hdcS, "int", w, "int", h, "ptr")
    old := DllCall("SelectObject", "ptr", hdcM, "ptr", hbm, "ptr")
    px := 0
    if DllCall("BitBlt", "ptr", hdcM, "int", 0, "int", 0, "int", w, "int", h,
               "ptr", hdcS, "int", x, "int", y, "uint", 0x40CC0020) {
        bi := Buffer(40, 0)
        NumPut("uint", 40, bi, 0)
        NumPut("int", w, bi, 4)
        NumPut("int", -h, bi, 8)
        NumPut("ushort", 1, bi, 12)
        NumPut("ushort", 32, bi, 14)
        px := Buffer(w * h * 4, 0)
        if !DllCall("GetDIBits", "ptr", hdcM, "ptr", hbm, "uint", 0, "uint", h,
                    "ptr", px, "ptr", bi, "uint", 0)
            px := 0
    }
    DllCall("SelectObject", "ptr", hdcM, "ptr", old)
    DllCall("DeleteObject", "ptr", hbm)
    DllCall("DeleteDC", "ptr", hdcM)
    DllCall("ReleaseDC", "ptr", 0, "ptr", hdcS)
    return px
}

; A window frame as a 32-bit BMP (convert it to JPEG later).
SaveBmp(path, x, y, w, h) {
    hdcS := DllCall("GetDC", "ptr", 0, "ptr")
    hdcM := DllCall("CreateCompatibleDC", "ptr", hdcS, "ptr")
    hbm := DllCall("CreateCompatibleBitmap", "ptr", hdcS, "int", w, "int", h, "ptr")
    old := DllCall("SelectObject", "ptr", hdcM, "ptr", hbm, "ptr")
    DllCall("BitBlt", "ptr", hdcM, "int", 0, "int", 0, "int", w, "int", h,
            "ptr", hdcS, "int", x, "int", y, "uint", 0x40CC0020)
    bi := Buffer(40, 0)
    NumPut("uint", 40, bi, 0)
    NumPut("int", w, bi, 4)
    NumPut("int", h, bi, 8)
    NumPut("ushort", 1, bi, 12)
    NumPut("ushort", 32, bi, 14)
    size := w * h * 4
    px := Buffer(size)
    DllCall("GetDIBits", "ptr", hdcM, "ptr", hbm, "uint", 0, "uint", h,
            "ptr", px, "ptr", bi, "uint", 0)
    hdr := Buffer(14, 0)
    NumPut("ushort", 0x4D42, hdr, 0)
    NumPut("uint", 54 + size, hdr, 2)
    NumPut("uint", 54, hdr, 10)
    f := FileOpen(path, "w")
    f.RawWrite(hdr, 14)
    f.RawWrite(bi, 40)
    f.RawWrite(px, size)
    f.Close()
    DllCall("SelectObject", "ptr", hdcM, "ptr", old)
    DllCall("DeleteObject", "ptr", hbm)
    DllCall("DeleteDC", "ptr", hdcM)
    DllCall("ReleaseDC", "ptr", 0, "ptr", hdcS)
}

; Is the "MY HEROES" strip on screen: it exists only with the "Custom Layout" sort.
; With another sort (Attributes etc.) the first row of the ordinary hero grid lies in
; the same place, and a click would hit a random hero. It is recognised by the
; "MY HEROES" label: a template of the label's light pixels (145x24 at 1440p) is in
; myheroes_tpl.txt. Measured: 0.98-1.00 match on frames with the strip, 0.22-0.26 without.
HasMyHeroes() {
    global TPL_ROWS
    if !TPL_ROWS.Length
        return false
    try WinGetPos &wx, &wy, &ww, &wh, "ahk_exe dota2.exe"
    catch
        return false
    if !wh
        return false
    s := wh / 1440
    rw := Round(146 * s) + 2, rh := Round(25 * s) + 2
    buf := GrabRegion(wx + Round(175 * s), wy + Round(243 * s), rw, rh)
    if !buf
        return false
    inter := 0, nTpl := 0, nLive := 0
    for y, row in TPL_ROWS {
        py := Round((y - 1) * s)
        if py >= rh
            continue
        Loop 145 {
            px := Round((A_Index - 1) * s)
            if px >= rw
                continue
            o := (py * rw + px) * 4
            lit := (NumGet(buf, o, "UChar") + NumGet(buf, o + 1, "UChar") + NumGet(buf, o + 2, "UChar")) / 3 > 105
            t := SubStr(row, A_Index, 1) = "1"
            if t
                nTpl++
            if lit
                nLive++
            if t && lit
                inter++
        }
    }
    return nTpl && nLive && inter / nTpl >= 0.85 && inter / nLive >= 0.85
}

; Which pick screen: "standard" (grid by attribute), "strip" (the MY HEROES strip)
; or "". The standard grid is recognised by the colored attribute icons before the
; block headings (Strength red, Agility green, Intelligence blue): they are in the
; same place in every language, unlike labels. Measured: 45-133 icon pixels on
; standard-grid frames, 0 on frames with the MY HEROES strip.
DetectLayout() {
    global XB
    try WinGetPos &wx, &wy, &ww, &wh, "ahk_exe dota2.exe"
    catch
        return ""
    if !wh
        return ""
    s := wh / 1440
    cnt := Map("S", 0, "A", 0, "I", 0)
    rw := Round(1500 * s), rh := Round(24 * s)
    buf := GrabRegion(wx + Round(170 * s), wy + Round(243 * s), rw, rh)
    if buf {
        for k in ["S", "A", "I"] {
            cx := Round((XB[k] + 3 - 170) * s), cy := Round((253 - 243) * s)
            n := 0
            Loop 19 {
                y := cy - 9 + A_Index - 1
                if y < 0 || y >= rh
                    continue
                Loop 19 {
                    x := cx - 9 + A_Index - 1
                    if x < 0 || x >= rw
                        continue
                    o := (y * rw + x) * 4
                    b := NumGet(buf, o, "UChar"), g := NumGet(buf, o + 1, "UChar")
                    r := NumGet(buf, o + 2, "UChar")
                    if (k = "S" && r > 150 && r > g + 70 && r > b + 70)
                       || (k = "A" && g > 120 && g > r + 50 && g > b + 40)
                       || (k = "I" && b > 150 && b > r + 60 && b > g + 10)
                        n++
                }
            }
            cnt[k] := n
        }
    }
    ok := (cnt["S"] >= 25) + (cnt["A"] >= 25) + (cnt["I"] >= 8)
    if ok >= 2
        return "standard"
    return HasMyHeroes() ? "strip" : ""
}

; Top-left of a hero card in the grid (1440p units) or "".
CellOrigin(key) {
    global HERO_ORDER, XB
    for attr, arr in HERO_ORDER {
        for i, k in arr {
            if k = key {
                cols := attr = "U" ? 4 : 6
                idx := i - 1
                return [XB[attr] + Mod(idx, cols) * 66.5, 279 + (idx // cols) * 110.5]
            }
        }
    }
    return ""
}

; Card state in the grid: [0 available / 1 crossed out / 2 gray, saturation%, brightness]
CellState(key) {
    global baseSat
    o := CellOrigin(key)
    if o = ""
        return ""
    try WinGetPos &wx, &wy, &ww, &wh, "ahk_exe dota2.exe"
    catch
        return ""
    s := wh / 1440
    x0 := o[1], y0 := o[2]
    ox := Round((x0 - 6) * s), oy := Round((y0 - 4) * s)
    rw := Round(72 * s), rh := Round(112 * s)
    buf := GrabRegion(wx + ox, wy + oy, rw, rh)
    if !buf
        return ""
    hits := 0
    for k in [20, 35, 50, 65, 80] {
        t := k / 100
        xl := Round((x0 + 49 * t) * s) - ox
        yl := Round((y0 + 100 - 101 * t) * s) - oy
        best := 999
        Loop 9 {
            xx := xl + A_Index - 5
            if xx < 0 || xx >= rw || yl < 0 || yl >= rh
                continue
            q := (yl * rw + xx) * 4
            d := Max(Abs(NumGet(buf, q + 2, "UChar") - 81)
                   , Abs(NumGet(buf, q + 1, "UChar") - 57)
                   , Abs(NumGet(buf, q, "UChar") - 62))
            if d < best
                best := d
        }
        if best <= 12
            hits++
    }
    sumV := 0, sumS := 0, n := 0
    for yy in [10, 16, 22, 28, 34, 40, 46, 52, 58, 64] {
        for xx in [8, 13, 18, 23, 28, 33, 38, 43, 48] {
            px := Round((x0 + xx) * s) - ox, py := Round((y0 + yy) * s) - oy
            if px < 0 || px >= rw || py < 0 || py >= rh
                continue
            q := (py * rw + px) * 4
            b := NumGet(buf, q, "UChar"), g := NumGet(buf, q + 1, "UChar")
            r := NumGet(buf, q + 2, "UChar")
            mx := Max(r, g, b), mn := Min(r, g, b)
            sumV += mx
            sumS += mx ? (mx - mn) / mx : 0
            n++
        }
    }
    sat := n ? 100 * sumS / n : 0
    v := n ? sumV / n : 0
    ;    ; gray = taken by someone else: saturation almost zero, or a strong drop
    ;    ; against the start of the pick (heroes with pale art have low saturation anyway)
    gray := sat < 8 || (baseSat.Has(key) && baseSat[key] > 15 && sat < 0.5 * baseSat[key])
    return [hits >= 4 ? 1 : (gray ? 2 : 0), Round(sat, 1), Round(v)]
}

; State of the 6 pool cards: [state, brightness, saturation%]
; state: 0 available, 1 crossed out (banned), 2 gray (taken by someone else).
; Returns "" if the window could not be read.
PoolStatus() {
    try WinGetPos &wx, &wy, &ww, &wh, "ahk_exe dota2.exe"
    catch
        return ""
    if !wh
        return ""
    s := wh / 1440
    ox := Round(178 * s), oy := Round(270 * s)
    rw := Round(420 * s), rh := Round(120 * s)
    buf := GrabRegion(wx + ox, wy + oy, rw, rh)
    if !buf
        return ""
    res := []
    Loop 6 {
        x0 := 184 + 65 * (A_Index - 1)
        hits := 0
        for k in [20, 35, 50, 65, 80] {
            t := k / 100
            xl := Round((x0 + 49 * t) * s) - ox
            yl := Round((278 + 100 - 101 * t) * s) - oy
            best := 999
            Loop 7 {
                xx := xl + A_Index - 4
                if xx < 0 || xx >= rw || yl < 0 || yl >= rh
                    continue
                o := (yl * rw + xx) * 4
                d := Max(Abs(NumGet(buf, o + 2, "UChar") - 81)
                       , Abs(NumGet(buf, o + 1, "UChar") - 57)
                       , Abs(NumGet(buf, o, "UChar") - 62))
                if d < best
                    best := d
            }
            if best <= 10
                hits++
        }
        ;        ; brightness and saturation of the middle of the card (without the number and the icon below)
        sumV := 0, sumS := 0, n := 0
        for yy in [288, 296, 304, 312, 320, 328, 336, 344] {
            for xx in [x0 + 8, x0 + 16, x0 + 24, x0 + 32, x0 + 40, x0 + 48] {
                px := Round(xx * s) - ox, py := Round(yy * s) - oy
                if px < 0 || px >= rw || py < 0 || py >= rh
                    continue
                o := (py * rw + px) * 4
                b := NumGet(buf, o, "UChar"), g := NumGet(buf, o + 1, "UChar")
                r := NumGet(buf, o + 2, "UChar")
                mx := Max(r, g, b), mn := Min(r, g, b)
                sumV += mx
                sumS += mx ? (mx - mn) / mx : 0
                n++
            }
        }
        v := n ? Round(sumV / n) : 0
        sat := n ? Round(100 * sumS / n) : 0
        state := hits >= 4 ? 1 : (sat < 10 ? 2 : 0)
        res.Push([state, v, sat])
    }
    return res
}

; Mean brightness of a rectangle given in window fractions (it shows that the
; LOCK IN button changed after a hero was selected).
RegionMean(fx, fy, fw, fh) {
    try WinGetPos &wx, &wy, &ww, &wh, "ahk_exe dota2.exe"
    catch
        return -1
    x := wx + Round(fx * ww), y := wy + Round(fy * wh)
    w := Round(fw * ww), h := Round(fh * wh)
    buf := GrabRegion(x, y, w, h)
    if !buf
        return -1
    sum := 0, n := 0
    Loop h // 4 {
        yy := (A_Index - 1) * 4
        Loop w // 4 {
            o := (yy * w + (A_Index - 1) * 4) * 4
            sum += NumGet(buf, o, "UChar") + NumGet(buf, o + 1, "UChar") + NumGet(buf, o + 2, "UChar")
            n++
        }
    }
    return n ? Round(sum / n / 3) : -1
}

; ── click without the mouse: messages to the Dota window, the cursor does not move ──
PickClick(x, y) {
    try {
        WinGetPos &wx, &wy, , , "ahk_exe dota2.exe"
        lp := (((y - wy) & 0xFFFF) << 16) | ((x - wx) & 0xFFFF)
        lp0 := (((y - wy - 8) & 0xFFFF) << 16) | ((x - wx - 12) & 0xFFFF)
        PostMessage 0x0200, 0, lp0, , "ahk_exe dota2.exe"
        Sleep 70
        PostMessage 0x0200, 0, lp, , "ahk_exe dota2.exe"
        Sleep 150
        PostMessage 0x0200, 0, lp, , "ahk_exe dota2.exe"
        Sleep 60
        PostMessage 0x0201, 1, lp, , "ahk_exe dota2.exe"
        Sleep 60
        PostMessage 0x0202, 0, lp, , "ahk_exe dota2.exe"
        return true
    }
    return false
}

CardCenter(i) {          ; i = 1..6
    WinGetPos &wx, &wy, &ww, &wh, "ahk_exe dota2.exe"
    s := wh / 1440
    return [wx + Round((184 + 65 * (i - 1) + 27) * s), wy + Round((278 + 49) * s)]
}

LockCenter() {
    WinGetPos &wx, &wy, &ww, &wh, "ahk_exe dota2.exe"
    return [wx + Round(0.762 * ww), wy + Round(0.765 * wh)]
}

; ── the pick itself ─────────────────────────────────────────────────
; What the pick screen looks like (measured on frames, brightness 0-255):
;  right-hand hero panel (the hero picture): no hero selected ~0, selected ~80;
;  LOCK IN button: nothing selected ~37, selected and active ~92, selected but dim
;  (e.g. "waiting for the other team", or someone in the team already picked) ~49;
;  after pressing LOCK IN the screen changes and the button is darker than 30.
; So "a hero is selected" is judged by the PANEL, and "it can be locked in" by the
; button: we select and wait until the button lights up.
LockBtn() {
    return RegionMean(0.70, 0.735, 0.14, 0.058)
}

HeroPanel() {
    return RegionMean(0.711, 0.215, 0.078, 0.215)
}

; State of a candidate's card (0 free, 1 banned, 2 gray), "" = not read.
; chk: ["std", hero key] for the grid or ["strip", number] for the MY HEROES strip.
CandState(chk) {
    if chk[1] = "std" {
        st := CellState(chk[2])
        return st = "" ? "" : st[1]
    }
    st := PoolStatus()
    return (st = "" || chk[2] > st.Length) ? "" : st[chk[2]][1]
}

; One attempt. Returns:
; 1 - the hero was selected and locked in (LOCK IN confirmed),
; 0 - the selection did not register (card unavailable: gray, banned): take the next,
; 2 - selected and LOCK IN pressed, but no confirmation,
; 3 - selected, but the LOCK IN button never lit up before the stage ended.
; If a hero is selected but the button is dim (someone in the team already picked
; instead of us, the round ended, etc.), we just wait until it lights up and press it.
PickTry(name, cc, chk) {
    global inStage
    lk := LockCenter()
    p0 := HeroPanel()
    Log(Tr("clicking ") . name . Tr(" at ") . cc[1] . "," . cc[2])
    PickClick(cc[1], cc[2])
    sel := false
    Loop 8 {
        Sleep 250
        p := HeroPanel()
        if p > 40 && (p0 < 20 || Abs(p - p0) > 3) {
            sel := true
            break
        }
    }
    b1 := LockBtn()
    PickShot("_a_card")
    if !sel {
        Log(Tr("selection did not register: hero panel ") . p0 . " -> " . p . Tr(", button ") . b1
            . " (" . name . Tr(" unavailable?) - taking the next one"))
        return 0
    }
    Log(name . Tr(" selected (panel ") . p . Tr("), LOCK IN button: ") . b1)
    t0 := A_TickCount, shotAt := A_TickCount
    chkAt := 0, lostN := 0, reclickAt := 0, lastCs := ""
    while b1 < 70 {
        if !inStage || A_TickCount - t0 > 90000 {
            Log(Tr("LOCK IN button never lit up before the stage ended (") . b1 . ")")
            PickShot("_nolock")
            return 3
        }
        if A_TickCount - t0 > 1500 && A_TickCount - shotAt > 6000 {
            shotAt := A_TickCount
            Log(Tr("waiting for LOCK IN to light up (brightness ") . b1 . ")")
            PickShot("_wait")
        }
        Sleep 250
        b1 := LockBtn()
        if b1 >= 70
            break
        ;        ; What exactly changed while we wait:
        ;        ;  a) the hero card turned gray or banned: the other team took it, so take
        ;        ;     the next candidate;
        ;        ;  b) only the LOCK IN button went dim (someone in our team already picked,
        ;        ;     the second round began): keep the hero and wait until the button lights
        ;        ;     up again;
        ;        ;  c) the hero panel disappeared but the card is free: the selection was
        ;        ;     reset, click it again.
        ;        ; "Gray" counts only if two reads in a row showed it.
        if A_TickCount - chkAt > 600 {
            chkAt := A_TickCount
            cs := CandState(chk)
            if cs != lastCs {
                lastCs := cs
                Log(Tr("card ") . name . Tr(" while waiting: ") . (cs = 1 ? Tr("banned") : cs = 2 ? Tr("gray") : cs = "" ? Tr("not read") : Tr("free"))
                    . Tr(", button ") . b1)
            }
            if cs = 1 || cs = 2 {
                if ++lostN >= 2 {
                    Log(name . ": " . (cs = 1 ? Tr("banned") : Tr("taken by the other team (card is gray)")) . Tr(" - taking the next one"))
                    PickShot("_lost")
                    return 0
                }
            } else {
                lostN := 0
                if cs = 0 && HeroPanel() < 15 && A_TickCount - reclickAt > 3000 {
                    reclickAt := A_TickCount
                    Log(Tr("hero panel disappeared, card ") . name . Tr(" is free - selecting again"))
                    PickClick(cc[1], cc[2])
                    Sleep 500
                }
            }
        }
    }
    Loop 3 {
        Log(Tr("LOCK IN button is lit (") . b1 . Tr("); pressing LOCK IN at ") . lk[1] . "," . lk[2])
        PickClick(lk[1], lk[2])
        Sleep 1200
        b2 := LockBtn()
        Log(Tr("button brightness after LOCK IN: ") . b2)
        if b2 < b1 - 30 {
            PickShot("_b_lock")
            return 1
        }
    }
    PickShot("_b_lock")
    return 2
}

DoPick() {
    global optPick, picked, inStage, HERO_NAME, stageAt, PICK_DEADLINE_MS, pickNote
    if !inStage || picked
        return
    if !optPick {
        picked := true
        Log(Tr("auto-pick is off - not touching anything"))
        return
    }
    if PICK_DEADLINE_MS - (A_TickCount - stageAt) < 3000 {
        picked := true
        Log(Tr("the first round is over (gold penalty next) - too late"))
        return
    }
    ;    ; Someone is at the PC: wait, maybe they will pick themselves; but the penalty will not wait.
    if A_TimeIdlePhysical < 6000 {
        if pickNote != "idle" {
            pickNote := "idle"
            Log(Tr("someone is at the PC (mouse/keyboard ") . A_TimeIdlePhysical
                . Tr(" ms ago) - waiting, maybe you will pick yourself"))
        }
        SetTimer DoPick, -3000
        return
    }
    try WinGetPos &wx, &wy, &ww, &wh, "ahk_exe dota2.exe"
    catch {
        Log(Tr("Dota window not found"))
        picked := true
        return
    }
    if Abs(ww / wh - 16 / 9) > 0.05 {
        picked := true
        Log(Tr("window is not 16:9 (") . ww . "x" . wh . Tr(") - layout not measured, not touching anything"))
        return
    }
    c1 := CardCenter(1)
    if !Under(c1[1], c1[2]) {
        if pickNote != "covered" {
            pickNote := "covered"
            Log(Tr("Dota is covered by another window - nothing to read, waiting"))
        }
        SetTimer DoPick, -3000
        return
    }
    lay := DetectLayout()
    if lay = "" {
        if pickNote != "nolayout" {
            pickNote := "nolayout"
            Log(Tr("pick screen not recognised yet - waiting (needs the Attributes or Custom Layout sort)"))
            PickShot("_unknown")
        }
        SetTimer DoPick, -3000
        return
    }
    Log(Tr("pick screen: ") . lay)
    ;    ; Candidates in priority order: [name, card center]. Unavailable ones by color
    ;    ; (banned/gray) are skipped; if the color is wrong, the LOCK IN check in PickTry
    ;    ; will catch it and we go to the next one.
    cands := []
    if lay = "standard" {
        want := ResolveHeroes()
        if !want.Length {
            picked := true
            Log(Tr("standard grid, but the hero list is empty - not touching anything"))
            return
        }
        s := wh / 1440
        for key in want {
            st := CellState(key)
            if st = "" {
                Log(HERO_NAME[key] . Tr(": card not read"))
                continue
            }
            Log(HERO_NAME[key] . ": " . (st[1] = 1 ? Tr("CROSSED OUT (banned)") : st[1] = 2 ? Tr("GRAY (taken)") : Tr("available"))
                . Tr(" (saturation ") . st[2] . Tr("%, brightness ") . st[3] . ")")
            if st[1] = 0 {
                o := CellOrigin(key)
                cands.Push([HERO_NAME[key], [wx + Round((o[1] + 27) * s), wy + Round((o[2] + 49) * s)], ["std", key]])
            }
        }
    } else {
        st := PoolStatus()
        if st = "" {
            Log(Tr("pool not read"))
            SetTimer DoPick, -3000
            return
        }
        txt := ""
        for i, c in st {
            txt .= " [" . i . (c[1] = 1 ? Tr(" CROSSED OUT") : c[1] = 2 ? Tr(" GRAY") : " ok")
                . " v" . c[2] . " s" . c[3] . "]"
            if c[1] = 0
                cands.Push([Tr("#") . i . Tr(" of the pool"), CardCenter(i), ["strip", i]])
        }
        Log(Tr("pool:") . txt)
    }
    if !cands.Length {
        picked := true
        Log(Tr("none of the heroes in the list is available - not picking"))
        return
    }
    unsure := ""
    for c in cands {
        if !inStage || PICK_DEADLINE_MS - (A_TickCount - stageAt) < 1500
            break
        r := PickTry(c[1], c[2], c[3])
        if r = 1 {
            picked := true
            Log(Tr("hero picked: ") . c[1])
            return
        }
        if r = 3 {
            picked := true
            Log(Tr("picked ") . c[1] . Tr(" but could not lock it in (the button never lit up)"))
            return
        }
        if r = 2 {
            unsure := c[1]
            break
        }
    }
    if unsure != "" {
        picked := true
        Log(Tr("picked ") . unsure . Tr(" but LOCK IN was not confirmed - check by hand"))
        return
    }
    Log(Tr("no attempt worked - retrying in 4 s if there is time before the round ends"))
    SetTimer DoPick, -4000
}

PoolWatch() {
    global inStage, lastPool, stageUntil, HERO_NAME
    if !inStage || A_TickCount > stageUntil {
        SetTimer PoolWatch, 0
        return
    }
    global heroWant, baseSat
    lay := DetectLayout()
    if lay = "standard" {
        if !heroWant.Length
            heroWant := ResolveHeroes()
        if !baseSat.Count {
            for key in heroWant {           ; saturation at the start of the pick = reference point
                st := CellState(key)
                if st != "" && st[1] = 0
                    baseSat[key] := st[2]
            }
        }
        key2 := "", txt := ""
        for key in heroWant {
            st := CellState(key)
            if st = ""
                continue
            key2 .= st[1]
            txt .= " [" . HERO_NAME[key] . (st[1] = 1 ? Tr(" CROSSED OUT") : st[1] = 2 ? Tr(" GRAY") : " ok")
                . " s" . st[2] . "]"
        }
        if key2 != lastPool {
            lastPool := key2
            Log(Tr("heroes from the list:") . txt)
        }
        return
    }
    st := PoolStatus()
    if st = ""
        return
    key := "", txt := ""
    for i, c in st {
        key .= c[1]
        txt .= " [" . i . (c[1] = 1 ? Tr(" CROSSED OUT") : c[1] = 2 ? Tr(" GRAY") : " ok")
            . " v" . c[2] . " s" . c[3] . "]"
    }
    if key != lastPool {
        lastPool := key
        Log(Tr("pool changed:") . txt)
    }
}

; ── tray ───────────────────────────────────────────────────────────
BuildTray() {
    global M_MATCH, M_INV, M_PAUSE, M_RUN, M_LOG
    global M_NTFY, M_NTFYCOPY, M_NTFYTEST, M_SETTINGS, M_PICK
    t := A_TrayMenu
    t.Delete()
    t.Add(M_SETTINGS, ShowSettings)
    t.Add()
    t.Add(M_MATCH, (*) => ToggleOpt("match"))
    t.Add(M_INV, (*) => ToggleOpt("invite"))
    t.Add(M_PICK, (*) => ToggleOpt("pick"))
    t.Add(M_NTFY, (*) => ToggleOpt("ntfy"))
    t.Add(M_NTFYCOPY, (*) => NtfyCopy())
    t.Add(M_NTFYTEST, (*) => NtfyTest())
    t.Add()
    t.Add(M_PAUSE, (*) => TogglePause())
    t.Add(M_RUN, (*) => StartupToggle())
    t.Add(M_LOG, (*) => OpenLog())
    t.Add()
    t.Add(Tr("Exit"), (*) => ExitApp())
    t.Default := M_SETTINGS
    Status()
}

Status() {
    global dotaPause, dotaLive, clogOk, optMatch, optInvite, optNtfy, optPick
    global M_MATCH, M_INV, M_PAUSE, M_RUN, M_NTFY, M_PICK, DOTA_LNK, issues
    s := dotaPause ? Tr("paused")
       : issues.Count ? Tr("PROBLEM: ") . IssueText()
       : dotaLive != 1 ? Tr("Dota is not running, waiting")
       : clogOk ? Tr("armed (reading the Dota log)")
       : Tr("looking for the Dota log")
    A_IconTip := SubStr("Dota auto-accept — " . s, 1, 127)
    UpdateIcon()
    try {
        t := A_TrayMenu
        for item, on in Map(M_MATCH, optMatch, M_INV, optInvite,
                            M_NTFY, optNtfy, M_PICK, optPick,
                            M_PAUSE, dotaPause, M_RUN, FileExist(DOTA_LNK)) {
            if on
                t.Check(item)
            else
                t.Uncheck(item)
        }
    }
}

ToggleOpt(which) {
    global optMatch, optInvite, optNtfy, optPick
    cur := which = "ntfy" ? optNtfy : which = "match" ? optMatch
         : which = "invite" ? optInvite : optPick
    SetOpt(which, !cur)
}

SetOpt(which, val) {
    global optMatch, optInvite, optNtfy, optPick, optSteamFix, DOTA_INI
    v := val ? 1 : 0
    if which = "steamfix" {
        optSteamFix := v
        IniWrite v, DOTA_INI, "steam", "fix"
        Log(Tr("launch options of other Steam accounts: ") . (v ? Tr("adding") : Tr("leaving alone")))
        if v
            SetTimer FixSteamAccounts, -300
    } else if which = "ntfy" {
        optNtfy := v
        IniWrite v, DOTA_INI, "options", "ntfy"
        Log(Tr("ntfy notifications: ") . (v ? Tr("on") : Tr("off")))
    } else if which = "match" {
        optMatch := v
        IniWrite v, DOTA_INI, "options", "match"
        Log(Tr("auto-accept of matches: ") . (v ? Tr("on") : Tr("off")))
    } else if which = "invite" {
        optInvite := v
        IniWrite v, DOTA_INI, "options", "invite"
        Log(Tr("auto-accept of party invites: ") . (v ? Tr("on") : Tr("off")))
    } else if which = "pick" {
        optPick := v
        IniWrite v, DOTA_INI, "pick", "enabled"
        Log(Tr("hero auto-pick: ") . (v ? Tr("on") : Tr("off")))
    }
    Status()
}

TogglePause(*) {
    global dotaPause
    dotaPause := !dotaPause
    Log(dotaPause ? Tr("PAUSED manually") : Tr("auto again"))
    Status()
    Note(dotaPause ? Tr("Dota auto-accept: PAUSED`n(Ctrl+Alt+P to resume)")
                   : Tr("Dota auto-accept: active"))
}

^!p::TogglePause()

; ── main tick ──────────────────────────────────────────────────────
Tick() {
    global DOTA_EXE, DOTA_POLL, DOTA_IDLE
    global dotaLive, dotaPause, clogPath, clogPos, clogOk, clogSaid
    global CLOG_READY, CLOG_MINE, CLOG_START, CLOG_INV, CLOG_INVOK
    global readyAt, readyDone, readyTries, invAt, invDone, invTried
    global READY_GAP, curLobby, lastTry, CLOG_TRIES, RETRY_MS
    global optMatch, optInvite, readyFail, alertedFor, NTFY_FAIL_MS
    global invPending, invUntil, invRetryAt, invMissLogged
    global issues, dotaSince, lastGrow, lobbyAt, lobbyWatch, lobbyNext
    static lastBeat := A_TickCount

    live := ProcessExist(DOTA_EXE) ? 1 : 0
    if live != dotaLive {
        dotaLive := live
        ;        ; Look for the log again: a new Dota session has a new one, and the
        ;        ; position must be set to its end again.
        clogOk := false, clogPos := 0
        readyDone := false, invDone := false
        inStage := false
        clogSaid := false
        issues.Clear()
        dotaSince := A_TickCount
        Log(live ? Tr("Dota started — armed") : Tr("Dota closed — sleeping"))
        if !live
            SetTimer ProfileAutoSave, -5000
        Status()
        SetTimer Tick, live ? DOTA_POLL : DOTA_IDLE
        if live
            CheckLaunchOpts()
    }
    if !live || dotaPause
        return
    ;    ; Heartbeat every 15 minutes: the last "alive" line shows when the script
    ;    ; stopped if it ever dies silently.
    if A_TickCount - lastBeat > 900000 {
        lastBeat := A_TickCount
        Log(Tr("alive"))
    }

    if !clogOk {
        clogPath := ClogFind()
        if clogPath != "" {
            try clogPos := FileGetSize(clogPath)
            SeedLobbies(clogPath)
            clogOk := true
            lastGrow := A_TickCount
            DelIssue("nolog")
            Log(Tr("Dota log found, working from it: ") . clogPath)
            Status()
        } else {
            ;            ; The log does not appear right after launch: give Dota 90 seconds.
            if !clogSaid && A_TickCount - dotaSince > 90000 {
                clogSaid := true
                Log(Tr("Dota's console.log was not found 90 s after launch. ")
                    . Tr("Check -condebug in the launch options (Steam → Dota 2 ")
                    . Tr("→ Properties) and restart it"))
                if !issues.Has("opts") {
                    AddIssue("nolog", Tr("Dota's console.log not found"))
                    Hint(Tr("The script cannot see Dota 2's log. Make sure the launch options ")
                         . Tr("contain -condebug, then restart Dota."))
                }
            }
            return
        }
    }
    _new := ClogNew()
    PickEvents(_new)
    ;    ; Watchdog: in the menu and in a match Dota writes to the log at least about
    ;    ; once a minute (measured: the longest silence in 2 hours was 61 s). 5+ minutes
    ;    ; of silence means the wrong log is read or Dota is hung; the icon shows "II".
    if _new != "" {
        lastGrow := A_TickCount
        if issues.Has("silent") {
            DelIssue("silent")
            Log(Tr("Dota log is flowing again"))
        }
    } else if A_TickCount - lastGrow > 300000 && !issues.Has("silent") {
        AddIssue("silent", Tr("Dota log silent for 5+ minutes"))
        Log(Tr("Dota log silent for 5+ minutes — the script may be blind"))
    }
    if _new = "" {
        InvRetry()
        LobbyScan()
        return
    }
    if InStr(_new, CLOG_MINE) {
        SetTimer NtfyMatchFail, 0       ; you accepted yourself: no alert needed
        readyDone := true               ; accepted by you, nothing for us to do
        readyAt := A_TickCount
    }
    if InStr(_new, CLOG_START)
        Log(Tr("server assigned — match is starting"))
    ;    ; PARTY. Its own event, separate from the ready-check: an invite arrives both
    ;    ; in the menu and in the middle of a match. Every subscription to Invite is a
    ;    ; new invite, even if someone answered the previous one a second ago (a friend
    ;    ; re-sent the party); only a duplicate line within 1.5 s is dropped. The order
    ;    ; inside the log chunk decides what came later.
    _pOk := InStr(_new, CLOG_INVOK, , -1)
    _pInv := InStr(_new, CLOG_INV, , -1)
    if _pOk {
        invDone := true                 ; answered by you or by us
        invPending := false
    }
    if _pInv > _pOk {
        if A_TickCount - invAt > 1500 {
            invDone := false, invTried := 0
            invPending := true, invUntil := A_TickCount + 40000
            invRetryAt := A_TickCount + 1000, invMissLogged := false
            Log(optInvite ? Tr("PARTY INVITE (log)")
                : Tr("PARTY INVITE — auto-accept is off, leaving it alone"))
        }
        invAt := A_TickCount
        if !invDone && optInvite
            TryAccept(Tr("party"))
    }
    ;    ; A new lobby is a different match, and the only reliable sign of it.
    _lob := LobbyId(_new)
    if _lob != "" && _lob != curLobby {
        curLobby := _lob
        if !seenLobbies.Has(_lob) {
            seenLobbies[_lob] := true
            readyDone := false, readyTries := 0, lastTry := 0
            readyFail := false
            lobbyAt := A_TickCount, lobbyWatch := true, lobbyNext := 0
            Log(Tr("new lobby ") . _lob)
        }
    }
    if InStr(_new, CLOG_READY) {
        ;        ; All candidates missed: try again after RETRY_MS: the window stays up
        ;        ; for ~25 seconds, and we keep clicking until the game registers it.
        if optMatch && !readyDone && readyTries >= CLOG_TRIES
           && A_TickCount - lastTry > RETRY_MS {
            readyTries := 0
            Log(Tr("window is still up — trying candidates again"))
        }
        if A_TickCount - readyAt > READY_GAP {
            ;            ; A new ready-check only if there was no signal for a long time:
            ;            ; while candidates were being tried, the same match could look new,
            ;            ; and the cursor jumped five more times after the accept.
            readyDone := false, readyTries := 0, readyFail := false
            Log(optMatch ? Tr("MATCH FOUND (log: ready-check)")
                : Tr("MATCH FOUND — auto-accept is off, leaving it alone"))
        }
        readyAt := A_TickCount
        if !readyDone
            ArmMatchAlert()
        if !readyDone && optMatch
            TryAccept()
    }
    InvRetry()
    LobbyScan()
}

StartupToggle(*) {
    global DOTA_LNK
    if FileExist(DOTA_LNK) {
        try FileDelete(DOTA_LNK)
        Log(Tr("removed from startup"))
        Note(Tr("No longer starts with Windows"), 2500, true)
    } else {
        try {
            FileCreateShortcut(A_ScriptFullPath, DOTA_LNK, A_ScriptDir)
            Log(Tr("added to startup"))
            Note(Tr("Now starts with Windows"), 2500, true)
        } catch as e {
            Note(Tr("could not create the shortcut:`n") . e.Message, 4000, true)
        }
    }
    Status()
}

OpenLog(*) {
    global DOTA_LOGF
    if !FileExist(DOTA_LOGF)
        return Note(Tr("the log is empty so far"), 2000, true)
    try Run(DOTA_LOGF)
}

; CLICKING. Called when the log says a ready-check is on. We click a candidate
; and WAIT FOR CONFIRMATION: Dota itself logs our click as Send 7070. No
; confirmation means a miss, and we take the next candidate.
; SILENT CLICK. We post click messages to the Dota window in its own
; coordinates, the cursor is not touched at all. Panorama may ignore them, so
; this is only the first attempt: if the log does not confirm, a real click is
; made. slow is for popups: a fast move-then-click (20 ms) was not accepted on
; the party popup, probably because Panorama applies :hover on the next frame,
; so we approach the button in two steps and give it time to highlight.
ClickSilent(x, y, slow := false) {
    global DOTA_WIN
    try {
        WinGetPos &wx, &wy, , , DOTA_WIN
        lp := (((y - wy) & 0xFFFF) << 16) | ((x - wx) & 0xFFFF)
        if slow {
            lp0 := (((y - wy - 8) & 0xFFFF) << 16) | ((x - wx - 12) & 0xFFFF)
            PostMessage 0x0200, 0, lp0, , DOTA_WIN
            Sleep 70
            PostMessage 0x0200, 0, lp, , DOTA_WIN
            Sleep 120
            PostMessage 0x0200, 0, lp, , DOTA_WIN
            Sleep 60
        } else {
            PostMessage 0x0200, 0, lp, , DOTA_WIN          ; WM_MOUSEMOVE
            Sleep 20
        }
        PostMessage 0x0201, 1, lp, , DOTA_WIN          ; WM_LBUTTONDOWN
        Sleep slow ? 60 : 30
        PostMessage 0x0202, 0, lp, , DOTA_WIN          ; WM_LBUTTONUP
        return true
    }
    return false
}

; ── the ACCEPT button in the invite popup ──────────────────────────
; Measured on a live invite: the button is GRAY (~0x3b4248), not green, so a
; search for green does not see it. The invite window is centered and the
; button sits at fixed fractions of the window: x 0.373-0.492, y 0.606-0.647
; (DECLINE starts to the right, from 0.51). We click the center of ACCEPT, but
; only if the corner points of the button are gray: a check that the button is
; there at all, so as not to click into the game when there is no window.
PARTY_BX := 0.430
PARTY_BY := 0.626

PartyGray(c) {
    if c = -1
        return false
    r := (c >> 16) & 0xFF, g := (c >> 8) & 0xFF, b := c & 0xFF
    return r >= 0x28 && b <= 0x58 && g >= r && b - r >= 3 && b - r <= 18
}

PartyGate(wx, wy, ww, wh) {
    n := 0
    for d in [[0.385, 0.613], [0.475, 0.613], [0.385, 0.640], [0.475, 0.640]]
        if PartyGray(Px(wx + Round(ww * d[1]), wy + Round(wh * d[2])))
            n++
    return n >= 3
}

; The window is not drawn instantly after the log line, so wait up to ~1.2 s.
; If it is not found, Tick retries once a second (see InvRetry): Dota may be
; covered by another window, and the popup is visible only once you return.
PartyCands(wx, wy, ww, wh, tries := 8) {
    global PARTY_BX, PARTY_BY
    Loop tries {
        cx := wx + Round(ww * PARTY_BX)
        cy := wy + Round(wh * PARTY_BY)
        if PartyGate(wx, wy, ww, wh) && Under(cx, cy)
            return [[cx, cy, Round(ww * 0.12), Px(cx - Round(ww * 0.03), cy)]]
        Sleep 150
    }
    return []
}

; Why the button was not found: is Dota in focus, is the point covered by
; another window, what colors are at the button corners (should be gray ~0x3b4248).
PartyDiag(wx, wy, ww, wh) {
    global DOTA_WIN, PARTY_BX, PARTY_BY
    s := Tr("Dota in focus: ") . (WinActive(DOTA_WIN) ? Tr("yes") : Tr("no"))
    s .= Tr(", under the button: ") . (Under(wx + Round(ww * PARTY_BX),
                                   wy + Round(wh * PARTY_BY)) ? Tr("Dota") : Tr("another window"))
    s .= Tr(", corners:")
    for d in [[0.385, 0.613], [0.475, 0.613], [0.385, 0.640], [0.475, 0.640]]
        s .= Format(" {:#08x}", Px(wx + Round(ww * d[1]), wy + Round(wh * d[2])))
    return s
}

; The invite arrived but the button is not visible: retry once a second until
; it is accepted (by us or by you) or 40 s have passed.
InvRetry() {
    global invPending, invUntil, invRetryAt, invDone, optInvite
    if !invPending
        return
    if invDone || !optInvite || A_TickCount > invUntil {
        invPending := false
        return
    }
    if A_TickCount < invRetryAt
        return
    invRetryAt := A_TickCount + 1000
    TryAccept(Tr("party"))
}

; what: "match" or "party". The only difference is which log line counts as the
; confirmation and which button is searched for.
TryAccept(what := Tr("match"), learnedOnly := false) {
    global CLOG_MINE, CLOG_INVOK, CLOG_WAIT, CLOG_TRIES
    global readyDone, readyTries, invDone, invTried
    global holdTill, CLOG_SILENT, CLOG_HOLD, CLOG_READY, readyAt, lastTry
    global DOTA_WIN, readyFail, invMissLogged
    if A_TickCount < holdTill
        return false            ; just accepted, no need to do it twice
    _wide := (what = Tr("match"))
    try
        WinGetPos &_wx, &_wy, &_ww, &_wh, "ahk_exe dota2.exe"
    catch
        return false
    if !_ww || !_wh
        return false
    _ok := _wide ? CLOG_MINE : CLOG_INVOK
    lastTry := A_TickCount
    cands := _wide ? FindAccept(true)
                   : PartyCands(_wx, _wy, _ww, _wh, invMissLogged ? 1 : 8)
    if learnedOnly {
        ; There is no signal from the log, the window was guessed from the screen: click only at
        ; the remembered spot of the button, not at any green band (that is how five false
        ; clicks on the post-match screen happened on 1.11).
        _only := []
        for e in cands
            if e.Length >= 5
                _only.Push(e)
        cands := _only
    }
    if !cands.Length {
        if _wide {
            Log(what . Tr(": signal received but the button was not found on screen"))
            DumpColumn(what . Tr(" no button"))
        } else if !invMissLogged {
            invMissLogged := true
            Log(Tr("party: signal received but the button was not found (") . PartyDiag(_wx, _wy,
                _ww, _wh) . Tr("); retrying for up to 40 s"))
        }
        return false
    }
    ;    ; A silent click on the right button once failed while a mouse click worked.
    ;    ; Suspicion: Dota was not in focus; note it in the log.
    _bg := WinActive(DOTA_WIN) ? "" : Tr(", Dota not in focus")
    _bg .= Tr(", mouse idle for ") . A_TimeIdlePhysical . Tr(" ms")
    for c in cands {
        if (_wide ? readyTries : invTried) >= CLOG_TRIES
            return false
        if _wide
            readyTries++
        else
            invTried++
        ;        ; Silent first, without the mouse. If not confirmed, then a real click.
        _how := Tr("no mouse")
        ;        ; The party popup appears with an animation: the button pixels are already
        ;        ; gray, but it does not take clicks yet. A mouse click ~1 s later worked,
        ;        ; a fast silent one in the first 100 ms did not. So let it settle, then
        ;        ; click silently, then a second time with a longer hover, and only then
        ;        ; with the mouse.
        if !_wide {
            Sleep 700
            ;            ; In the meantime the invite may have been accepted by hand or gone:
            ;            ; then there is a menu under the point, and it must not be clicked.
            _ch := ClogNew()
            if InStr(_ch, _ok) {
                invDone := true
                Log(Tr("party: answered by someone else while waiting — leaving it alone"))
                return true
            }
            if !PartyGate(_wx, _wy, _ww, _wh) {
                Log(Tr("party: the invite window is gone — leaving it alone"))
                return false
            }
        }
        ; The mouse is being moved right now: a silent click may not work at such a moment
        ; (1.11: twice it did not, the mouse worked; HYPOTHESIS: Panorama keeps :hover by the
        ; real cursor). We still try the silent one first, to see in the log whether it works,
        ; but give the real click earlier and skip the second silent one (with hover).
        _user := A_TimeIdlePhysical < 2000
        ClickSilent(c[1], c[2])
        t0 := A_TickCount
        _lim := CLOG_SILENT
        _hard := false
        _slow := _user                  ; second silent click, with hover
        while A_TickCount - t0 < _lim {
            Sleep 120
            _ch := ClogNew()
            if InStr(_ch, CLOG_READY)
                readyAt := A_TickCount      ; the signal is still coming: same match
            if InStr(_ch, _ok) {
                if _wide {
                    readyDone := true
                    holdTill := A_TickCount + CLOG_HOLD
                    ; We remember only a spot near the center: the confirmation could also come from
                    ; somebody else's click (you accepted yourself), and then the spot is random.
                    if Abs((c[1] - _wx) / _ww - 0.5) <= 0.2
                        LearnSave((c[1] - _wx) / _ww, (c[2] - _wy) / _wh,
                                  c[3] / _ww)
                } else
                    invDone := true
                Log(Format(Tr("ACCEPTED {5} {7}: click {1},{2} (band {3} px, ")
                           . Tr("color {6:#06x}), Dota confirmed in {4} ms"),
                           c[1], c[2], c[3], A_TickCount - t0, what,
                           c.Has(4) ? c[4] : 0, _how . _bg))
                if _wide {
                    SetTimer NtfyMatchFail, 0
                    Ntfy(readyFail ? Tr("Match accepted after all") : Tr("Match found and accepted"),
                         "high", "white_check_mark")
                }
                return true
            }
            if !_slow && A_TickCount - t0 >= 450 {
                _slow := true
                _how := Tr("no mouse (with hover)")
                ClickSilent(c[1], c[2], true)
            }
            ;            ; the silent click did not work: finish with a real click
            if !_hard && A_TickCount - t0 >= (_user ? 450 : CLOG_SILENT - 120) {
                _hard := true
                _how := _user ? Tr("with the mouse (the mouse was moving)") : Tr("mouse")
                _lim := CLOG_SILENT + CLOG_WAIT
                MouseGetPos &ox, &oy
                Click c[1] . " " . c[2]
                Sleep 60
                MouseMove ox, oy, 0
            }
        }
        Log(Format(Tr("{4}: click {1},{2} (band {3} px, color {5:#06x}) — ")
                   . Tr("no confirmation, trying the next one"), c[1], c[2],
                   c[3], what, c.Has(4) ? c[4] : 0))
    }
    return false
}

; FIRST RUN. The whole point is "download, click, and it works": on the very
; first run the script puts a shortcut into Startup itself and never mentions it
; again (a flag in the ini). To turn it off use the "Start with Windows" item in
; the tray menu.
FirstRun() {
    global DOTA_INI, DOTA_LNK
    if IniRead(DOTA_INI, "setup", "done", "") != ""
        return
    IniWrite 1, DOTA_INI, "setup", "done"
    if FileExist(DOTA_LNK)
        return
    try {
        FileCreateShortcut(A_ScriptFullPath, DOTA_LNK, A_ScriptDir)
        Log(Tr("first run: startup shortcut created"))
        Note(Tr("Match auto-accept is on and will start with Windows.")
             . Tr("`nTo turn it off use the tray icon; Ctrl+Alt+P pauses.")
             . Tr("`nThis message will not appear again."), 7000, true)
    } catch as e {
        Log(Tr("first run: could not create the shortcut — ") . e.Message)
    }
}

LoadPickTemplate()
LoadHeroMap()
NtfyInit()
KnownInit()
BuildTray()
EarlyCheck()
FirstRun()
Log(Tr("script started"))
SetTimer Tick, 100
SetTimer FixSteamAccounts, -6000
SetTimer WatchAccount, 20000
if LANG_NOTE != ""
    Log(LANG_NOTE)
if (A_Args.Length && A_Args[1] = "/settings") || IniRead(DOTA_INI, "state", "reopen", "0") = "1" {
    IniDelete DOTA_INI, "state", "reopen"
    ShowSettings()
}
