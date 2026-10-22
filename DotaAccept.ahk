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

M_SETTINGS := "Settings…"
M_PICK := "Auto-pick hero"
M_NTFY := "Phone notifications (ntfy)"
M_NTFYCOPY := "Copy ntfy topic"
M_NTFYTEST := "Send test notification"
M_MATCH := "Auto-accept matches"
M_INV := "Auto-accept party invites"
M_PAUSE := "Pause  (Ctrl+Alt+P)"
M_RUN := "Start with Windows"
M_LOG := "Open log"

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
DumpColumn(why := "accept window seen, green button not found") {
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
    Log(why . ". grid:" . s)
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
        if _p.Length >= 3
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

; A quiet Windows notification at the bottom of the screen, at most three times
; in total, so as not to nag someone who does not intend to add the option. The
; counter is reset once the option is found.
Hint(text) {
    global DOTA_INI
    n := Integer(IniRead(DOTA_INI, "state", "hints", "0"))
    if n >= 3
        return
    IniWrite n + 1, DOTA_INI, "state", "hints"
    try TrayTip(text, "Dota auto-accept", "Iconi Mute")
}

HintReset() {
    global DOTA_INI
    if IniRead(DOTA_INI, "state", "hints", "0") != "0"
        IniWrite 0, DOTA_INI, "state", "hints"
}

HINT_TEXT := "Dota 2 was started without the -condebug launch option, so the script cannot see matches. "
           . "In Steam: Dota 2 → Properties → Launch Options: add -condebug "
           . "and restart Dota."

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
    global HINT_TEXT
    cmd := DotaCmdLine()
    if cmd = ""
        return                          ; could not read it, so do not guess
    if InStr(cmd, "-condebug") {
        DelIssue("opts")
        HintReset()
        return
    }
    AddIssue("opts", "Dota started without -condebug")
    Log("Dota was started without -condebug: the script cannot see matches")
    Hint(HINT_TEXT)
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
; say so right away rather than after the first missed match.
EarlyCheck() {
    global HINT_TEXT, DOTA_EXE
    if ProcessExist(DOTA_EXE)
        return                          ; already running: Tick checks the process
    o := SteamLaunchOptions()
    if o = -1
        return
    if InStr(o, "-condebug") {
        HintReset()
        return
    }
    Log("the Dota 2 launch options in Steam do not contain -condebug")
    Hint(HINT_TEXT)
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
    Log("ntfy: topic created (stored in dota_accept.ini, section [ntfy])")
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
        Log("ntfy: send failed — " . e.Message)
    }
}

