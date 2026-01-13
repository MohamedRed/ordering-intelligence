import "pkg:/source/api.brs"

sub init()
    m.top.backgroundUri = "pkg:/images/bg_placeholder.png"

    if m.top.pairingUrl <> invalid then
        qr = m.top.findNode("qr")
        qr.uri = Substitute("https://api.qrserver.com/v1/create-qr-code/?size=260x260&data={0}", UrlEncode(m.top.pairingUrl))
    end if

    ' Populate placeholder; attempt live fetch if session token exists.
    setMockReorders()
    attemptLoadReorders()
end sub

function UrlEncode(str as string) as string
    return CreateObject("roUrlTransfer").Escape(str)
end function

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
    baseUrl = "https://dev-channel-gateway.liive.dev"
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
