sub init()
    m.top.functionName = "fetchSchedule"
end sub

' Polls the JSON export shop-schedule's server.py serves alongside schedule.html
' (same directory, same {report_date, thru_date, sections} shape jobboss_db.py/
' parse_pdf() already produce internally) -- see shop-schedule PR adding it.
sub fetchSchedule()
    url = m.top.serverUrl + "/schedule.json"

    request = CreateObject("roUrlTransfer")
    request.SetUrl(url)
    request.SetCertificatesFile("common:/certs/ca-bundle.crt")
    request.InitClientCertificates()

    port = CreateObject("roMessagePort")
    request.SetPort(port)
    request.RetainBodyOnError(true)
    request.AddHeader("Accept", "application/json")
    request.AsyncGetToString()

    msg = wait(15000, port)
    if type(msg) = "roUrlEvent" then
        code = msg.GetResponseCode()
        body = msg.GetString()
        if code = 200 then
            data = ParseJson(body)
            if data <> invalid and data.sections <> invalid then
                m.top.scheduleData = data
                m.top.errorMessage = ""
            else
                m.top.scheduleData = invalid
                m.top.errorMessage = "Server returned unexpected data."
            end if
        else
            m.top.scheduleData = invalid
            m.top.errorMessage = "Server returned HTTP " + code.ToStr() + "."
        end if
    else
        request.AsyncCancel()
        m.top.scheduleData = invalid
        m.top.errorMessage = "Could not reach server (timed out)."
    end if
end sub
