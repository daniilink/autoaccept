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
        if _hit
            _a.Push(_e)
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

UpdateIcon() {
    global dotaPause, issues
    static last := 0
    want := (dotaPause || issues.Count) ? 4 : 1
    if want = last
        return
    last := want
    try TraySetIcon(A_AhkPath, want, true)
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

; ── tray ───────────────────────────────────────────────────────────
BuildTray() {
    global M_MATCH, M_INV, M_PAUSE, M_RUN, M_LOG
    global M_NTFY, M_NTFYCOPY, M_NTFYTEST
    t := A_TrayMenu
    t.Delete()
    t.Add(M_MATCH, (*) => ToggleOpt("match"))
    t.Add(M_INV, (*) => ToggleOpt("invite"))
    t.Add(M_NTFY, (*) => ToggleOpt("ntfy"))
    t.Add(M_NTFYCOPY, (*) => NtfyCopy())
    t.Add(M_NTFYTEST, (*) => NtfyTest())
    t.Add()
    t.Add(M_PAUSE, (*) => TogglePause())
    t.Add(M_RUN, (*) => StartupToggle())
    t.Add(M_LOG, (*) => OpenLog())
    t.Add()
    t.Add("Exit", (*) => ExitApp())
    t.Default := M_LOG
    Status()
}

Status() {
    global dotaPause, dotaLive, clogOk, optMatch, optInvite, optNtfy
    global M_MATCH, M_INV, M_PAUSE, M_RUN, M_NTFY, DOTA_LNK, issues
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
                            M_NTFY, optNtfy,
                            M_PAUSE, dotaPause, M_RUN, FileExist(DOTA_LNK)) {
            if on
                t.Check(item)
            else
                t.Uncheck(item)
        }
    }
}

ToggleOpt(which) {
    global optMatch, optInvite, optNtfy, DOTA_INI
    if which = "ntfy" {
        optNtfy := !optNtfy
        IniWrite optNtfy ? 1 : 0, DOTA_INI, "options", "ntfy"
        Log("ntfy notifications: " . (optNtfy ? "on" : "off"))
    } else if which = "match" {
        optMatch := !optMatch
        IniWrite optMatch ? 1 : 0, DOTA_INI, "options", "match"
        Log("auto-accept of matches: " . (optMatch ? "on" : "off"))
    } else {
        optInvite := !optInvite
        IniWrite optInvite ? 1 : 0, DOTA_INI, "options", "invite"
        Log("auto-accept of party invites: " . (optInvite ? "on" : "off"))
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
    global issues, dotaSince, lastGrow
    static lastBeat := A_TickCount

    live := ProcessExist(DOTA_EXE) ? 1 : 0
    if live != dotaLive {
        dotaLive := live
        ;        ; Look for the log again: a new Dota session has a new one, and the
        ;        ; position must be set to its end again.
        clogOk := false, clogPos := 0
        readyDone := false, invDone := false
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
        if !readyDone && curLobby != alertedFor {
            alertedFor := curLobby
            if optMatch
                SetTimer NtfyMatchFail, -NTFY_FAIL_MS
            else {
                readyFail := true
                Ntfy("Match found, auto-accept is off — accept it yourself!",
                     "high", "rotating_light")
            }
        }
        if !readyDone && optMatch
            TryAccept()
    }
    InvRetry()
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

NtfyInit()
BuildTray()
EarlyCheck()
FirstRun()
Log("script started")
SetTimer Tick, 100
