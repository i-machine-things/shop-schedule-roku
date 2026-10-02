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
    m.manualPauseTimer = m.top.findNode("manualPauseTimer")

    m.scheduleTask.observeField("scheduleData", "onScheduleData")
    m.refreshTimer.observeField("fire", "onRefreshTimer")
    m.scrollTimer.observeField("fire", "onScrollTick")
    m.pauseTimer.observeField("fire", "onPauseTimerFire")
    m.clockTimer.observeField("fire", "onClockTick")
    m.manualPauseTimer.observeField("fire", "onManualPauseTimerFire")

    m.viewportHeight = 1080 - 186
    m.contentHeight = 0
    m.scrollY = 0
    m.scrollState = "idle"
    m.SCROLL_SPEED = 1.1
    m.HEADER_HEIGHT = 56
    m.ROW_HEIGHT = 60
    m.sectionBounds = []
    m.currentSectionIdx = -1
    m.stickyHeader.visible = false
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
    try
        requestFetch()
    catch e
        print "onRefreshTimer error: "; e.getMessage()
    end try
end sub

sub onClockTick()
    updateClock()
end sub

' This is the single best "is the render thread still alive" signal on
' screen -- it ticks every second independent of scrolling. If it's frozen
' too, the whole thread is dead, not just the scroll state machine.
sub updateClock()
    try
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
    catch e
        print "updateClock error: "; e.getMessage()
    end try
end sub

function leftPad(s as String, width as Integer) as String
    result = s
    while result.Len() < width
        result = "0" + result
    end while
    return result
end function

sub onScheduleData()
    try
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
    catch e
        print "onScheduleData error: "; e.getMessage()
    end try
end sub

' Each section's header bar is rendered inline, at its real scrolled position.
' The real content with real-world data runs to hundreds of jobs -- a full
' scroll-through at this speed takes several minutes, far longer than the
' 60s refresh interval. Resetting scrollY to 0 on every refresh (the first
' version) meant the display could never get more than a minute into the
' list before being yanked back to the top -- confirmed on real hardware as
' "restarts instead of showing the whole list." Fix: preserve scroll
' position across a refresh; only reset to 0 on the very first load.
sub buildContent(sections as Object)
    ' Guards the kiosk against ever freezing on an unexpected data shape --
    ' a crash here previously took the whole render thread down with it,
    ' leaving the last frame stuck on screen with no timers left running.
    ' See CODING_NOTES.md "Resilience" for the incident this came from.
    try
        previousScrollY = m.scrollY
        wasManuallyPaused = (m.scrollState = "manualPaused")

        m.scrollContent.removeChildren(m.scrollContent.getChildren(-1, 0))
        m.scrollTimer.control = "stop"
        m.pauseTimer.control = "stop"
        m.scrollState = "idle"
        m.sectionBounds = []
        m.currentSectionIdx = -1

        y = 0
        for each section in sections
            if section.jobs <> invalid and section.jobs.Count() > 0 then
                m.sectionBounds.push({ startY: y, section: section })

                headerGroup = buildSectionHeader(section, y)
                m.scrollContent.appendChild(headerGroup)
                y = y + m.HEADER_HEIGHT

                for each job in section.jobs
                    rowGroup = buildJobRow(job, y)
                    m.scrollContent.appendChild(rowGroup)
                    y = y + m.ROW_HEIGHT
                end for
            end if
        end for

        m.contentHeight = y
        maxScroll = m.contentHeight - m.viewportHeight

        if maxScroll > 0 then
            m.scrollY = previousScrollY
            if m.scrollY > maxScroll then m.scrollY = maxScroll
            if m.scrollY < 0 then m.scrollY = 0
            applyScroll()
            if wasManuallyPaused then
                m.scrollState = "manualPaused"
                m.manualPauseTimer.control = "start"
            else
                m.scrollState = "scrolling"
                m.scrollTimer.control = "start"
            end if
        else
            m.scrollY = 0
            m.scrollContent.translation = [0, 0]
            updateStickyHeader(0)
        end if
    catch e
        print "buildContent error: "; e.getMessage()
        m.errorLabel.text = "Display error building schedule -- will retry next refresh."
        m.errorBanner.visible = true
    end try
