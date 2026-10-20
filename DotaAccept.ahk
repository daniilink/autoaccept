#Requires AutoHotkey v2.0
#SingleInstance Force
; ──────────────────────────────────────────────────────────────────────
;  АВТОПРИНЯТИЕ МАТЧА В DOTA 2.  Самостоятельный скрипт, больше ничего не
;  делает: ни автозамен, ни других горячих клавиш.
;
;  Включать руками не надо: пока запущена дота, он на взводе, дота закрыта
;  — спит. Сам по времени не отключается.
;
;  КАК ОНО РАБОТАЕТ ТЕПЕРЬ (главный путь — лог доты):
;    Дота с параметром запуска -condebug пишет console.log, и в нём
;    открытым текстом видно всё нужное. Замерено 19.10.2026:
;      Recv 7170 (k_EMsgGCReadyUpStatus)   матч найден, окно висит
;      Send 7070 (k_EMsgGCReadyUp)         принято, наш клик дошёл
;      owner=<Invite:                      пришло приглашение в пати
;      k_EMsgGCPartyInviteResponse         ответ на приглашение дошёл
;      ...SteamDatagramTicket              сервер выдан, матч стартует
;    Задержка записи на диск: медиана 0.22 с, максимум 0.59 — при окне
;    принятия в 25 секунд запас стократный.
;
;    Поэтому СОБЫТИЕ мы знаем точно, а экран нужен ровно для одного:
;    найти, КУДА нажать. Ищем не картинку кнопки и не один пиксель, а
;    ШИРОКУЮ РОВНУЮ ПОЛОСУ зелёной заливки — ей безразличны язык
;    (текст мы не читаем), разрешение (ширина считается от окна) и
;    Dota Plus, из-за которого окно принятия шире и стоит иначе.
;    Промах не страшен: нажатие подтверждается строкой из лога, и если
;    подтверждения нет за 1.4 с, пробуется следующий кандидат.
;
;  ЗАПАСНОЙ ПУТЬ — если -condebug не добавлен и лога нет. Тогда правило
;  на два пикселя, как было:
;      кнопка ЗАКРЫТИЯ доты (справа вверху) своего обычного цвета
;      И  в середине экрана появилась серая панель окна принятия
;          → нажать зелёную кнопку
;
;  Почему именно так, замерено 19.10.2026 на живом экране, четыре принятия
;  подряд. Каждое выглядит в две фазы:
;      фаза 1, 1-4 с: панель окна принятия 0x3D4341, кнопка закрытия
;                     обычная красная 0x480D0D  ← ЖМЁМ ЗДЕСЬ
;      фаза 2, ~4 с:  панель 0x1F2424, кнопка закрытия затемнена 0x0B0606
;  Фаза 2 — это уже ПОСЛЕ принятия, поэтому ловить затемнение кнопки нельзя,
;  опоздаем на шаг. Зато кнопка закрытия в фазе 1 ровно обычная, а в бою её
;  на экране нет вообще — значит она же и отвечает на вопрос «я в меню или в
;  матче». Поэтому никакой приметы боя и никакой машины состояний больше
;  нет: в бою первое условие ложно всегда.
;
;  До этого правила скрипт искал зелёную заливку кнопки — и 19.10 пять раз
;  щёлкнул посреди боя, потому что тёмно-зелёный 0x3C6250 это ещё и трава, и
;  верхняя панель, и фон меню. Зелёный остался только как способ НАЙТИ, куда
;  именно нажать, когда окно принятия уже опознано по панели.
;
;  КАК ПОСТАВИТЬ ДРУГУ
;    1. Поставить AutoHotkey v2 — autohotkey.com (бесплатно).
;    2. Положить файл куда угодно, запустить двойным кликом. В трее появится
;       значок: там состояние и все кнопки. Рядом с файлом он сделает
;       dota_accept.ini (точки) и dota_log.txt (что когда нажал).
;    3. Трей → «Запускать вместе с Windows».
;    4. Точки прошиты мои, под 2560x1440. При другом разрешении снять свои,
;       это полминуты — трей или горячие клавиши:
;         Ctrl+Alt+C — навести мышь на кнопку ЗАКРЫТИЯ доты (крестик справа
;                      вверху) в главном меню и нажать;
;         Ctrl+Alt+W — когда висит окно принятия, навести на его СЕРУЮ
;                      ПАНЕЛЬ (не на кнопку, не на буквы) и нажать;
;         Ctrl+Alt+F — тогда же навести на зелёную заливку кнопки ACCEPT.
;       Ctrl+Alt+T в любой момент показывает, что он видит сейчас.
;
;  ГОРЯЧИЕ КЛАВИШИ
;    Ctrl+Alt+P   пауза / снова авто      Ctrl+Alt+T   что видно сейчас
;    Ctrl+Alt+C   точка кнопки закрытия   Ctrl+Alt+W   точка панели окна
;    Ctrl+Alt+F   точка зелёной кнопки
;    Ctrl+Alt+K   пати: точка ПАНЕЛИ приглашения
;    Ctrl+Alt+J   пати: точка его КНОПКИ принять. Снять обе, пока
;                 приглашение висит на экране, — и пати тоже начнёт
;                 приниматься само. Пока не сняты, эта часть молчит.
;    Ctrl+Alt+D   снимок, когда окно принятия висит: что в этот момент на
;                 обеих точках и где в столбце зелёное. Прицеливаться не
;                 надо, точки он читает сам.
;
;  ЧТО ЕЩЁ ВАЖНО, чтобы не переделывать по второму кругу:
;  · Нажимается КЛИКОМ, а не Enter: в Dota 2 Enter открывает чат. Проверено
;    по логу — шесть Enter подряд не убрали кнопку. Клик заодно не требует
;    фокуса, он уходит в окно под курсором; мышь сразу возвращается.
;  · Перед каждым чтением пикселя проверяется, что под точкой ДЕЙСТВИТЕЛЬНО
;    окно доты. WinExist() про это не говорит: дота бывает жива и полностью
;    закрыта другим окном. 19.10 замер поймал это прямо — на точке был белый
;    пиксель чужого окна, а скрипт читал его как меню и щёлкал по чужому
;    приложению.
;  · После нажатия слежка продолжается: любой в лобби может отказаться,
;    поиск пойдёт заново и окно всплывёт ещё раз. В замере таких кругов
;    было четыре подряд.
; ──────────────────────────────────────────────────────────────────────

DOTA_EXE := "dota2.exe"
DOTA_WIN := "ahk_exe dota2.exe"
DOTA_POLL := 200         ; как часто смотреть, когда дота запущена, мс
DOTA_IDLE := 2000        ; как часто проверять, не запустилась ли дота
DOTA_TOL := 14           ; допуск по каждому каналу цвета
DOTA_NEED := 3           ; панель надо увидеть столько опросов подряд
DOTA_SPAN := 20          ; полоса поиска зелёной кнопки по горизонтали
DOTA_VSPAN := 260        ; и по вертикали от точки: кнопку сдвигает панель
                         ; Dota Plus с оценкой матча, по логу на ±240