NtfyReap() {
    global ntfyJobs
    jobs := ntfyJobs
    ntfyJobs := []
    for j in jobs {
        try {
            if !j[1].WaitForResponse(0)
                Log("ntfy: no server response for [" . j[2] . "]")
            else if j[1].Status != 200
                Log("ntfy: server answered " . j[1].Status . " for [" . j[2] . "]")
        } catch as e {
            Log("ntfy: send error for [" . j[2] . "] — " . e.Message)
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
    Log("ntfy: not accepted within " . Round(NTFY_FAIL_MS / 1000) . " s - alert")
    Ntfy("Match found, auto-accept did not work — accept it yourself!", "high",
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
        Ntfy("Match found, auto-accept is off — accept it yourself!", "high",
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
    Log("MATCH FOUND (by screen: lobby exists but no ready-up signal in the log)")
    ArmMatchAlert()
    if optMatch
        TryAccept()
}

NtfyCopy() {
    global ntfyTopic
    if ntfyTopic = ""
        return Note("No topic yet", 2000, true)
    A_Clipboard := ntfyTopic
    Note("ntfy topic copied to the clipboard.`nIn the ntfy app: tap + and paste.", 5000, true)
}

NtfyTest() {
    global optNtfy
    if !optNtfy
        return Note("Notifications are off", 2000, true)
    Ntfy("Connection check: notifications from your PC work", "high", "white_check_mark")
    Note("Test notification sent", 2000, true)
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
        Log("hero selection started; picking in " . Round(optPickDelay / 1000) . " s")
        PickShot("_0_start")
        SetTimer DoPick, -optPickDelay
        SetTimer PoolWatch, 1500
    }
    if inStage && InStr(txt, "entering state 'DOTA_GAMERULES_STATE_STRATEGY_TIME'") {
        inStage := false
        SetTimer DoPick, 0
        SetTimer PoolWatch, 0
        Log("hero selection stage ended" . (picked ? "" : " (no pick was made)"))
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
    sgOrder := ResolveHeroes()
    sgKeys := []
    sgBuilding := false
    sg := Gui("-MaximizeBox", "Dota auto-accept — settings")
    sg.MarginX := 14, sg.MarginY := 12
    sg.OnEvent("Close", (*) => CloseSettings())
    tab := sg.Add("Tab3", "w650 h560", ["General", "Auto-pick"])
    tab.UseTab(1)
    sg.Add("GroupBox", "x28 y48 w620 h130", "Auto-accept")
    c := sg.Add("Checkbox", "x48 y76 w580", "Auto-accept matches (the match found window)")
    c.Value := optMatch
    c.OnEvent("Click", (ctl, *) => SetOpt("match", ctl.Value))
    c := sg.Add("Checkbox", "x48 y106 w580", "Auto-accept party invites")
    c.Value := optInvite
    c.OnEvent("Click", (ctl, *) => SetOpt("invite", ctl.Value))
    c := sg.Add("Checkbox", "x48 y136 w580", "Start with Windows")
    c.Value := FileExist(DOTA_LNK) ? 1 : 0
    c.OnEvent("Click", (*) => StartupToggle())
    sg.Add("GroupBox", "x28 y190 w620 h150", "Phone notifications (ntfy)")
    c := sg.Add("Checkbox", "x48 y218 w580", "Send: match found and accepted / auto-accept did not work")
    c.Value := optNtfy
    c.OnEvent("Click", (ctl, *) => SetOpt("ntfy", ctl.Value))
    b := sg.Add("Button", "x48 y258 w210 h30", "Copy ntfy topic")
    b.OnEvent("Click", (*) => NtfyCopy())
    b := sg.Add("Button", "x268 y258 w210 h30", "Send test notification")
    b.OnEvent("Click", (*) => NtfyTest())
    sg.Add("Text", "x48 y300 w580 c808080", "The topic works like the channel password: it is stored in dota_accept.ini and never logged.")
    b := sg.Add("Button", "x28 y360 w160 h30", "Open log")
    b.OnEvent("Click", (*) => OpenLog())
    tab.UseTab(2)
    c := sg.Add("Checkbox", "x28 y48 w300", "Enable hero auto-pick")
    c.Value := optPick
    c.OnEvent("Click", (ctl, *) => SetOpt("pick", ctl.Value))
    sg.Add("Text", "x340 y50 w134", "Pick after (sec):")
    ed := sg.Add("Edit", "x478 y46 w56 Number", Round(optPickDelay / 1000))
    ed.OnEvent("Change", (ctl, *) => SetPickDelay(ctl.Value))
    sg.Add("Text", "x28 y82 w610 h34", "Attributes grid: tick the heroes; the order in the right-hand list is the priority (the first available one is taken). MY HEROES strip (Custom Layout): no list needed.")
    sg.Add("Text", "x28 y124 w60", "Search:")
    sgFilter := sg.Add("Edit", "x88 y120 w270")
    sgFilter.OnEvent("Change", (*) => FillHeroLV())
    sgLV := sg.Add("ListView", "x28 y154 w330 h340 Checked -Multi NoSortHdr", ["Hero", "Attribute"])
    sgLV.OnEvent("ItemCheck", OnHeroCheck)
    sg.Add("Text", "x376 y124 w200", "Pick order:")
    sgLB := sg.Add("ListBox", "x376 y154 w210 h340")
    b := sg.Add("Button", "x594 y154 w44 h34", "▲")
    b.OnEvent("Click", (*) => MoveHero(-1))
    b := sg.Add("Button", "x594 y194 w44 h34", "▼")
    b.OnEvent("Click", (*) => MoveHero(1))
    b := sg.Add("Button", "x594 y234 w44 h34", "✕")
    b.OnEvent("Click", (*) => RemoveHero())
    b := sg.Add("Button", "x376 y504 w262 h30", "Save hero list")
    b.OnEvent("Click", (*) => SaveHeroes())
    sgInfo := sg.Add("Text", "x28 y510 w330 c808080", "")
    tab.UseTab()
    FillHeroLV()
    RefreshOrder()
    sg.Show("w680 h600")
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
    attrName := Map("S", "Strength", "A", "Agility", "I", "Intelligence", "U", "Universal")
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
    sgInfo.Value := "Saved: " . sgOrder.Length . " heroes"
    Log("auto-pick hero list: " . (names = "" ? "(empty)" : names))
}

Norm(t) {
    t := StrLower(RegExReplace(t, "[^\p{L}\p{N}]"))
    return StrReplace(t, Chr(0x451), Chr(0x435))
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
                Log("in the heroes list [" . Trim(nm) . "] was read as [" . HERO_NAME[best] . "] (typo)")
            } else
                Log("unknown name in the heroes list: [" . Trim(nm) . "] (use the English name as in the game)")
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
    Log("clicking " . name . " at " . cc[1] . "," . cc[2])
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
        Log("selection did not register: hero panel " . p0 . " -> " . p . ", button " . b1
            . " (" . name . " unavailable?) - taking the next one")
        return 0
    }
    Log(name . " selected (panel " . p . "), LOCK IN button: " . b1)
    t0 := A_TickCount, shotAt := A_TickCount
    chkAt := 0, lostN := 0, reclickAt := 0, lastCs := ""
    while b1 < 70 {
        if !inStage || A_TickCount - t0 > 90000 {
            Log("LOCK IN button never lit up before the stage ended (" . b1 . ")")
            PickShot("_nolock")
            return 3
        }
        if A_TickCount - t0 > 1500 && A_TickCount - shotAt > 6000 {
            shotAt := A_TickCount
            Log("waiting for LOCK IN to light up (brightness " . b1 . ")")
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
                Log("card " . name . " while waiting: " . (cs = 1 ? "banned" : cs = 2 ? "gray" : cs = "" ? "not read" : "free")
                    . ", button " . b1)
            }
            if cs = 1 || cs = 2 {
                if ++lostN >= 2 {
                    Log(name . ": " . (cs = 1 ? "banned" : "taken by the other team (card is gray)") . " - taking the next one")
                    PickShot("_lost")
                    return 0
                }
            } else {
                lostN := 0
                if cs = 0 && HeroPanel() < 15 && A_TickCount - reclickAt > 3000 {
                    reclickAt := A_TickCount
                    Log("hero panel disappeared, card " . name . " is free - selecting again")
                    PickClick(cc[1], cc[2])
                    Sleep 500
                }
            }
        }
    }
    Loop 3 {
        Log("LOCK IN button is lit (" . b1 . "); pressing LOCK IN at " . lk[1] . "," . lk[2])
        PickClick(lk[1], lk[2])
        Sleep 1200
        b2 := LockBtn()
        Log("button brightness after LOCK IN: " . b2)
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
        Log("auto-pick is off - not touching anything")
        return
    }
    if PICK_DEADLINE_MS - (A_TickCount - stageAt) < 3000 {
        picked := true
        Log("the first round is over (gold penalty next) - too late")
        return
    }
    ;    ; Someone is at the PC: wait, maybe they will pick themselves; but the penalty will not wait.
    if A_TimeIdlePhysical < 6000 {
        if pickNote != "idle" {
            pickNote := "idle"
            Log("someone is at the PC (mouse/keyboard " . A_TimeIdlePhysical
                . " ms ago) - waiting, maybe you will pick yourself")
        }
        SetTimer DoPick, -3000
        return
    }
    try WinGetPos &wx, &wy, &ww, &wh, "ahk_exe dota2.exe"
    catch {
        Log("Dota window not found")
        picked := true
        return
    }
    if Abs(ww / wh - 16 / 9) > 0.05 {
        picked := true
        Log("window is not 16:9 (" . ww . "x" . wh . ") - layout not measured, not touching anything")
        return
    }
    c1 := CardCenter(1)
    if !Under(c1[1], c1[2]) {
        if pickNote != "covered" {
            pickNote := "covered"
            Log("Dota is covered by another window - nothing to read, waiting")
        }
        SetTimer DoPick, -3000
        return
    }
    lay := DetectLayout()
    if lay = "" {
        if pickNote != "nolayout" {
            pickNote := "nolayout"
            Log("pick screen not recognised yet - waiting (needs the Attributes or Custom Layout sort)")
            PickShot("_unknown")
        }
        SetTimer DoPick, -3000
        return
    }
    Log("pick screen: " . lay)
    ;    ; Candidates in priority order: [name, card center]. Unavailable ones by color
    ;    ; (banned/gray) are skipped; if the color is wrong, the LOCK IN check in PickTry
    ;    ; will catch it and we go to the next one.
    cands := []
    if lay = "standard" {
        want := ResolveHeroes()
        if !want.Length {
            picked := true
            Log("standard grid, but the hero list is empty - not touching anything")
            return
        }
        s := wh / 1440
        for key in want {
            st := CellState(key)
            if st = "" {
                Log(HERO_NAME[key] . ": card not read")
                continue
            }
            Log(HERO_NAME[key] . ": " . (st[1] = 1 ? "CROSSED OUT (banned)" : st[1] = 2 ? "GRAY (taken)" : "available")
                . " (saturation " . st[2] . "%, brightness " . st[3] . ")")
            if st[1] = 0 {
                o := CellOrigin(key)
                cands.Push([HERO_NAME[key], [wx + Round((o[1] + 27) * s), wy + Round((o[2] + 49) * s)], ["std", key]])
            }
        }
    } else {
        st := PoolStatus()
        if st = "" {
            Log("pool not read")
            SetTimer DoPick, -3000
            return
        }
        txt := ""
        for i, c in st {
            txt .= " [" . i . (c[1] = 1 ? " CROSSED OUT" : c[1] = 2 ? " GRAY" : " ok")
                . " v" . c[2] . " s" . c[3] . "]"
            if c[1] = 0
                cands.Push(["#" . i . " of the pool", CardCenter(i), ["strip", i]])
        }
        Log("pool:" . txt)
    }
    if !cands.Length {
        picked := true
        Log("none of the heroes in the list is available - not picking")
        return
    }
    unsure := ""
    for c in cands {
        if !inStage || PICK_DEADLINE_MS - (A_TickCount - stageAt) < 1500
            break
        r := PickTry(c[1], c[2], c[3])
        if r = 1 {
            picked := true
            Log("hero picked: " . c[1])
            return
        }
        if r = 3 {
            picked := true
            Log("picked " . c[1] . " but could not lock it in (the button never lit up)")
            return
        }
        if r = 2 {
            unsure := c[1]
            break
        }
    }
    if unsure != "" {
        picked := true
        Log("picked " . unsure . " but LOCK IN was not confirmed - check by hand")
        return
    }
    Log("no attempt worked - retrying in 4 s if there is time before the round ends")
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
            txt .= " [" . HERO_NAME[key] . (st[1] = 1 ? " CROSSED OUT" : st[1] = 2 ? " GRAY" : " ok")
                . " s" . st[2] . "]"
        }
        if key2 != lastPool {
            lastPool := key2
            Log("heroes from the list:" . txt)
        }
        return
    }
    st := PoolStatus()
    if st = ""
        return
    key := "", txt := ""
    for i, c in st {
        key .= c[1]
        txt .= " [" . i . (c[1] = 1 ? " CROSSED OUT" : c[1] = 2 ? " GRAY" : " ok")
            . " v" . c[2] . " s" . c[3] . "]"
    }
    if key != lastPool {
        lastPool := key
        Log("pool changed:" . txt)
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
    t.Add("Exit", (*) => ExitApp())
    t.Default := M_SETTINGS
    Status()
}

