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

func decodePubSubPushJSON(body io.Reader, target any) (string, error) {
	var env pubsubPushEnvelope
	if err := json.NewDecoder(body).Decode(&env); err != nil {
		return pubsubDecodeInvalidEnvelope, err
	}

	data := strings.TrimSpace(env.Message.Data)
	if data == "" {
		return pubsubDecodeMissingData, errors.New("pubsub message data is empty")
	}

	raw, err := base64.StdEncoding.DecodeString(data)
	if err != nil {
		return pubsubDecodeInvalidBase64, err
	}

	if err := json.Unmarshal(raw, target); err != nil {
		return pubsubDecodeInvalidPayload, fmt.Errorf("decode pubsub payload: %w", err)
	}
	return "", nil
}
