function GetSessionToken() as string
    registry = CreateObject("roRegistrySection", "ordering-intel")
    token = registry.Read("session_token", invalid)
    if token = invalid then return ""
    return token
end function

function FetchJson(url as string, token as string) as object
    transfer = CreateObject("roUrlTransfer")
    transfer.SetUrl(url)
    transfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
    transfer.InitClientCertificates()
    if token <> "" then transfer.AddHeader("Authorization", "Bearer " + token)
    response = transfer.GetToString()
    if response = invalid then return invalid
    return ParseJson(response)
end function

function FetchReorders(baseUrl as string) as object
    token = GetSessionToken()
    if token = "" then return invalid
    url = baseUrl + "/tv/reorders"
    return FetchJson(url, token)
end function
