package main

import (
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"strings"
)

const (
	pubsubDecodeInvalidEnvelope = "invalid_pubsub_envelope"
	pubsubDecodeMissingData     = "missing_message_data"
	pubsubDecodeInvalidBase64   = "invalid_base64"
	pubsubDecodeInvalidPayload  = "invalid_payload"
)

func decodePubSubPushData(body io.Reader) ([]byte, string, string, error) {
	var env pubsubPushEnvelope
	if err := json.NewDecoder(body).Decode(&env); err != nil {
		return nil, "", pubsubDecodeInvalidEnvelope, err
	}

	data := strings.TrimSpace(env.Message.Data)
	if data == "" {
		return nil, "", pubsubDecodeMissingData, errors.New("pubsub message data is empty")
	}

	raw, err := base64.StdEncoding.DecodeString(data)
	if err != nil {
		return nil, "", pubsubDecodeInvalidBase64, err
	}
	return raw, strings.TrimSpace(env.Message.MessageID), "", nil
}

func decodePubSubPushJSON(body io.Reader, target any) (string, error) {
	raw, _, reason, err := decodePubSubPushData(body)
	if err != nil {
		return reason, err
	}
	if err := json.Unmarshal(raw, target); err != nil {
		return pubsubDecodeInvalidPayload, fmt.Errorf("decode pubsub payload: %w", err)
	}
	return "", nil
}
