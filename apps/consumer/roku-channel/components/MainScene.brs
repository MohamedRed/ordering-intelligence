import "pkg:/source/api.brs"

sub init()
    m.top.backgroundUri = "pkg:/images/bg_placeholder.png"
    m.top.observeField("pairingUrl", "refreshPairingUi")
    m.top.observeField("pairingCode", "refreshPairingUi")
    m.top.observeField("baseUrl", "setupPairingTask")
    m.top.observeField("pairingId", "setupPairingTask")
    m.top.observeField("pollIntervalSeconds", "setupPairingTask")

    refreshPairingUi()
    setMockReorders()
    attemptLoadReorders()
    setupPairingTask()
end sub

sub refreshPairingUi()
    pairingUrl = m.top.pairingUrl
    if pairingUrl <> invalid and pairingUrl <> "" then
        qr = m.top.findNode("qr")
        qr.uri = Substitute("https://api.qrserver.com/v1/create-qr-code/?size=260x260&data={0}", UrlEncode(pairingUrl))
    else
        subtitle = m.top.findNode("subtitle")
        if subtitle <> invalid then subtitle.text = "Connect to the internet to get a pairing code."
    end if

    codeLabel = m.top.findNode("pairingCode")
    if codeLabel <> invalid then
        if m.top.pairingCode <> invalid and m.top.pairingCode <> "" then
            codeLabel.text = m.top.pairingCode
        else
            codeLabel.text = "------"
        end if
    end if
end sub

sub setMockReorders()
    row = m.top.findNode("reorders")
    if row = invalid then return

    content = CreateObject("roSGNode", "ContentNode")
    content.AppendChild(BuildCard("Last order: Tacos", "Ready in ~10 mins"))
    content.AppendChild(BuildCard("Reorder: Pizza Margherita", "Medium, thin crust"))
    content.AppendChild(BuildCard("Reorder: Fuel - €50", "Shell - Station #1042"))
    row.content = content
end sub

function BuildCard(title as string, subtitle as string) as object
    item = CreateObject("roSGNode", "ContentNode")
    item.SetFields({
        title: title
        description: subtitle
        hdposterurl: "pkg:/images/card_placeholder.png"
    })
    return item
end function

sub attemptLoadReorders()
    baseUrl = ResolveBaseUrl()
    data = FetchReorders(baseUrl)
    if data = invalid or data.items = invalid then return

    row = m.top.findNode("reorders")
    if row = invalid then return

    content = CreateObject("roSGNode", "ContentNode")
    for each item in data.items
        title = item.title
        desc = item.subtitle
        content.AppendChild(BuildCard(title, desc))
    end for
    row.content = content
end sub

sub setupPairingTask()
    if m.top.baseUrl = invalid or m.top.baseUrl = "" then return
    if m.top.pairingId = invalid or m.top.pairingId = "" then return
    if m.pairingTask <> invalid then return

    m.pairingTask = CreateObject("roSGNode", "PairingTask")
    m.pairingTask.baseUrl = m.top.baseUrl
    m.pairingTask.pairingId = m.top.pairingId
    m.pairingTask.pollIntervalSeconds = m.top.pollIntervalSeconds
    m.pairingTask.observeField("sessionToken", "onSessionToken")
    m.pairingTask.control = "run"
end sub

sub onSessionToken()
    attemptLoadReorders()
end sub

function ResolveBaseUrl() as string
    if m.top.baseUrl <> invalid and m.top.baseUrl <> "" then return m.top.baseUrl
    return "https://dev-channel-gateway.liive.dev"
end function

function UrlEncode(value as string) as string
    return CreateObject("roUrlTransfer").Escape(value)
end function
