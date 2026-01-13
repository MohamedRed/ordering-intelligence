package main

const (
	discordInteractionPing             = 1
	discordInteractionCommand          = 2
	discordInteractionMessageComponent = 3

	discordResponsePong    = 1
	discordResponseMessage = 4

	discordComponentActionRow = 1
	discordComponentButton    = 2
	discordButtonStylePrimary = 1
	discordButtonStyleLink    = 5

	discordEphemeralFlag = 1 << 6
)

type discordInteraction struct {
	Type   int                       `json:"type"`
	Data   *discordInteractionData   `json:"data,omitempty"`
	Member *discordInteractionMember `json:"member,omitempty"`
	User   *discordUser              `json:"user,omitempty"`
}

type discordInteractionData struct {
	Name     string                     `json:"name,omitempty"`
	CustomID string                     `json:"custom_id,omitempty"`
	Options  []discordInteractionOption `json:"options,omitempty"`
}

type discordInteractionOption struct {
	Name    string                     `json:"name,omitempty"`
	Value   any                        `json:"value,omitempty"`
	Options []discordInteractionOption `json:"options,omitempty"`
}

type discordInteractionMember struct {
	User *discordUser `json:"user,omitempty"`
}

type discordUser struct {
	ID         string `json:"id,omitempty"`
	Username   string `json:"username,omitempty"`
	GlobalName string `json:"global_name,omitempty"`
}

type discordInteractionResponse struct {
	Type int                             `json:"type"`
	Data *discordInteractionResponseData `json:"data,omitempty"`
}

type discordInteractionResponseData struct {
	Content    string             `json:"content,omitempty"`
	Flags      int                `json:"flags,omitempty"`
	Components []discordComponent `json:"components,omitempty"`
}

type discordComponent struct {
	Type       int                `json:"type"`
	Components []discordComponent `json:"components,omitempty"`
	Label      string             `json:"label,omitempty"`
	Style      int                `json:"style,omitempty"`
	CustomID   string             `json:"custom_id,omitempty"`
	URL        string             `json:"url,omitempty"`
}
