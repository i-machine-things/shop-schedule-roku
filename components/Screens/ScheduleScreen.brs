' Column layout for job rows -- fixed x offsets within a 1920-wide screen,
' mirroring the web kiosk's table column order (job/customer/part/rev/oper/
' qty/sched/currwc/remhrs/shipqty/promised). Single-line rows (part number +
' description combined, sched start/end combined) rather than the web's
' multi-line cells -- simpler and more reliable to lay out correctly in
' SceneGraph than wrestling per-cell text wrapping.
sub init()
    m.COLS = [
        { x: 30,   w: 100, key: "job" }
        { x: 140,  w: 170, key: "customer" }
        { x: 320,  w: 480, key: "partdesc" }
        { x: 810,  w: 60,  key: "rev" }
        { x: 880,  w: 90,  key: "oper" }
        { x: 980,  w: 70,  key: "qty" }
        { x: 1060, w: 190, key: "sched" }
        { x: 1260, w: 150, key: "currwc" }
        { x: 1420, w: 90,  key: "remhrs" }
        { x: 1520, w: 90,  key: "shipqty" }
        { x: 1620, w: 220, key: "promised" }
    ]

    m.DEPT_COLORS = {
        assembly:   { bg: "0x0D2B1AFF", accent: "0x1A6640FF" }
        cnc:        { bg: "0x0D1A2BFF", accent: "0x1A4466FF" }
        inspection: { bg: "0x1E0D2BFF", accent: "0x4D2080FF" }
        shipping:   { bg: "0x2B1A0DFF", accent: "0x664020FF" }
        welding:    { bg: "0x2B0D0DFF", accent: "0x661A1AFF" }
        manual:     { bg: "0x0D2B2BFF", accent: "0x1A6666FF" }
        machine:    { bg: "0x1A1A0DFF", accent: "0x404020FF" }
        engineer:   { bg: "0x1A0D1AFF", accent: "0x401A40FF" }
    }

    m.titleLabel = m.top.findNode("titleLabel")
    m.metaLabel = m.top.findNode("metaLabel")
    m.clockLabel = m.top.findNode("clockLabel")
    m.viewport = m.top.findNode("viewport")
    m.scrollContent = m.top.findNode("scrollContent")
    m.errorBanner = m.top.findNode("errorBanner")
    m.errorLabel = m.top.findNode("errorLabel")
    m.loadingLabel = m.top.findNode("loadingLabel")
    m.scheduleTask = m.top.findNode("scheduleTask")
    m.refreshTimer = m.top.findNode("refreshTimer")
    m.scrollTimer = m.top.findNode("scrollTimer")
    m.pauseTimer = m.top.findNode("pauseTimer")
    m.clockTimer = m.top.findNode("clockTimer")

    m.scheduleTask.observeField("scheduleData", "onScheduleData")
    m.refreshTimer.observeField("fire", "onRefreshTimer")
    m.scrollTimer.observeField("fire", "onScrollTick")
    m.pauseTimer.observeField("fire", "onPauseTimerFire")
    m.clockTimer.observeField("fire", "onClockTick")

    m.viewportHeight = 1080 - 70
    m.contentHeight = 0
    m.scrollY = 0
    m.scrollState = "idle"
    m.SCROLL_SPEED = 1.1

    m.MONTHS = { jan: 1, feb: 2, mar: 3, apr: 4, may: 5, jun: 6, jul: 7, aug: 8, sep: 9, oct: 10, nov: 11, dec: 12 }
end sub

sub screenShown()
    m.top.setFocus(true)
    updateClock()
    m.clockTimer.control = "start"

    sec = CreateObject("roRegistrySection", "ScheduleConfig")
    m.serverUrl = sec.Read("serverUrl")

    requestFetch()
    m.refreshTimer.control = "start"
end sub

sub requestFetch()
    m.scheduleTask.serverUrl = m.serverUrl
    m.scheduleTask.control = "RUN"
end sub

sub onRefreshTimer()
    requestFetch()
end sub

sub onClockTick()
    updateClock()
end sub

sub updateClock()
    dt = CreateObject("roDateTime")
    dt.ToLocalTime()
    h = dt.GetHours()
    ampm = "AM"
    if h = 0 then
        h = 12
    else if h = 12 then
        ampm = "PM"
    else if h > 12 then
        h = h - 12
        ampm = "PM"
    end if
    m.clockLabel.text = h.ToStr() + ":" + leftPad(dt.GetMinutes().ToStr(), 2) + ":" + leftPad(dt.GetSeconds().ToStr(), 2) + " " + ampm
end sub

function leftPad(s as String, width as Integer) as String
    result = s
    while result.Len() < width
        result = "0" + result
    end while
    return result
end function

sub onScheduleData()
    data = m.scheduleTask.scheduleData
    m.loadingLabel.visible = false
    if data = invalid then
        suffix = " Showing last known schedule."
        if m.contentHeight = 0 then suffix = " No schedule loaded yet."
        m.errorLabel.text = "Connection problem: " + m.scheduleTask.errorMessage + suffix
        m.errorBanner.visible = true
        ' Leave whatever's already on screen alone -- a transient fetch failure
        ' shouldn't blank an otherwise-fine kiosk display.
        return
    end if

    m.errorBanner.visible = false

    reportDate = ""
    thruDate = ""
    if data.report_date <> invalid then reportDate = data.report_date
    if data.thru_date <> invalid then thruDate = data.thru_date
    m.metaLabel.text = "Report: " + reportDate + "   |   Thru: " + thruDate

    buildContent(data.sections)
end sub

sub buildContent(sections as Object)
    m.scrollContent.removeChildren(m.scrollContent.getChildren(-1, 0))
    m.scrollTimer.control = "stop"
    m.pauseTimer.control = "stop"
    m.scrollState = "idle"

    y = 0
    for each section in sections
        if section.jobs <> invalid and section.jobs.Count() > 0 then
            headerGroup = buildSectionHeader(section, y)
            m.scrollContent.appendChild(headerGroup)
            y = y + 56

            for each job in section.jobs
                rowGroup = buildJobRow(job, y)
                m.scrollContent.appendChild(rowGroup)
                y = y + 48
            end for
        end if
    end for

    m.contentHeight = y
    m.scrollY = 0
    m.scrollContent.translation = [0, 0]

    if m.contentHeight > m.viewportHeight then
        m.scrollState = "scrolling"
        m.scrollTimer.control = "start"
    end if
end sub

function buildSectionHeader(section as Object, y as Integer) as Object
    colors = colorsForDept(section.department)

    group = CreateObject("roSGNode", "Group")
    group.translation = [0, y]

    bg = CreateObject("roSGNode", "Rectangle")
    bg.width = 1920
    bg.height = 56
    bg.color = colors.bg
    group.appendChild(bg)

    accentBar = CreateObject("roSGNode", "Rectangle")
    accentBar.width = 6
    accentBar.height = 56
    accentBar.color = colors.accent
    group.appendChild(accentBar)

    wcLabel = CreateObject("roSGNode", "Label")
    wcLabel.text = section.wc
    wcLabel.translation = [30, 14]
    wcLabel.font = "font:LargeBoldSystemFont"
    wcLabel.color = "0xFFFFFFFF"
    group.appendChild(wcLabel)

    deptLabel = CreateObject("roSGNode", "Label")
    deptLabel.text = section.department + "   -   " + section.wc_group
    deptLabel.translation = [360, 20]
    deptLabel.font = "font:SmallSystemFont"
    deptLabel.color = "0x999999FF"
    group.appendChild(deptLabel)

    return group
end function

function colorsForDept(department as String) as Object
    deptLower = LCase(department)
    for each keyword in m.DEPT_COLORS
        if deptLower.InStr(0, keyword) >= 0 then
            return m.DEPT_COLORS[keyword]
        end if
    end for
    return { bg: "0x1A1A1AFF", accent: "0x666666FF" }
end function

function buildJobRow(job as Object, y as Integer) as Object
    group = CreateObject("roSGNode", "Group")
    group.translation = [0, y]

    bg = CreateObject("roSGNode", "Rectangle")
    bg.width = 1920
    bg.height = 48
    bg.color = "0x0A0A14FF"
    group.appendChild(bg)

    overdue = isOverdue(job.promised)
    promisedColor = "0xCCCCCCFF"
    if overdue then promisedColor = "0xFF5555FF"

    partDesc = job.part
    if job.description <> invalid and job.description <> "" then
        partDesc = partDesc + " - " + job.description
    end if

    schedText = job.sch_start
    if job.sch_end <> invalid and job.sch_end <> "" and job.sch_end <> job.sch_start then
        schedText = schedText + " to " + job.sch_end
    end if

    addCell(group, colByKey("job"),      job.job,      "0x4AAFFFFF", "font:MediumBoldSystemFont")
    addCell(group, colByKey("customer"), job.customer, "0xCCCCCCFF", "font:SmallSystemFont")
    addCell(group, colByKey("partdesc"), partDesc,     "0x999999FF", "font:SmallSystemFont")
    addCell(group, colByKey("rev"),      job.rev,      "0xCCCCCCFF", "font:SmallSystemFont")
    addCell(group, colByKey("oper"),     job.oper,     "0xCCCCCCFF", "font:SmallSystemFont")
    addCell(group, colByKey("qty"),      job.make_qty, "0xCCCCCCFF", "font:SmallSystemFont")
    addCell(group, colByKey("sched"),    schedText,    "0xCCCCCCFF", "font:SmallSystemFont")
    addCell(group, colByKey("currwc"),   job.curr_wc,  "0xCCCCCCFF", "font:SmallSystemFont")
    addCell(group, colByKey("remhrs"),   job.rem_hrs,  "0xCCCCCCFF", "font:SmallSystemFont")
    addCell(group, colByKey("shipqty"),  job.ship_qty, "0xCCCCCCFF", "font:SmallSystemFont")
    addCell(group, colByKey("promised"), job.promised, promisedColor, "font:MediumBoldSystemFont")

    return group
end function

function colByKey(key as String) as Object
    for each col in m.COLS
        if col.key = key then return col
    end for
    return { x: 0, w: 100 }
end function

sub addCell(parent as Object, col as Object, text as String, color as String, font as String)
    label = CreateObject("roSGNode", "Label")
    if text = invalid then text = ""
    label.text = text
    label.translation = [col.x, 12]
    label.width = col.w
    label.font = font
    label.color = color
    parent.appendChild(label)
end sub

' Dates are "DD-Mon-YY" (e.g. "16-Oct-26"), matching the PDF parser's format.
function isOverdue(promised as String) as Boolean
    if promised = invalid or promised = "" then return false

    parts = promised.Split("-")
    if parts.Count() <> 3 then return false

    day = parts[0].ToInt()
    monKey = LCase(parts[1])
    yy = parts[2].ToInt()
    if m.MONTHS[monKey] = invalid then return false
    month = m.MONTHS[monKey]
    year = 2000 + yy

    dt = CreateObject("roDateTime")
    dt.ToLocalTime()
    todayKey = dt.GetYear() * 10000 + (dt.GetMonth() * 100) + dt.GetDayOfMonth()
    promisedKey = year * 10000 + (month * 100) + day

    return promisedKey < todayKey
end function

' Scroll loop: scroll down, pause at the bottom, snap to top, pause there,
' repeat. Not a seamless infinite-wrap like the web kiosk's doubled-content
' trick -- a visible reset is a reasonable tradeoff for how much simpler it
' is to get right in SceneGraph, and still reads fine as "auto-scrolling".
sub onScrollTick()
    maxScroll = m.contentHeight - m.viewportHeight
    if maxScroll <= 0 then return

    m.scrollY = m.scrollY + m.SCROLL_SPEED
    if m.scrollY >= maxScroll then
        m.scrollY = maxScroll
        m.scrollContent.translation = [0, -m.scrollY]
        m.scrollState = "pausedAtBottom"
        m.scrollTimer.control = "stop"
        m.pauseTimer.duration = 3
        m.pauseTimer.control = "start"
    else
        m.scrollContent.translation = [0, -m.scrollY]
    end if
end sub

sub onPauseTimerFire()
    if m.scrollState = "pausedAtBottom" then
        m.scrollY = 0
        m.scrollContent.translation = [0, 0]
        m.scrollState = "pausedAtTop"
        m.pauseTimer.duration = 2
        m.pauseTimer.control = "start"
    else if m.scrollState = "pausedAtTop" then
        m.scrollState = "scrolling"
        m.scrollTimer.control = "start"
    end if
end sub

' Press "options" (the asterisk/star key) to reset the configured server and
' return to setup. Deliberately not a commonly-pressed key -- this runs
' unattended on a shop floor TV and shouldn't be easy to trigger by accident.
function onKeyEvent(key as String, press as Boolean) as Boolean
    if press and key = "options" then
        m.top.reconfigure = true
        return true
    end if
    return false
end function