DOTA_SCAN_MAX := 14      ; не больше столько кандидатов за опрос
DOTA_SCAN_MS := 150      ; и не дольше столька мс
DOTA_STUCK := 6          ; окно не исчезает после столька кликов → пауза
DOTA_SAMPLE_WAIT := 2000 ; сколько ждать, пока уберёшь мышь с точки
; ТИХО: про свою обычную работу он не говорит ничего — ни про принятый матч,
; ни про взвод. Тултипсы остаются только там, где ты сам нажал кнопку, и на
; двух редких случаях, когда молчать нельзя: он встал на паузу или не нашёл
; зелёную кнопку. Всё остальное пишется в лог.
QUIET := true
; Строки в console.log доты, по которым всё и работает. Сравниваем с
; закрывающей скобкой: "k_EMsgGCReadyUpStatus" содержит в себе
; "k_EMsgGCReadyUp", и без скобки одно ловилось бы другим.
CLOG_READY := "(k_EMsgGCReadyUpStatus)"   ; GC: идёт ready-check
CLOG_MINE := "(k_EMsgGCReadyUp)"          ; клиент: приняли (мы или он)
CLOG_START := "(k_EMsgGCToClientSteamDatagramTicket)"  ; сервер выдан
; Приглашение в пати. Замерено: оно приходит как подписка на объект
; Invite, в строке видно и SteamID пригласившего — при желании потом
; можно принимать только от своих. Ответ клиента (наш клик) дота пишет
; отдельным сообщением, по нему и проверяем, что попали.
; Токен берём ТОЧНЫЙ: строка закрытия приглашения — CacheUnsubscribedJob —
; тоже содержит "owner=<Invite:", и по ней скрипт щёлкал бы в пустоту уже
; после отказа или истечения приглашения.
CLOG_INV := "CacheSubscribedJob(owner=<Invite:"   ; пришло приглашение
CLOG_INVOK := "(k_EMsgGCPartyInviteResponse)"   ; ответ отправлен
CLOG_PARTY := "owner=<Party:"             ; мы в пати, итог
; У каждого ready-check своё лобби со своим ID. Это и есть точный ответ
; на вопрос «тот же матч или уже другой», вместо гадания по времени.
CLOG_LOBBY := "owner=<Lobby:"
CLOG_WAIT := 1400       ; сколько ждать подтверждения нажатия, мс
CLOG_TRIES := 5         ; столько кандидатов пробуем за один ready-check
BTN_MINW := 60          ; кнопка не уже столька пикселей (на 1440p)
; Размер снимка. 256x144 при окне 2560x1440 — это ровно 1:10: кнопка в
; 300 px становится полосой в 30 клеток, мимо такой не промахнёшься, а
; просмотр 37 тысяч точек стоит ~150 мс.
SHOT_W := 256
SHOT_H := 144
; Полоса шире этой доли окна — это не кнопка, а панель во всю ширину.
; По логу: кнопка 230 px при окне 2560 (0.09), промахи 850 и 1040 px.
BTN_MAXFRAC := 0.25
; 1.1 с, а не 600 мс: подтверждение само доезжает до диска за 0.1-0.6 с
; (замерено), и при коротком окне УДАЧНОЕ тихое нажатие не успевало бы
; подтвердиться, и мышь дёрнулась бы впустую — ровно чего он не хочет.
CLOG_SILENT := 1100      ; сколько ждать подтверждения тихого нажатия
; Глухой паузы после принятия больше нет: замолкаем по факту
; подтверждения, а просыпаемся по новому лобби.
CLOG_HOLD := 0
; Аварийный таймаут на случай режима, где строки лобби не будет вовсе.
READY_GAP := 120000
RETRY_MS := 4000         ; все кандидаты промазали — через столько снова
DOTA_LOGF := A_ScriptDir . "\dota_log.txt"
DOTA_INI := A_ScriptDir . "\dota_accept.ini"
DOTA_LNK := A_AppData . "\Microsoft\Windows\Start Menu\Programs\Startup"
           . "\DotaAccept.lnk"

; Точки по умолчанию — замеренные, под 2560x1440 на весь экран.
DEF := Map("close_x", 2500, "close_y", 58, "close_c", 0x480D0D,
           "panel_x", 1199, "panel_y", 684, "panel_c", 0x3D4341,
           "btn_x", 1199, "btn_y", 684, "btn_c", 0x3C6250,
           "btn_h", 0x9DE38E)

; Координаты и цвета — ЭКРАННЫЕ. По умолчанию AHK считает их от активного
; окна, и точка, снятая в одном окне, в другом уже не та.
CoordMode "Mouse", "Screen"
CoordMode "Pixel", "Screen"

closeX := 0, closeY := 0, closeC := 0      ; кнопка закрытия доты
panelX := 0, panelY := 0, panelC := 0      ; серая панель окна принятия
btnX := 0, btnY := 0, btnC := 0, btnH := 0 ; зелёная кнопка и её подсветка
dotaPause := false       ; Ctrl+Alt+P
dotaLive := -1           ; 1 дота есть, 0 нет, -1 ещё не смотрели
hits := 0                ; сколько опросов подряд видим панель
nextAt := 0              ; раньше этого момента не жмём
seenAt := 0              ; когда панель увидели впервые — для замера
clicks := 0              ; кликов подряд, после которых окно не исчезло
dumped := false          ; дамп столбца на это окно уже написан
autoClose := true        ; точку не снимали руками — считаем от окна
autoPanel := true
autoBtn := true
lastW := 0, lastH := 0   ; при каком размере окна считали в прошлый раз
; ПРИГЛАШЕНИЕ В ПАТИ. Своё правило и свои точки: всплывашка приходит и в
; меню, и посреди матча, фон за собой не затемняет и кнопку закрытия не
; трогает. Пока точки не сняты (для них нужно живое приглашение), всё
; это выключено: ноль в invPX значит «не умею, ничего не делаю».
invPX := 0, invPY := 0, invPC := 0     ; панель всплывашки
invBX := 0, invBY := 0, invBC := 0     ; её кнопка «принять»
invBH := 0                             ; и подсвеченный цвет кнопки
invHits := 0, invNext := 0, invClicks := 0
clogPath := ""          ; путь к console.log доты
clogPos := 0             ; сколько байт уже прочли
clogOk := false          ; лог найден и читается
clogSaid := false        ; про отсутствие лога сказали один раз
readyAt := 0             ; когда последний раз видели ready-check
readyDone := false       ; в этом ready-check уже приняли
readyTries := 0          ; сколько кандидатов попробовали
invAt := 0               ; когда видели приглашение в пати
invDone := false         ; на это приглашение уже ответили
invTried := 0            ; сколько кандидатов попробовали
holdTill := 0            ; (не используется: паузы после принятия нет)
curLobby := ""           ; ID лобби текущего ready-check
lastTry := 0             ; когда последний раз перебирали кандидатов
learned := []            ; запомненные удачные места, в долях окна
pend := 0                ; подсвеченный цвет, снятый в момент Ctrl+Alt+F

