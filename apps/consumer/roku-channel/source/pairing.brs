function BuildPollUrl(pairingUrl as string) as string
    ' Expect pairingUrl like https://.../tv/pair
    ' Polls /tv/pair/state for linked session.
    return pairingUrl + "/state"
end function

function PollPairingState(pollUrl as string) as object
    transfer = CreateObject("roUrlTransfer")
    transfer.SetUrl(pollUrl)
    transfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
    transfer.InitClientCertificates()
    response = transfer.GetToString()
    if response = invalid then return invalid
    return ParseJson(response)
end function
