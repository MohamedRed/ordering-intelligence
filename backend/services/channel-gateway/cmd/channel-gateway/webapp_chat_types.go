package main

type webappChatTurnRequest struct {
	SessionID        string                `json:"sessionId"`
	Text             string                `json:"text"`
	AudioBase64      string                `json:"audioBase64"`
	AudioMime        string                `json:"audioMime"`
	SeededIntro      string                `json:"seededIntro,omitempty"`
	SeededSource     string                `json:"seededSource,omitempty"`
	SeededCategories []string              `json:"seededCategories,omitempty"`
	ToolResult       *webappChatToolResult `json:"toolResult,omitempty"`
}

type webappChatTurnResponse struct {
	Messages  []webappChatMessage  `json:"messages,omitempty"`
	ToolCalls []webappChatToolCall `json:"toolCalls,omitempty"`
}

type webappChatMessage struct {
	Role     string              `json:"role"`
	Text     string              `json:"text,omitempty"`
	Options  []webappChatOption  `json:"options,omitempty"`
	Products []webappChatProduct `json:"products,omitempty"`
}

type webappChatOption struct {
	Label    string `json:"label"`
	Payload  string `json:"payload,omitempty"`
	ToolName string `json:"toolName,omitempty"`
}

type webappChatProduct struct {
	ID          string `json:"id,omitempty"`
	Name        string `json:"name,omitempty"`
	Description string `json:"description,omitempty"`
	PriceLabel  string `json:"priceLabel,omitempty"`
	ImageURL    string `json:"imageUrl,omitempty"`
}

type webappChatToolCall struct {
	ID        string         `json:"id,omitempty"`
	Name      string         `json:"name"`
	Arguments map[string]any `json:"arguments,omitempty"`
}

type webappChatToolResult struct {
	ToolCallID string `json:"toolCallId"`
	Name       string `json:"name,omitempty"`
	Result     any    `json:"result,omitempty"`
	IsError    bool   `json:"isError,omitempty"`
}