Status() {
    global dotaPause, dotaLive, clogOk, optMatch, optInvite, optNtfy, optPick
    global M_MATCH, M_INV, M_PAUSE, M_RUN, M_NTFY, M_PICK, DOTA_LNK, issues
    s := dotaPause ? "paused"
       : issues.Count ? "PROBLEM: " . IssueText()
       : dotaLive != 1 ? "Dota is not running, waiting"
       : clogOk ? "armed (reading the Dota log)"
       : "looking for the Dota log"
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
    global optMatch, optInvite, optNtfy, optPick, DOTA_INI
    v := val ? 1 : 0
    if which = "ntfy" {
        optNtfy := v
        IniWrite v, DOTA_INI, "options", "ntfy"
        Log("ntfy notifications: " . (v ? "on" : "off"))
    } else if which = "match" {
        optMatch := v
        IniWrite v, DOTA_INI, "options", "match"
        Log("auto-accept of matches: " . (v ? "on" : "off"))
    } else if which = "invite" {
        optInvite := v
        IniWrite v, DOTA_INI, "options", "invite"
        Log("auto-accept of party invites: " . (v ? "on" : "off"))
    } else if which = "pick" {
        optPick := v
        IniWrite v, DOTA_INI, "pick", "enabled"
        Log("hero auto-pick: " . (v ? "on" : "off"))
    }
    Status()
}