M_PAUSE := "Пауза  (Ctrl+Alt+P)"
M_PROBE := "Что видно сейчас  (Ctrl+Alt+T)"
M_CLOSE := "Точка кнопки закрытия  (Ctrl+Alt+C)"
M_PANEL := "Точка панели окна принятия  (Ctrl+Alt+W)"
M_BTN := "Точка зелёной кнопки  (Ctrl+Alt+F)"
M_RUN := "Запускать вместе с Windows"
M_LOG := "Открыть лог"

; ЦВЕТА от разрешения не зависят — интерфейс доты красят одинаково, их и
; берём готовыми. А КООРДИНАТЫ зависят, поэтому если точку не снимали
; руками, считаем её от размеров окна доты (AutoPoints). Так у друга с
; другим монитором всё работает сразу, без настройки.
Load() {
    global closeX, closeY, closeC, panelX, panelY, panelC
    global btnX, btnY, btnC, btnH, DOTA_INI, DEF
    global autoClose, autoPanel, autoBtn
    closeC := Integer(IniRead(DOTA_INI, "close", "color", DEF["close_c"]))
    panelC := Integer(IniRead(DOTA_INI, "panel", "color", DEF["panel_c"]))
    btnC := Integer(IniRead(DOTA_INI, "accept", "color", DEF["btn_c"]))
    btnH := Integer(IniRead(DOTA_INI, "accept", "hover", DEF["btn_h"]))
    global invPX, invPY, invPC, invBX, invBY, invBC, invBH
    invPX := Integer(IniRead(DOTA_INI, "invite", "px", 0))
    invPY := Integer(IniRead(DOTA_INI, "invite", "py", 0))
    invPC := Integer(IniRead(DOTA_INI, "invite", "pcolor", 0))
    invBX := Integer(IniRead(DOTA_INI, "invite", "bx", 0))
    invBY := Integer(IniRead(DOTA_INI, "invite", "by", 0))
    invBC := Integer(IniRead(DOTA_INI, "invite", "bcolor", 0))
    invBH := Integer(IniRead(DOTA_INI, "invite", "bhover", 0))
    autoClose := (IniRead(DOTA_INI, "close", "x", "") = "")
    autoPanel := (IniRead(DOTA_INI, "panel", "x", "") = "")
    autoBtn := (IniRead(DOTA_INI, "accept", "x", "") = "")
    if !autoClose {
        closeX := Integer(IniRead(DOTA_INI, "close", "x", 0))
        closeY := Integer(IniRead(DOTA_INI, "close", "y", 0))
    }
    if !autoPanel {
        panelX := Integer(IniRead(DOTA_INI, "panel", "x", 0))
        panelY := Integer(IniRead(DOTA_INI, "panel", "y", 0))
    }
    if !autoBtn {
        btnX := Integer(IniRead(DOTA_INI, "accept", "x", 0))
        btnY := Integer(IniRead(DOTA_INI, "accept", "y", 0))
    }
}

; Пересчёт точек под текущее окно доты. Опорные числа — замеренные на
; 2560x1440 во весь экран: кнопка закрытия в 60 пикселях от правого края и
; 58 от верхнего; панель окна принятия в 81 левее и 36 выше центра экрана.
; Интерфейс доты масштабируется по высоте, поэтому множитель — высота/1440.
AutoPoints() {
    global closeX, closeY, panelX, panelY, btnX, btnY, DOTA_WIN
    global autoClose, autoPanel, autoBtn, lastW, lastH
    try
        WinGetPos &wx, &wy, &ww, &wh, DOTA_WIN
    catch
        return false
    if !ww || !wh
        return false
    if ww = lastW && wh = lastH
        return true
    lastW := ww, lastH := wh
    k := wh / 1440.0
    if autoClose
        closeX := wx + ww - Round(60 * k), closeY := wy + Round(58 * k)
    if autoPanel
        panelX := wx + Round(ww / 2) - Round(81 * k)
        , panelY := wy + Round(wh / 2) - Round(36 * k)
    if autoBtn
        btnX := panelX, btnY := panelY
    Log(Format("окно доты {1}x{2}: кнопка закрытия {3},{4}, панель {5},{6}"
               . "{7}", ww, wh, closeX, closeY, panelX, panelY,
               (autoClose || autoPanel) ? " (посчитаны от окна)" : ""))
    return true
}
Load()
LearnLoad()

; Запомненные удачные нажатия: доли окна, а не пиксели, — тогда они
; переносятся между разрешениями и между аккаунтами (у Dota Plus окно
; принятия другое). Храним до трёх, свежее первым.
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
        ; то же место второй раз не храним
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

Log(txt) {
    global DOTA_LOGF
    try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") . "  " . txt
                   . "`n", DOTA_LOGF, "UTF-8")
}

Note(txt, ms := 1500, force := false) {
    global QUIET
    if QUIET && !force
        return
    ToolTip txt
    SetTimer () => ToolTip(), -ms
}

Px(x, y) {
    try
        return PixelGetColor(x, y)
    catch
        return -1
}

; Сравнение с допуском: дота сглаживает края и подсвечивает окно, точного
; совпадения пикселя ждать нельзя.
Same(c, w) {
    global DOTA_TOL
    if c = -1
        return false
    return Abs((c & 0xFF) - (w & 0xFF)) <= DOTA_TOL
        && Abs(((c >> 8) & 0xFF) - ((w >> 8) & 0xFF)) <= DOTA_TOL
        && Abs(((c >> 16) & 0xFF) - ((w >> 16) & 0xFF)) <= DOTA_TOL
}

; Окно ПОД ТОЧКОЙ должно быть дотой, иначе читать нечего.
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

InMenu() {
    global closeX, closeY, closeC
    return closeX ? Same(Px(closeX, closeY), closeC) : false
}

DialogUp() {
    global panelX, panelY, panelC
    return panelX ? Same(Px(panelX, panelY), panelC) : false
}

