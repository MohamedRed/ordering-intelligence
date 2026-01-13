import "pkg:/source/pairing.brs"

sub init()
    m.top.functionName = "runTask"
end sub

sub runTask()
    if m.top.pairingUrl = invalid or m.top.pairingUrl = "" then return

    pollUrl = BuildPollUrl(m.top.pairingUrl)
    maxTries = 60 ' ~60 polls (approx 1 minute)
    for i = 1 to maxTries
        state = PollPairingState(pollUrl)
        if state <> invalid and state.linked = true then
            ' Write session token to registry; UI scene can pick it up next launch.
            registry = CreateObject("roRegistrySection", "ordering-intel")
            if state.session <> invalid then registry.Write("session_token", state.session)
            registry.Flush()
            exit for
        end if
        sleep(1000)
    end for
end sub
