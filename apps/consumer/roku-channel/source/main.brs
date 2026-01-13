sub Main()
    screen = CreateObject("roSGScreen")
    port = CreateObject("roMessagePort")
    screen.SetMessagePort(port)

    scene = screen.CreateScene("MainScene")
    screen.Show()

    pairingUrl = GetPairingUrl()
    scene.pairingUrl = pairingUrl

    ' Kick off lightweight pairing poll in background.
    StartPairingPoll(pairingUrl)

    while true
        msg = wait(0, port)
        if type(msg) = "roSGScreenEvent" and msg.isScreenClosed()
            exit while
        end if
    end while
end sub

function GetPairingUrl() as string
    registry = CreateObject("roRegistrySection", "ordering-intel")
    url = registry.Read("pairing_url", invalid)
    if url <> invalid then return url
    ' Fallback dev endpoint; replace at build time.
    return "https://dev-channel-gateway.liive.dev/tv/pair"
end function

sub StartPairingPoll(pairingUrl as string)
    task = CreateObject("roSGNode", "PairingTask")
    task.control = "run"
    task.pairingUrl = pairingUrl
end sub
