sub init()
    m.top.functionName = "runLoop"
end sub

' Runs forever on this Task's own thread once started (control="RUN").
' Fires a harmless local ECP keypress every 90s to reset Roku's idle/
' screensaver countdown, the same way a real remote press would. "Left" is
' used because nothing in ScheduleScreen/AppScene handles it -- a true
' no-op, unlike "up"/"down" (manual scroll), "options" (reconfigure), or
' "rewind" (AppScene's easter egg).
sub runLoop()
    port = CreateObject("roMessagePort")
    while true
        try
            request = CreateObject("roUrlTransfer")
            request.SetUrl("http://localhost:8060/keypress/Left")
            request.SetPort(port)
            request.AsyncPostFromString("")
            ' Not reading the response -- we don't care if it succeeds, this
            ' is purely to reset the idle timer. wait() here just re-uses the
            ' same port as a 90s sleep between beats.
        catch e
            print "HeartbeatTask error: "; e.getMessage()
        end try
        wait(90000, port)
    end while
end sub