TogglePause(*) {
    global dotaPause
    dotaPause := !dotaPause
    Log(dotaPause ? "PAUSED manually" : "auto again")
    Status()
    Note(dotaPause ? "Dota auto-accept: PAUSED`n(Ctrl+Alt+P to resume)"
                   : "Dota auto-accept: active")
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
        Log(live ? "Dota started — armed" : "Dota closed — sleeping")
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
        Log("alive")
    }

    if !clogOk {
        clogPath := ClogFind()
        if clogPath != "" {
            try clogPos := FileGetSize(clogPath)
            clogOk := true
            lastGrow := A_TickCount
            DelIssue("nolog")
            Log("Dota log found, working from it: " . clogPath)
            Status()
        } else {
            ;            ; The log does not appear right after launch: give Dota 90 seconds.
            if !clogSaid && A_TickCount - dotaSince > 90000 {
                clogSaid := true
                Log("Dota's console.log was not found 90 s after launch. "
                    . "Check -condebug in the launch options (Steam → Dota 2 "
                    . "→ Properties) and restart it")
                if !issues.Has("opts") {
                    AddIssue("nolog", "Dota's console.log not found")
                    Hint("The script cannot see Dota 2's log. Make sure the launch options "
                         . "contain -condebug, then restart Dota.")
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
            Log("Dota log is flowing again")
        }
    } else if A_TickCount - lastGrow > 300000 && !issues.Has("silent") {
        AddIssue("silent", "Dota log silent for 5+ minutes")
        Log("Dota log silent for 5+ minutes — the script may be blind")
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
        Log("server assigned — match is starting")
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
            Log(optInvite ? "PARTY INVITE (log)"
                : "PARTY INVITE — auto-accept is off, leaving it alone")
        }
        invAt := A_TickCount
        if !invDone && optInvite
            TryAccept("party")
    }
    ;    ; A new lobby is a different match, and the only reliable sign of it.
    _lob := LobbyId(_new)
    if _lob != "" && _lob != curLobby {
        curLobby := _lob
        readyDone := false, readyTries := 0, lastTry := 0
        readyFail := false
        lobbyAt := A_TickCount, lobbyWatch := true, lobbyNext := 0
        Log("new lobby " . _lob)
    }
    if InStr(_new, CLOG_READY) {
        ;        ; All candidates missed: try again after RETRY_MS: the window stays up
        ;        ; for ~25 seconds, and we keep clicking until the game registers it.
        if optMatch && !readyDone && readyTries >= CLOG_TRIES
           && A_TickCount - lastTry > RETRY_MS {
            readyTries := 0
            Log("window is still up — trying candidates again")
        }
        if A_TickCount - readyAt > READY_GAP {
            ;            ; A new ready-check only if there was no signal for a long time:
            ;            ; while candidates were being tried, the same match could look new,
            ;            ; and the cursor jumped five more times after the accept.
            readyDone := false, readyTries := 0, readyFail := false
            Log(optMatch ? "MATCH FOUND (log: ready-check)"
                : "MATCH FOUND — auto-accept is off, leaving it alone")
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
        Log("removed from startup")
        Note("No longer starts with Windows", 2500, true)
    } else {
        try {
            FileCreateShortcut(A_ScriptFullPath, DOTA_LNK, A_ScriptDir)
            Log("added to startup")
            Note("Now starts with Windows", 2500, true)
        } catch as e {
            Note("could not create the shortcut:`n" . e.Message, 4000, true)
        }
    }
    Status()
}

OpenLog(*) {
    global DOTA_LOGF
    if !FileExist(DOTA_LOGF)
        return Note("the log is empty so far", 2000, true)
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
    s := "Dota in focus: " . (WinActive(DOTA_WIN) ? "yes" : "no")
    s .= ", under the button: " . (Under(wx + Round(ww * PARTY_BX),
                                   wy + Round(wh * PARTY_BY)) ? "Dota" : "another window")
    s .= ", corners:"
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
    TryAccept("party")
}

; what: "match" or "party". The only difference is which log line counts as the
; confirmation and which button is searched for.
TryAccept(what := "match") {
    global CLOG_MINE, CLOG_INVOK, CLOG_WAIT, CLOG_TRIES
    global readyDone, readyTries, invDone, invTried
    global holdTill, CLOG_SILENT, CLOG_HOLD, CLOG_READY, readyAt, lastTry
    global DOTA_WIN, readyFail, invMissLogged
    if A_TickCount < holdTill
        return false            ; just accepted, no need to do it twice
    _wide := (what = "match")
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
    if !cands.Length {
        if _wide {
            Log(what . ": signal received but the button was not found on screen")
            DumpColumn(what . " no button")
        } else if !invMissLogged {
            invMissLogged := true
            Log("party: signal received but the button was not found (" . PartyDiag(_wx, _wy,
                _ww, _wh) . "); retrying for up to 40 s")
        }
        return false
    }
    ;    ; A silent click on the right button once failed while a mouse click worked.
    ;    ; Suspicion: Dota was not in focus; note it in the log.
    _bg := WinActive(DOTA_WIN) ? "" : ", Dota not in focus"
    for c in cands {
        if (_wide ? readyTries : invTried) >= CLOG_TRIES
            return false
        if _wide
            readyTries++
        else
            invTried++
        ;        ; Silent first, without the mouse. If not confirmed, then a real click.
        _how := "no mouse"
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
                Log("party: answered by someone else while waiting — leaving it alone")
                return true
            }
            if !PartyGate(_wx, _wy, _ww, _wh) {
                Log("party: the invite window is gone — leaving it alone")
                return false
            }
        }
        ClickSilent(c[1], c[2])
        t0 := A_TickCount
        _lim := CLOG_SILENT
        _hard := false
        _slow := false                  ; second silent click, with hover
        while A_TickCount - t0 < _lim {
            Sleep 120
            _ch := ClogNew()
            if InStr(_ch, CLOG_READY)
                readyAt := A_TickCount      ; the signal is still coming: same match
            if InStr(_ch, _ok) {
                if _wide {
                    readyDone := true
                    holdTill := A_TickCount + CLOG_HOLD
                    LearnSave((c[1] - _wx) / _ww, (c[2] - _wy) / _wh,
                              c[3] / _ww)
                } else
                    invDone := true
                Log(Format("ACCEPTED {5} {7}: click {1},{2} (band {3} px, "
                           . "color {6:#06x}), Dota confirmed in {4} ms",
                           c[1], c[2], c[3], A_TickCount - t0, what,
                           c.Has(4) ? c[4] : 0, _how . _bg))
                if _wide {
                    SetTimer NtfyMatchFail, 0
                    Ntfy(readyFail ? "Match accepted after all" : "Match found and accepted",
                         "high", "white_check_mark")
                }
                return true
            }
            if !_slow && A_TickCount - t0 >= 450 {
                _slow := true
                _how := "no mouse (with hover)"
                ClickSilent(c[1], c[2], true)
            }
            ;            ; the silent click did not work: finish with a real click
            if !_hard && A_TickCount - t0 >= CLOG_SILENT - 120 {
                _hard := true
                _how := "mouse"
                _lim := CLOG_SILENT + CLOG_WAIT
                MouseGetPos &ox, &oy
                Click c[1] . " " . c[2]
                Sleep 60
                MouseMove ox, oy, 0
            }
        }
        Log(Format("{4}: click {1},{2} (band {3} px, color {5:#06x}) — "
                   . "no confirmation, trying the next one", c[1], c[2],
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
        Log("first run: startup shortcut created")
        Note("Match auto-accept is on and will start with Windows."
             . "`nTo turn it off use the tray icon; Ctrl+Alt+P pauses."
             . "`nThis message will not appear again.", 7000, true)
    } catch as e {
        Log("first run: could not create the shortcut — " . e.Message)
    }
}

LoadPickTemplate()
LoadHeroMap()
NtfyInit()
BuildTray()
EarlyCheck()
FirstRun()
Log("script started")
SetTimer Tick, 100
if A_Args.Length && A_Args[1] = "/settings"
    ShowSettings()