; Где нажать. Окно уже опознано по панели, поэтому зелёный тут работает не
; приметой, а линейкой: ищем его в полосе вокруг точки кнопки — по высоте
; кнопку сдвигает панель Dota Plus. Ищем ТОЛЬКО внутри окна доты.
FindButton() {
    global btnX, btnY, btnC, btnH, DOTA_TOL, DOTA_SPAN, DOTA_VSPAN
    global DOTA_SCAN_MAX, DOTA_SCAN_MS, DOTA_WIN
    if Same(Px(btnX, btnY), btnC) || (btnH && Same(Px(btnX, btnY), btnH))
        return [btnX, btnY]
    x1 := btnX - DOTA_SPAN, x2 := btnX + DOTA_SPAN
    y1 := btnY - DOTA_VSPAN, y2 := btnY + DOTA_VSPAN
    try {
        WinGetPos &wx, &wy, &ww, &wh, DOTA_WIN
        if ww > 0 && wh > 0 {
            x1 := Max(x1, wx), x2 := Min(x2, wx + ww - 1)
            y1 := Max(y1, wy), y2 := Min(y2, wy + wh - 1)
        }
    }
    if x1 > x2 || y1 > y2
        return 0
    t0 := A_TickCount
    for w in (btnH ? [btnC, btnH] : [btnC]) {
        y := y1
        Loop DOTA_SCAN_MAX {
            try {
                if !PixelSearch(&fx, &fy, x1, y, x2, y2, w, DOTA_TOL)
                    break
            } catch
                break
            if Under(fx, fy)
                return [fx, fy]
            if A_TickCount - t0 > DOTA_SCAN_MS
                return 0
            y := fy + 1
        }
    }
    return 0
}

; СНИМОК области экрана, сразу сжатый до sw x sh. Возвращает буфер
; sw*sh*4 байт, по четыре на точку: B, G, R и мусор.
; StretchBlt с HALFTONE усредняет при сжатии, а не берёт каждый n-й пиксель,
; — поэтому тонкая рамка не превращается в полосу, а большая заливка
; остаётся заливкой.
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
        NumPut("int", -sh, bi, 8)      ; минус — строки сверху вниз
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

; Зелень КНОПКИ, а не панели. Зелёный канал должен доминировать с
; запасом: у заливки кнопки (87,145,97) запас есть, у панели окна
; (48,78,66) синий почти равен зелёному — и она отсеивается.
GreenDom(c) {
    if c = -1
        return false
    r := (c >> 16) & 0xFF, g := (c >> 8) & 0xFF, b := c & 0xFF
    return g > r + 20 && g > b + 15 && g > 60 && g < 250
}

; Тот же тон: сравниваем кандидата с цветом, от которого шли по полосе.
; Допуск шире обычного — кнопка пульсирует и к краям темнеет.
SameHue(c, w) {
    if !GreenDom(c)
        return false
    return Abs(((c >> 8) & 0xFF) - ((w >> 8) & 0xFF)) <= 45
        && Abs(((c >> 16) & 0xFF) - ((w >> 16) & 0xFF)) <= 45
        && Abs((c & 0xFF) - (w & 0xFF)) <= 45
}

; Кандидаты на кнопку ПРИНЯТЬ. Запускается один раз на ready-check, когда
; уже точно известно, что окно висит, — поэтому можно искать нормально, а не
; одним пикселем. Проверка геометрией: кнопка это ШИРОКАЯ РОВНАЯ ПОЛОСА
; своего цвета. У травы и панелей такой полосы нет, а у кнопки она есть
; всегда, в любом языке и при любом разрешении.
; wide=false — для маленькой кнопки приглашения: она уже и всплывашка
; стоит не по центру, поэтому и полоса короче, и область больше.
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
    ; Снимок ВСЕГО окна: кнопка принятия стоит по центру, а всплывашка
    ; приглашения может быть у любого края, и область для них одна.
    px := Shot(wx, wy, ww, wh, SHOT_W, SHOT_H)
    if !px
        return out
    kx := ww / SHOT_W, ky := wh / SHOT_H
    ; Минимальная ширина полосы — в клетках снимка. BTN_MINW задан для
    ; 1440p, поэтому сначала переводим в пиксели этого окна, потом в клетки.
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
    ; Самая широкая полоса — скорее всего кнопка. Сортируем по ширине и
    ; схлопываем соседние строки одной и той же кнопки в одного кандидата.
    ; Внутри корзины «нормальной ширины» первой пойдёт самая широкая.
    Loop rows.Length - 1 {
        i := A_Index
        Loop rows.Length - i {
            j := A_Index
            if (rows[j][2] - rows[j][1]) < (rows[j + 1][2] - rows[j + 1][1]) {
                _t := rows[j], rows[j] := rows[j + 1], rows[j + 1] := _t
            }
        }
    }
    ; Сначала собираем всех, потом раскладываем по трём корзинам:
    ; 1) рядом с запомненным удачным местом — сразу,
    ; 2) нормальной ширины — по убыванию ширины,
    ; 3) шире четверти окна — в конец, это панели, а не кнопки.
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
            if Abs((cx - wx) / ww - L[1]) < 0.06
               && Abs((cy - wy) / wh - L[2]) < 0.06
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

; Если окно принятия опознано, а зелёного нет — пишем в лог весь столбец.
; По этим строкам видно, где кнопка на самом деле, и точку можно поправить
; не гадая. Один раз на окно, иначе лог захлебнётся.
DumpColumn(why := "окно принятия вижу, зелёной кнопки не нашёл") {
    global DOTA_WIN
    ; Сетка по середине окна, а не один столбец: по одному столбцу в
    ; прошлый раз пришлось угадывать, где кнопка, а где панель.
    try
        WinGetPos &wx, &wy, &ww, &wh, DOTA_WIN
    catch
        return
    s := ""
    Loop 5 {
        px := wx + Round(ww * (0.35 + 0.075 * (A_Index - 1)))
        s .= "`n  x=" . px . ":"
        y := wy + Round(wh * 0.2)
        while y <= wy + Round(wh * 0.8) {
            s .= Format(" {1}:{2:#06x}", y, Px(px, y))
            y += Round(wh * 0.025)
        }
    }
    Log(why . ". сетка:" . s)
}

; ── console.log доты ─────────────────────────────────────────────────
; Путь берём от самого процесса, а не угадываем: у стима может быть вторая
; библиотека на другом диске. exe лежит в game\bin\win64, лог — в game\dota.
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

; ID лобби из куска лога — берём ПОСЛЕДНЕЕ вхождение, оно самое свежее.
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

