import "pkg:/source/pairing.brs"

sub Main()
    screen = CreateObject("roSGScreen")
    port = CreateObject("roMessagePort")
    screen.SetMessagePort(port)

    scene = screen.CreateScene("MainScene")
    screen.Show()

    baseUrl = GetBaseUrl()
    pairing = StartTvPairing(baseUrl)
    if pairing <> invalid then
        scene.baseUrl = baseUrl
        scene.pairingId = pairing.pairingId
        scene.pairingCode = pairing.code
        scene.pairingUrl = pairing.pairUrl
        scene.pollIntervalSeconds = pairing.pollIntervalSeconds
    else
        scene.baseUrl = baseUrl
    end if

    while true
        msg = wait(0, port)
        if type(msg) = "roSGScreenEvent" and msg.isScreenClosed()
            exit while
        end if
    end while
end sub
