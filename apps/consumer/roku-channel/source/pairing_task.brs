import "pkg:/source/pairing.brs"

sub init()
    m.top.functionName = "runTask"
end sub

sub runTask()
    if m.top.baseUrl = invalid or m.top.baseUrl = "" then return
    if m.top.pairingId = invalid or m.top.pairingId = "" then return

    interval = m.top.pollIntervalSeconds
    if interval = invalid or interval <= 0 then interval = 2

    maxTries = 120 ' ~4 minutes at 2s interval
    for i = 1 to maxTries
        state = PollPairingState(m.top.baseUrl, m.top.pairingId)
        if state <> invalid and state.linked = true then
            token = invalid
            if state.sessionToken <> invalid then token = state.sessionToken
            if token = invalid and state.session <> invalid then token = state.session
            if token <> invalid then
                registry = CreateObject("roRegistrySection", "ordering-intel")
                registry.Write("session_token", token)
                registry.Flush()
                m.top.sessionToken = token
            end if
            exit for
        end if
        sleep(interval * 1000)
    end for
end sub
