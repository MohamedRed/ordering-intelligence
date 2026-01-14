package main

import (
	"context"
	"encoding/json"
	"strings"
	"time"

	"github.com/gorilla/websocket"
)

type clientToolCall struct {
	ToolName   string
	ToolCallID string
	Parameters map[string]any
}

type agentReply struct {
	Text     string
	ToolCall *clientToolCall
}

func readAgentReply(ctx context.Context, conn *websocket.Conn, allowToolCalls bool) (agentReply, string, error) {
	deadline := time.Now().Add(18 * time.Second)
	var conversationID string
	for {
		if err := conn.SetReadDeadline(deadline); err != nil {
			return agentReply{}, conversationID, err
		}
		_, data, err := conn.ReadMessage()
		if err != nil {
			return agentReply{}, conversationID, err
		}
		msg, ok := parseAgentEvent(data)
		if !ok {
			continue
		}
		switch msg.Type {
		case "ping":
			if msg.EventID != "" {
				_ = conn.WriteJSON(map[string]any{"type": "pong", "event_id": msg.EventID})
			}
		case "conversation_initiation_metadata":
			if msg.ConversationID != "" {
				conversationID = msg.ConversationID
			}
		case "client_tool_call":
			if allowToolCalls && msg.ToolCall != nil {
				return agentReply{ToolCall: msg.ToolCall}, conversationID, nil
			}
		case "agent_response":
			if msg.Text != "" {
				return agentReply{Text: msg.Text}, conversationID, nil
			}
		case "agent_response_correction":
			if msg.Text != "" {
				return agentReply{Text: msg.Text}, conversationID, nil
			}
		}

		select {
		case <-ctx.Done():
			return agentReply{}, conversationID, ctx.Err()
		default:
		}
	}
}

type agentEvent struct {
	Type           string
	Text           string
	EventID        string
	ConversationID string
	ToolCall       *clientToolCall
}

func parseAgentEvent(data []byte) (agentEvent, bool) {
	msg, ok := decodeJSONMap(data)
	if !ok {
		return agentEvent{}, false
	}
	eventType := anyToString(msg["type"])
	if eventType == "" {
		return agentEvent{}, false
	}
	event := agentEvent{Type: eventType}
	switch eventType {
	case "ping":
		event.EventID = getNestedString(msg, "ping_event", "event_id")
	case "conversation_initiation_metadata":
		event.ConversationID = getNestedString(msg, "conversation_initiation_metadata_event", "conversation_id")
	case "agent_response":
		event.Text = stringsTrimSpace(getNestedString(msg, "agent_response_event", "agent_response"))
	case "agent_response_correction":
		event.Text = stringsTrimSpace(getNestedString(msg, "agent_response_correction_event", "agent_response_correction"))
	case "client_tool_call":
		event.ToolCall = parseClientToolCall(msg)
	}
	return event, true
}

func parseClientToolCall(msg map[string]any) *clientToolCall {
	raw, ok := msg["client_tool_call"].(map[string]any)
	if !ok {
		return nil
	}
	name := stringsTrimSpace(raw["tool_name"])
	if name == "" {
		name = stringsTrimSpace(raw["toolName"])
	}
	callID := stringsTrimSpace(raw["tool_call_id"])
	if callID == "" {
		callID = stringsTrimSpace(raw["toolCallId"])
	}
	params := map[string]any{}
	if rawParams, ok := raw["parameters"].(map[string]any); ok {
		params = rawParams
	}
	if name == "" && callID == "" && len(params) == 0 {
		return nil
	}
	return &clientToolCall{
		ToolName:   name,
		ToolCallID: callID,
		Parameters: params,
	}
}

func decodeJSONMap(data []byte) (map[string]any, bool) {
	var msg map[string]any
	if err := json.Unmarshal(data, &msg); err != nil {
		return nil, false
	}
	return msg, true
}

func stringsTrimSpace(value any) string {
	if value == nil {
		return ""
	}
	return strings.TrimSpace(anyToString(value))
}