; Новые байты лога. Читаем только хвост: файл за сессию вырастает на
; десятки килобайт, перечитывать его целиком пять раз в секунду незачем.
ClogNew() {
    global clogPath, clogPos
    try {
        ; Просто "r". Суффикс "-rwd" в AHK ЗАПРЕЩАЕТ другим процессам
        ; читать-писать-удалять файл, а дота держит его открытым на
        ; запись — открыть не удавалось, и лог читался как пустой.
        f := FileOpen(clogPath, "r")
        if !f
            return ""
        ; Дота СТИРАЕТ console.log при каждом своём запуске. Значит файл
        ; короче запомненной позиции — это новая сессия, и встаём в его
        ; КОНЕЦ, а не в начало: с начала мы перечитали бы весь лог этой
        ; сессии разом и приняли бы старый ready-check за новый.
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

; ── трей ─────────────────────────────────────────────────────────────
BuildTray() {
    global M_PAUSE, M_PROBE, M_CLOSE, M_PANEL, M_BTN, M_RUN, M_LOG
    t := A_TrayMenu
    t.Delete()
    t.Add(M_PAUSE, (*) => TogglePause())
    t.Add(M_PROBE, (*) => Probe())
    t.Add()
    t.Add(M_CLOSE, (*) => GrabStart("close"))
    t.Add(M_PANEL, (*) => GrabStart("panel"))
    t.Add(M_BTN, (*) => GrabStart("accept"))
    t.Add("Пати: точка панели приглашения  (Ctrl+Alt+K)",
          (*) => GrabStart("invp"))
    t.Add("Пати: точка кнопки принять  (Ctrl+Alt+J)",
          (*) => GrabStart("invb"))
    t.Add("СНИМОК при живом окне принятия  (Ctrl+Alt+D)", (*) => Send("^!d"))
    t.Add()
    t.Add(M_RUN, (*) => StartupToggle())
    t.Add(M_LOG, (*) => OpenLog())
    t.Add()
    t.Add("Выход", (*) => ExitApp())
    t.Default := M_PROBE
    Status()
}

Status() {
    global dotaPause, dotaLive, closeX, closeY, panelX
    global M_PAUSE, M_RUN, DOTA_LNK, clogOk
    s := dotaPause ? "пауза"
       : dotaLive != 1 ? "доты нет"
       : clogOk ? "жду матч (по логу доты)"
       : !closeX || !panelX ? "нужны точки: Ctrl+Alt+C и Ctrl+Alt+W"
       : !Under(closeX, closeY) ? "дота закрыта другим окном"
       : InMenu() ? "меню — жду окно принятия"
       : "не меню (бой или загрузка)"
    A_IconTip := "Dota auto-accept — " . s
    try {
        t := A_TrayMenu
        if dotaPause
            t.Check(M_PAUSE)
        else
            t.Uncheck(M_PAUSE)
        if FileExist(DOTA_LNK)
            t.Check(M_RUN)
        else
            t.Uncheck(M_RUN)
    }
}

TogglePause(*) {
    global dotaPause, hits, clicks, seenAt
    dotaPause := !dotaPause
    hits := 0, clicks := 0, seenAt := 0
    Log(dotaPause ? "ПАУЗА вручную" : "снова авто")
    Status()
    Note(dotaPause ? "Dota auto-accept: ПАУЗА`n(Ctrl+Alt+P — обратно)"
                   : "Dota auto-accept: авто", 2000, true)
}

^!p::TogglePause()

StartupToggle(*) {
    global DOTA_LNK
    if FileExist(DOTA_LNK) {
        try FileDelete(DOTA_LNK)
        Log("убран из автозагрузки")
        Note("С Windows больше не запускается", 2500, true)
    } else {
        try {
            FileCreateShortcut(A_ScriptFullPath, DOTA_LNK, A_ScriptDir)
            Log("добавлен в автозагрузку")
            Note("Теперь запускается вместе с Windows", 2500, true)
        } catch as e {
            Note("не вышло положить ярлык:`n" . e.Message, 4000, true)
        }
    }
    Status()
}

OpenLog(*) {
    global DOTA_LOGF
    if !FileExist(DOTA_LOGF)
        return Note("лог пока пустой", 2000, true)
    try Run(DOTA_LOGF)
}

; ── снятие точек ─────────────────────────────────────────────────────
; Координаты берём сразу, цвет через DOTA_SAMPLE_WAIT: кнопка под курсором
; подсвечивается, и снятый «наведённый» цвет потом не совпал бы никогда.
GrabStart(which) {
    global DOTA_SAMPLE_WAIT, pend
    MouseGetPos &mx, &my
    pend := (which = "accept" || which = "invb") ? Px(mx, my) : 0
    nm := which = "close" ? "КНОПКИ ЗАКРЫТИЯ"
        : which = "panel" ? "ПАНЕЛИ окна принятия"
        : which = "invp" ? "ПАНЕЛИ приглашения"
        : which = "invb" ? "КНОПКИ приглашения" : "ЗЕЛЁНОЙ кнопки"
    Note(Format("точка {4} {1},{2} взята. Убери мышь — цвет через {3} с",
                mx, my, DOTA_SAMPLE_WAIT // 1000, nm), DOTA_SAMPLE_WAIT,
         true)
    SetTimer () => GrabColor(which, mx, my), -DOTA_SAMPLE_WAIT
}

GrabColor(which, x, y) {
    global closeX, closeY, closeC, panelX, panelY, panelC
    global btnX, btnY, btnC, btnH, pend, DOTA_INI
    global autoClose, autoPanel, autoBtn
    global invPX, invPY, invPC, invBX, invBY, invBC, invBH
    c := Px(x, y)
    if c = -1
        return Note("цвет считать не удалось", 1500, true)
    sec := (which = "accept") ? "accept"
         : (which = "invp" || which = "invb") ? "invite" : which
    if which = "close"
        closeX := x, closeY := y, closeC := c, autoClose := false
    else if which = "panel"
        panelX := x, panelY := y, panelC := c, autoPanel := false
    else if which = "invp" {
        invPX := x, invPY := y, invPC := c
        IniWrite x, DOTA_INI, "invite", "px"
        IniWrite y, DOTA_INI, "invite", "py"
        IniWrite c, DOTA_INI, "invite", "pcolor"
    } else if which = "invb" {
        invBX := x, invBY := y, invBC := c
        invBH := (pend != -1 && pend && !Same(pend, c)) ? pend : 0
        IniWrite x, DOTA_INI, "invite", "bx"
        IniWrite y, DOTA_INI, "invite", "by"
        IniWrite c, DOTA_INI, "invite", "bcolor"
        IniWrite invBH, DOTA_INI, "invite", "bhover"
    } else {
        btnX := x, btnY := y, btnC := c, autoBtn := false
        ; Подсвеченный цвет берём, только если он сам отличается от обычного:
        ; иначе это не подсветка, а тот же фон.
        btnH := (pend != -1 && pend && !Same(pend, c)) ? pend : 0
        IniWrite btnH, DOTA_INI, "accept", "hover"
    }
    if which != "invp" && which != "invb" {
        IniWrite x, DOTA_INI, sec, "x"
        IniWrite y, DOTA_INI, sec, "y"
        IniWrite c, DOTA_INI, sec, "color"
    }
    nm := which = "close" ? "кнопки закрытия"
        : which = "panel" ? "панели окна"
        : which = "invp" ? "панели приглашения"
        : which = "invb" ? "кнопки приглашения" : "зелёной кнопки"
    Note(Format("точка {4} запомнена: {1},{2}  цвет {3:#06x}", x, y, c, nm)
         . ((which = "accept" && btnH)
            ? Format("`nподсвеченный {1:#06x}", btnH) : ""), 4000, true)
    Status()
}

; СНИМОК в момент, когда окно принятия висит. Прицеливаться не надо: точки
; уже запомнены, он читает цвет в них сам. Нужен, чтобы ответить на один
; оставшийся вопрос — затемнена ли кнопка закрытия уже в этот момент или
; только после принятия. Плюс пишет в лог весь столбец, где живёт зелёная
; кнопка: по нему её точка ставится точно, а не на глаз.
^!d:: {
    global closeX, closeY, closeC, panelX, panelY, panelC, DOTA_INI
    cc := Px(closeX, closeY), pc := Px(panelX, panelY)
    IniWrite cc, DOTA_INI, "found", "close"
    IniWrite pc, DOTA_INI, "found", "panel"
    _cs := Same(cc, closeC) ? "как в меню" : "ДРУГАЯ"
    _ps := Same(pc, panelC) ? "как у окна принятия" : "другая"
    Log(Format("СНИМОК: кнопка закрытия {1},{2} = {3:#06x} ({4}), панель "
        . "{5},{6} = {7:#06x} ({8})", closeX, closeY, cc, _cs,
        panelX, panelY, pc, _ps))
    DumpColumn("СНИМОК")
    Note(Format("снято, записано в лог:`nкнопка закрытия {1:#06x} — {2}`n"
        . "панель {3:#06x} — {4}", cc, _cs, pc, _ps), 6000, true)
}

^!k::GrabStart("invp")
^!j::GrabStart("invb")

^!c::GrabStart("close")
^!w::GrabStart("panel")
^!f::GrabStart("accept")

; ── что видно сейчас ─────────────────────────────────────────────────
^!t::Probe()

Probe(*) {
    global closeX, closeY, closeC, panelX, panelY, panelC, btnX, btnY
    global dotaPause, dotaLive, DOTA_EXE
    global invPX, invPY, invPC, invBX, invBY, invBC
    b := FindButton()
    Note(Format("состояние: {1}`n`n"
        . "кнопка закрытия {2},{3}`n  запомнен {4:#06x}, сейчас {5:#06x} — {6}`n"
        . "панель окна {7},{8}`n  запомнен {9:#06x}, сейчас {10:#06x} — {11}`n"
        . "зелёная кнопка: {12}`n`n{13}`n`nпати: {14}",
        dotaPause ? "ПАУЗА" : !ProcessExist(DOTA_EXE) ? "доты нет"
            : !Under(closeX, closeY) ? "дота закрыта другим окном"
            : InMenu() ? "меню" : "не меню (бой или загрузка)",
        closeX, closeY, closeC, Px(closeX, closeY),
        InMenu() ? "совпало (мы в меню)" : "нет",
        panelX, panelY, panelC, Px(panelX, panelY),
        DialogUp() ? "СОВПАЛО (окно принятия висит)" : "нет",
        b ? Format("{1},{2}", b[1], b[2]) : "не найдена",
        (InMenu() && DialogUp()) ? "сейчас я бы нажал"
                                 : "сейчас нажатия не будет",
        !invPX ? "точки не сняты (Ctrl+Alt+K и Ctrl+Alt+J)"
               : (Same(Px(invPX, invPY), invPC)
                  && Same(Px(invBX, invBY), invBC))
                 ? "приглашение вижу — нажал бы" : "приглашения нет"),
        8000, true)
}

; ЖМЁМ. Вызывается, когда лог сказал, что идёт ready-check. Щёлкаем по
; кандидату и ЖДЁМ ПОДТВЕРЖДЕНИЯ: дота сама пишет в лог наш клик строкой
; Send 7070. Нет подтверждения — значит промах, берём следующего кандидата.
; Это и есть то, чего не было у пиксельной версии: она надеялась, а эта
; знает.
; НАЖАТИЕ БЕЗ МЫШИ. Шлём окну доты сообщения о щелчке в его координатах —
; курсор не трогается вообще. Panorama может их проигнорировать, поэтому
; это только первая попытка: если лог не подтвердит, жмём настоящим кликом.
; slow — для всплывашек. Факт: на приглашении в пати быстрое тихое нажатие
; (движение, 20 мс, клик) не прошло, мышью прошло. ГИПОТЕЗА: Panorama вешает
; :hover на кнопку только на следующем кадре. Поэтому подводим «курсор» в два
; шага и даём кнопке время подсветиться; сработает ли — смотреть в логе по
; слову «без мыши» / «мышью» в строке ПРИНЯЛ пати.
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

; ── кнопка ACCEPT во всплывашке приглашения ──────────────────────────
; Замерено 20.10.2026 на живом приглашении: кнопка СЕРАЯ (0x3b4248 ±), а не
; зелёная, поэтому поиск зелени её не видит и по пати тыкал в чужое — первым
; кандидатом шла PLAY главного меню. Окно приглашения по центру, и кнопка
; стоит в долях окна: x 0.373–0.492, y 0.606–0.647 (правее, с 0.51 — DECLINE).
; Кликаем в центр ACCEPT, но только если угловые точки кнопки серые: проверка
; на «а есть ли она вообще», чтобы не щёлкать в игру, когда окна нет.
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

; Окно рисуется не мгновенно после строки лога, поэтому ждём до ~2.5 с.
PartyCands(wx, wy, ww, wh) {
    global PARTY_BX, PARTY_BY
    Loop 17 {
        cx := wx + Round(ww * PARTY_BX)
        cy := wy + Round(wh * PARTY_BY)
        if PartyGate(wx, wy, ww, wh) && Under(cx, cy)
            return [[cx, cy, Round(ww * 0.12), Px(cx - Round(ww * 0.03), cy)]]
        Sleep 150
    }
    return []
}

; what: "матч" или "пати". Разница только в том, какую строку лога
; считать подтверждением и какой кнопку искать.
TryAccept(what := "матч") {
    global CLOG_MINE, CLOG_INVOK, CLOG_WAIT, CLOG_TRIES
    global readyDone, readyTries, invDone, invTried
    global holdTill, CLOG_SILENT, CLOG_HOLD, CLOG_READY, readyAt, lastTry
    if A_TickCount < holdTill
        return false            ; только что приняли, второй раз не надо
    _wide := (what = "матч")
    try
        WinGetPos &_wx, &_wy, &_ww, &_wh, "ahk_exe dota2.exe"
    catch
        return false
    if !_ww || !_wh
        return false
    _ok := _wide ? CLOG_MINE : CLOG_INVOK
    lastTry := A_TickCount
    cands := _wide ? FindAccept(true) : PartyCands(_wx, _wy, _ww, _wh)
    if !cands.Length {
        Log(what . ": сигнал есть, а кнопку на экране не нашёл")
        DumpColumn(what . " без кнопки")
        return false
    }
    for c in cands {
        if (_wide ? readyTries : invTried) >= CLOG_TRIES
            return false
        if _wide
            readyTries++
        else
            invTried++
        ; Сначала тихо, без мыши. Не подтвердилось — тогда уже кликом.
        _how := "без мыши"
        ; Всплывашка пати появляется с анимацией: пиксели кнопки уже серые,
        ; а нажатие она ещё не берёт. Мышью через ~1 с проходило, быстрым
        ; тихим в первые 100 мс — нет. ГИПОТЕЗА, проверяется логом: даём
        ; ей отстояться, потом бьём тихо, при неудаче — второй раз с долгим
        ; наведением, и только потом мышью.
        if !_wide {
            Sleep 700
            ; За это время приглашение могли принять руками или оно ушло:
            ; тогда под точкой уже меню, и щёлкать в него нельзя.
            _ch := ClogNew()
            if InStr(_ch, _ok) {
                invDone := true
                Log("пати: ответили сами, пока ждал — не трогаю")
                return true
            }
            if !PartyGate(_wx, _wy, _ww, _wh) {
                Log("пати: окно приглашения исчезло — не трогаю")
                return false
            }
        }
        ClickSilent(c[1], c[2])
        t0 := A_TickCount
        _lim := CLOG_SILENT
        _hard := false
        _slow := _wide                  ; второй тихий — только для пати
        while A_TickCount - t0 < _lim {
            Sleep 120
            _ch := ClogNew()
            if InStr(_ch, CLOG_READY)
                readyAt := A_TickCount      ; сигнал ещё идёт, это тот же матч
            if InStr(_ch, _ok) {
                if _wide {
                    readyDone := true
                    holdTill := A_TickCount + CLOG_HOLD
                    LearnSave((c[1] - _wx) / _ww, (c[2] - _wy) / _wh,
                              c[3] / _ww)
                } else
                    invDone := true
                Log(Format("ПРИНЯЛ {5} {7}: клик {1},{2} (полоса {3} px, "
                           . "цвет {6:#06x}), дота подтвердила за {4} мс",
                           c[1], c[2], c[3], A_TickCount - t0, what,
                           c.Has(4) ? c[4] : 0, _how))
                return true
            }
            if !_slow && A_TickCount - t0 >= 450 {
                _slow := true
                _how := "без мыши (с наведением)"
                ClickSilent(c[1], c[2], true)
            }
            ; тихое не сработало — добираем настоящим кликом
            if !_hard && A_TickCount - t0 >= CLOG_SILENT - 120 {
                _hard := true
                _how := "мышью"
                _lim := CLOG_SILENT + CLOG_WAIT
                MouseGetPos &ox, &oy
                Click c[1] . " " . c[2]
                Sleep 60
                MouseMove ox, oy, 0
            }
        }
        Log(Format("{4}: клик {1},{2} (полоса {3} px, цвет {5:#06x}) — "
                   . "подтверждения нет, пробую следующего", c[1], c[2],
                   c[3], what, c.Has(4) ? c[4] : 0))
    }
    return false
}

; ── главный такт ─────────────────────────────────────────────────────
Tick() {
    global DOTA_EXE, DOTA_POLL, DOTA_IDLE, DOTA_NEED, DOTA_STUCK
    global dotaLive, dotaPause, closeX, closeY, panelX
    global hits, nextAt, seenAt, clicks, dumped
    global invPX, invPY, invPC, invBX, invBY, invBC, invBH
    global invHits, invNext, invClicks
    global clogPath, clogPos, clogOk, clogSaid
    global CLOG_READY, CLOG_MINE, CLOG_START
    global CLOG_INV, CLOG_INVOK, CLOG_PARTY
    global readyAt, readyDone, readyTries
    global invAt, invDone, invTried
    global READY_GAP, holdTill, CLOG_LOBBY, curLobby, lastTry
    global CLOG_TRIES, RETRY_MS

    live := ProcessExist(DOTA_EXE) ? 1 : 0
    if live != dotaLive {
        dotaLive := live
        hits := 0, clicks := 0, seenAt := 0, nextAt := 0, dumped := false
        ; Лог ищем заново: у новой сессии доты он новый, и позицию надо
        ; заново поставить в его конец.
        clogOk := false, clogPos := 0
        readyDone := false, invDone := false
        Log(live ? "дота запущена — на взводе" : "дота закрыта — сплю")
        Status()
        SetTimer Tick, live ? DOTA_POLL : DOTA_IDLE
    }
    if !live || dotaPause
        return
    ; Пульс раз в 15 минут: 20.10 скрипт тихо умер посреди дня, и по логу
    ; нельзя было понять, когда. Теперь последняя строка «жив» покажет.
    static lastBeat := A_TickCount
    if A_TickCount - lastBeat > 900000 {
        lastBeat := A_TickCount
        Log("жив")
    }

    ; ── ГЛАВНЫЙ ПУТЬ: лог доты ──────────────────────────────────────
    if !clogOk {
        clogPath := ClogFind()
        if clogPath != "" {
            try clogPos := FileGetSize(clogPath)
            clogOk := true
            Log("лог доты найден, работаю по нему: " . clogPath)
            Status()
        } else if !clogSaid {
            clogSaid := true
            Log("console.log доты не найден — работаю по экрану. Чтобы "
                . "работать точно, добавь -condebug в параметры запуска доты")
        }
    }
    if clogOk {
        _new := ClogNew()
        if _new != "" {
            if InStr(_new, CLOG_MINE) {
                readyDone := true       ; принял он сам, нам делать нечего
                readyAt := A_TickCount
            }
            if InStr(_new, CLOG_START)
                Log("сервер выдан — матч стартует")
            ; ПАТИ. Своё событие, мимо ready-check: приглашение приходит
            ; и в меню, и посреди матча.
            ; Каждая подписка на Invite — новое приглашение, даже если
            ; секунду назад кто-то уже ответил на прошлое (друг скинул
            ; пати повторно). Отбрасываем только дубль строки в пределах
            ; 1.5 с. Порядок в куске лога решает, что было позже.
            _pOk := InStr(_new, CLOG_INVOK, , -1)
            _pInv := InStr(_new, CLOG_INV, , -1)
            if _pOk
                invDone := true         ; ответил он сам или мы
            if _pInv > _pOk {
                if A_TickCount - invAt > 1500 {
                    invDone := false, invTried := 0
                    Log("ПРИГЛАШЕНИЕ В ПАТИ (лог)")
                }
                invAt := A_TickCount
                if !invDone
                    TryAccept("пати")
            }
            ; Новое лобби — это другой матч, и единственный верный признак.
            _lob := LobbyId(_new)
            if _lob != "" && _lob != curLobby {
                curLobby := _lob
                readyDone := false, readyTries := 0, lastTry := 0
                Log("новое лобби " . _lob)
            }
            if InStr(_new, CLOG_READY) {
                ; Все кандидаты промазали — через RETRY_MS пробуем снова:
                ; окно висит ~25 секунд, а «кликаем пока игру не регнет».
                if !readyDone && readyTries >= CLOG_TRIES
                   && A_TickCount - lastTry > RETRY_MS {
                    readyTries := 0
                    Log("окно ещё висит — пробую кандидатов заново")
                }
                if A_TickCount - readyAt > READY_GAP {
                    ; Новый ready-check — только если сигнала не было
                    ; совсем давно. Пять секунд оказалось мало: пока
                    ; перебирались кандидаты, тот же матч успевал
                    ; показаться новым, и курсор дёргался ещё пять раз
                    ; уже после принятия.
                    readyDone := false, readyTries := 0
                    Log("МАТЧ НАЙДЕН (лог: ready-check)")
                }
                readyAt := A_TickCount
                if !readyDone
                    TryAccept()
            }
        }
        return                          ; по экрану больше ничего не решаем
    }

    if !AutoPoints() || !closeX || !panelX
        return                      ; окна ещё нет или точек нет
    ; Дота жива, но не видна — все пиксели в этот момент чужие.
    if !Under(closeX, closeY) {
        hits := 0, seenAt := 0
        return
    }
    ; 0. ПРИГЛАШЕНИЕ В ПАТИ — до всего остального и мимо кнопки закрытия:
    ;    всплывашка приходит и посреди матча. Зато требует совпадения ДВУХ
    ;    своих точек сразу — панели и кнопки. Одной зелёной мало, на этом
    ;    мы уже обожглись: тёмно-зелёный есть и в траве, и в панелях.
    if invPX && invBX {
        if Same(Px(invPX, invPY), invPC)
           && (Same(Px(invBX, invBY), invBC)
               || (invBH && Same(Px(invBX, invBY), invBH)))
           && Under(invBX, invBY) {
            if ++invHits >= DOTA_NEED && A_TickCount >= invNext {
                invHits := 0
                MouseGetPos &iox, &ioy
                Click invBX . " " . invBY
                Sleep 60
                MouseMove iox, ioy, 0
                invNext := A_TickCount + 2000
                invClicks++
                Log(Format("приглашение в пати: клик по {1},{2} (клик {3})",
                           invBX, invBY, invClicks))
                if invClicks >= DOTA_STUCK {
                    dotaPause := true
                    invClicks := 0
                    Log("приглашение не исчезает после " . DOTA_STUCK
                        . " кликов — пауза")
                    Status()
                    return Note("Щёлкнул " . DOTA_STUCK . " раз по "
                        . "приглашению, а оно на месте — встал на ПАУЗУ."
                        . "`nПересними его точки: Ctrl+Alt+K и Ctrl+Alt+J.",
                        10000, true)
                }
            }
        } else
            invHits := 0, invClicks := 0
    }
    ; 1. мы в меню? В бою кнопки закрытия на экране нет, и это единственная
    ;    защита, которая нужна: щёлкать посреди матча нельзя.
    if !InMenu() {
        hits := 0, seenAt := 0, dumped := false
        return
    }
    ; 2. висит ли окно принятия
    if !DialogUp() {
        hits := 0, seenAt := 0, dumped := false, clicks := 0
        return
    }
    if A_TickCount < nextAt
        return                      ; только что жали, даём окну исчезнуть
    if !seenAt
        seenAt := A_TickCount
    if ++hits < DOTA_NEED
        return
    hits := 0
    b := FindButton()
    if !b {
        if !dumped {
            dumped := true
            DumpColumn()
            Note("окно принятия вижу, а зелёной кнопки не нашёл.`nНаведись на "
                 . "неё и нажми Ctrl+Alt+F — столбец я записал в лог.",
                 6000, true)
        }
        nextAt := A_TickCount + 1000
        return
    }
    el := A_TickCount - seenAt
    MouseGetPos &ox, &oy
    Click b[1] . " " . b[2]
    Sleep 60
    MouseMove ox, oy, 0             ; мышь обратно, без анимации
    seenAt := 0
    nextAt := A_TickCount + 900     ; короткая пауза: если первый клик ушёл
                                    ; на поднятие окна, следующий опрос добьёт
    clicks++
    Log(Format("клик по {1},{2}: {3} мс от появления панели (клик {4})",
               b[1], b[2], el, clicks))
    ; Настоящее окно после клика уходит. Не уходит — значит мы щёлкаем не
    ; туда, и лучше встать на паузу, чем тыкать до утра.
    if clicks >= DOTA_STUCK {
        dotaPause := true
        clicks := 0
        Log("окно принятия не исчезает после " . DOTA_STUCK . " кликов — пауза")
        Status()
        return Note("Щёлкнул " . DOTA_STUCK . " раз, а окно принятия на месте."
            . "`nЗначит жму не туда — встал на ПАУЗУ.`nНаведись на зелёную "
            . "кнопку, Ctrl+Alt+F, потом Ctrl+Alt+P обратно в авто.",
            10000, true)
    }
    ; Про принятый матч молчим: он и так начался, а тултипса поверх игры —
    ; это ровно то, чего он просил не делать.
}

; ПЕРВЫЙ ЗАПУСК. Весь смысл в том, чтобы «скачал, нажал кнопочку и всё
; работает» — поэтому при первом же запуске он сам кладёт ярлык в
; автозагрузку и больше про это не вспоминает (метка в ini). Выключить —
; там же в трее, галка «Запускать вместе с Windows».
FirstRun() {
    global DOTA_INI, DOTA_LNK
    if IniRead(DOTA_INI, "setup", "done", "") != ""
        return
    IniWrite 1, DOTA_INI, "setup", "done"
    if FileExist(DOTA_LNK)
        return
    try {
        FileCreateShortcut(A_ScriptFullPath, DOTA_LNK, A_ScriptDir)
        Log("первый запуск: положил ярлык в автозагрузку")
        Note("Автопринятие матча включено и будет включаться с Windows."
             . "`nВыключить — значок в трее, Ctrl+Alt+P пауза."
             . "`nБольше я ничего показывать не буду.", 7000, true)
    } catch as e {
        Log("первый запуск: ярлык не положил — " . e.Message)
    }
}

BuildTray()
FirstRun()
Log("скрипт запущен")
SetTimer Tick, 100