end sub

function buildSectionHeader(section as Object, y as Integer) as Object
    colors = colorsForDept(section.department)

    group = CreateObject("roSGNode", "Group")
    group.translation = [0, y]

    bg = CreateObject("roSGNode", "Rectangle")
    bg.width = 1920
    bg.height = m.HEADER_HEIGHT
    bg.color = colors.bg
    group.appendChild(bg)

    accentBar = CreateObject("roSGNode", "Rectangle")
    accentBar.width = 6
    accentBar.height = m.HEADER_HEIGHT
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

' Always visible once there's at least one section -- deliberately simple.
' Two earlier versions tried to time the overlay's visibility against exactly
' when the real inline header should be clipped away (hidden until scrollY
' passed startY, then hidden until startY+HEADER_HEIGHT) and each attempt
' produced a real, hardware-confirmed bug: a doubled/overlapping header, then
' a "blacks out" gap during the handoff. Always-on, idx-driven only, costs a
' brief harmless moment of the overlay and the real header both showing the
' *same* matching text during each transition -- far less objectionable than
' either previous failure mode, and there's no timing window left to get
' wrong. See CODING_NOTES.md "Sticky header v2".
sub updateStickyHeader(idx as Integer)
    if idx < 0 or idx >= m.sectionBounds.Count() then return
    if idx = m.currentSectionIdx then return
    m.currentSectionIdx = idx

    section = m.sectionBounds[idx].section
    colors = colorsForDept(section.department)
    m.stickyHeader.visible = true
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
    bg.height = m.ROW_HEIGHT
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
' This fires ~33x/second for as long as the kiosk is scrolling -- any
' uncaught error here previously killed the whole render thread (nothing
' left to fire the clock, refresh timer, or anything else), leaving the
' last frame frozen on screen permanently. On error: stop the scroll timer
' (so it doesn't re-throw every tick) and let the next successful refresh's
' buildContent() restart scrolling cleanly, rather than crash the channel.
sub onScrollTick()
    try
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
    catch e
        print "onScrollTick error: "; e.getMessage()
        m.scrollTimer.control = "stop"
        m.scrollState = "idle"
    end try
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
    updateStickyHeader(idx)
end sub

sub onPauseTimerFire()
    try
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
    catch e
        print "onPauseTimerFire error: "; e.getMessage()
        m.scrollState = "idle"
    end try
end sub

' Press "options" (the asterisk/star key) to reset the configured server and
' return to setup. Deliberately not a commonly-pressed key -- this runs
' unattended on a shop floor TV and shouldn't be easy to trigger by accident.
' Up/Down scroll manually; auto-scroll pauses while in manual control and
' resumes a few seconds after the last press, same idea as the web kiosk
' pausing on wheel/touch input.
function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then return false

    if key = "options" then
        m.top.reconfigure = true
        return true
    else if key = "up" then
        manualScroll(-200)
        return true
    else if key = "down" then
        manualScroll(200)
        return true
    end if
    return false
end function

sub manualScroll(delta as Integer)
    try
        maxScroll = m.contentHeight - m.viewportHeight
        if maxScroll <= 0 then return

        m.scrollTimer.control = "stop"
        m.pauseTimer.control = "stop"
        m.scrollState = "manualPaused"

        m.scrollY = m.scrollY + delta
        if m.scrollY < 0 then m.scrollY = 0
        if m.scrollY > maxScroll then m.scrollY = maxScroll
        applyScroll()

        m.manualPauseTimer.control = "stop"
        m.manualPauseTimer.control = "start"
    catch e
        print "manualScroll error: "; e.getMessage()
        m.scrollState = "idle"
    end try
end sub

sub onManualPauseTimerFire()
    try
        if m.scrollState <> "manualPaused" then return
        m.scrollState = "scrolling"
        m.scrollTimer.control = "start"
    catch e
        print "onManualPauseTimerFire error: "; e.getMessage()
        m.scrollState = "idle"
    end try
end sub
