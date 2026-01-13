function GetBaseUrl() as string
    registry = CreateObject("roRegistrySection", "ordering-intel")
    configured = registry.Read("base_url", invalid)
    if configured <> invalid and configured <> "" then
        return NormalizeBaseUrl(configured)
    end if

    legacy = registry.Read("pairing_url", invalid)
    if legacy <> invalid and legacy <> "" then
        return BaseUrlFromPairingUrl(legacy)
    end if

    return "https://dev-channel-gateway.liive.dev"
end function

function StartTvPairing(baseUrl as string) as object
    if baseUrl = invalid or baseUrl = "" then return invalid
    payload = BuildPairingPayload()
    transfer = CreateObject("roUrlTransfer")
    transfer.SetUrl(NormalizeBaseUrl(baseUrl) + "/tv/pair/start")
    transfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
    transfer.InitClientCertificates()
    transfer.AddHeader("Content-Type", "application/json")
    response = transfer.PostFromString(FormatJson(payload))
    if response = invalid then return invalid
    return ParseJson(response)
end function

function PollPairingState(baseUrl as string, pairingId as string) as object
    if baseUrl = invalid or baseUrl = "" then return invalid
    if pairingId = invalid or pairingId = "" then return invalid
    url = NormalizeBaseUrl(baseUrl) + "/tv/pair/state?pairingId=" + UrlEncode(pairingId)
    transfer = CreateObject("roUrlTransfer")
    transfer.SetUrl(url)
    transfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
    transfer.InitClientCertificates()
    response = transfer.GetToString()
    if response = invalid then return invalid
    return ParseJson(response)
end function

function BuildPairingPayload() as object
    device = CreateObject("roDeviceInfo")
    appInfo = CreateObject("roAppInfo")
    payload = {
        deviceId: device.GetChannelClientId()
        deviceType: "roku"
        deviceName: device.GetModel()
        clientPlatform: "roku"
        clientVersion: appInfo.GetVersion()
        locale: device.GetCountryCode()
    }
    return payload
end function

function NormalizeBaseUrl(url as string) as string
    trimmed = url.Trim()
    if trimmed = "" then return trimmed
    if Right(trimmed, 1) = "/" then return Left(trimmed, Len(trimmed) - 1)
    return trimmed
end function

function BaseUrlFromPairingUrl(url as string) as string
    trimmed = url.Trim()
    if trimmed = "" then return trimmed
    pos = Instr(1, trimmed, "/tv/pair")
    if pos > 0 then
        return NormalizeBaseUrl(Left(trimmed, pos - 1))
    end if
    return NormalizeBaseUrl(trimmed)
end function

function UrlEncode(value as string) as string
    return CreateObject("roUrlTransfer").Escape(value)
end function
