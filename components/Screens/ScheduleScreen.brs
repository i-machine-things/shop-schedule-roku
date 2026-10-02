' Only 5 fields are shown per job (per explicit scope decision): job number,
' customer, description, operation name, and current work center. Single-line
' rows with generous column widths -- an earlier 11-column layout truncated
' badly on real hardware (Roku's system fonts render much larger than this
' was designed around). Column x offsets within a 1920-wide screen:
sub init()
    m.COLS = [
        { x: 40,   w: 180, key: "job" }
        { x: 240,  w: 320, key: "customer" }
        { x: 580,  w: 850, key: "description" }
        { x: 1450, w: 150, key: "oper" }
        { x: 1620, w: 260, key: "currwc" }
    ]

    ' Keyword -> (bg, accent) color pairs, ported from update_schedule.py's
    ' _DEPT_DEFAULTS so department section colors match the web kiosk.
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
    m.stickyHeader = m.top.findNode("stickyHeader")
    m.stickyHeaderBg = m.top.findNode("stickyHeaderBg")
    m.stickyAccent = m.top.findNode("stickyAccent")
    m.stickyWcLabel = m.top.findNode("stickyWcLabel")
    m.stickyDeptLabel = m.top.findNode("stickyDeptLabel")
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
    m.heartbeatTimer = m.top.findNode("heartbeatTimer")

    m.scheduleTask.observeField("scheduleData", "onScheduleData")
    m.refreshTimer.observeField("fire", "onRefreshTimer")
    m.scrollTimer.observeField("fire", "onScrollTick")
    m.pauseTimer.observeField("fire", "onPauseTimerFire")
    m.clockTimer.observeField("fire", "onClockTick")
    m.heartbeatTimer.observeField("fire", "onHeartbeat")

    m.viewportHeight = 1080 - 186
    m.contentHeight = 0
    m.scrollY = 0
    m.scrollState = "idle"
    m.SCROLL_SPEED = 1.1
    m.sectionBounds = []
    m.currentSectionIdx = -1
    m.stickyHeader.visible = false
end sub

sub screenShown()
    m.top.setFocus(true)
    updateClock()
    m.clockTimer.control = "start"
    m.heartbeatTimer.control = "start"

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

' Resets Roku's idle/screensaver countdown by sending a harmless local ECP
' keypress, the same way a real remote press would. "Up" is used because
' nothing in this app (or AppScene) handles it -- it's a true no-op here,
' unlike "options" (reconfigure) or "rewind" (AppScene's easter egg). Fired
' fire-and-forget: the request is stashed on m. so it isn't garbage collected
' mid-flight, but the response is never read -- we don't care if it succeeds.
sub onHeartbeat()
    m.heartbeatRequest = CreateObject("roUrlTransfer")
    m.heartbeatRequest.SetUrl("http://localhost:8060/keypress/Up")
    m.heartbeatPort = CreateObject("roMessagePort")
    m.heartbeatRequest.SetPort(m.heartbeatPort)
    m.heartbeatRequest.AsyncPostFromString("")
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

' Each section's header bar is rendered inline, at its real scrolled position,
' identical in appearance to the fixed stickyHeader overlay above the
' viewport. It scrolls normally with its rows -- the overlay only becomes
' visible once that real header has scrolled up past the viewport's top edge
' (where clippingRect would otherwise just make it vanish), taking over to
' look like it "stuck" there. This is what makes it match the web kiosk's
' CSS position:sticky section headers instead of an instant swap with no
' scroll motion.
sub buildContent(sections as Object)
    m.scrollContent.removeChildren(m.scrollContent.getChildren(-1, 0))
    m.scrollTimer.control = "stop"
    m.pauseTimer.control = "stop"
    m.scrollState = "idle"
    m.sectionBounds = []
    m.currentSectionIdx = -1
    m.stickyHeader.visible = false

    y = 0
    for each section in sections
        if section.jobs <> invalid and section.jobs.Count() > 0 then
            m.sectionBounds.push({ startY: y, section: section })

            headerGroup = buildSectionHeader(section, y)
            m.scrollContent.appendChild(headerGroup)
            y = y + 56

            for each job in section.jobs
                rowGroup = buildJobRow(job, y)
                m.scrollContent.appendChild(rowGroup)
                y = y + 60
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

' Overlay is shown only once the real header for the active section has
' scrolled past the top (scrollY beyond its startY) -- exactly the point
' clippingRect would otherwise make it disappear. At rest, or while that
' header is still naturally within the viewport, the overlay stays hidden
' so the real one is the only copy on screen (avoids a double-header).
sub updateStickyHeader(idx as Integer, scrollY as Float)
    if idx < 0 or idx >= m.sectionBounds.Count() then
        m.stickyHeader.visible = false
        return
    end if

    bounds = m.sectionBounds[idx]
    if scrollY <= bounds.startY then
        m.stickyHeader.visible = false
        return
    end if

    m.stickyHeader.visible = true
    if idx = m.currentSectionIdx then return
    m.currentSectionIdx = idx

    section = bounds.section
    colors = colorsForDept(section.department)
    m.stickyHeaderBg.color = colors.bg
    m.stickyAccent.color = colors.accent
    m.stickyWcLabel.text = section.wc
    m.stickyDeptLabel.text = section.department + "   -   " + section.wc_group
end sub

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
    bg.height = 60
    bg.color = "0x0A0A14FF"
    group.appendChild(bg)

    addCell(group, colByKey("job"),         job.job,         "0x4AAFFFFF", "font:MediumBoldSystemFont")
    addCell(group, colByKey("customer"),    job.customer,    "0xCCCCCCFF", "font:MediumSystemFont")
    addCell(group, colByKey("description"), job.description, "0x999999FF", "font:MediumSystemFont")
    addCell(group, colByKey("oper"),        job.oper,        "0xCCCCCCFF", "font:MediumSystemFont")
    addCell(group, colByKey("currwc"),      job.curr_wc,     "0xFFFFFFFF", "font:MediumBoldSystemFont")

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
    label.translation = [col.x, 16]
    label.width = col.w
    label.font = font
    label.color = color
    parent.appendChild(label)
end sub

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
        applyScroll()
        m.scrollState = "pausedAtBottom"
        m.scrollTimer.control = "stop"
        m.pauseTimer.duration = 3
        m.pauseTimer.control = "start"
    else
        applyScroll()
    end if
end sub

sub applyScroll()
    m.scrollContent.translation = [0, -m.scrollY]

    ' Find which section the viewport's top edge currently sits within, and
    ' swap the sticky header the moment that section starts, same as the web
    ' kiosk's CSS position:sticky section headers.
    idx = 0
    for i = 0 to m.sectionBounds.Count() - 1
        if m.sectionBounds[i].startY <= m.scrollY then
            idx = i
        else
            exit for
        end if
    end for
    updateStickyHeader(idx, m.scrollY)
end sub

sub onPauseTimerFire()
    if m.scrollState = "pausedAtBottom" then
        m.scrollY = 0
        applyScroll()
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
