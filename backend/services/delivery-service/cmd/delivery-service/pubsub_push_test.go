package main

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func pubsubOrderBody(payload any) *bytes.Reader {
	raw, _ := json.Marshal(payload)
	env := pubsubPushEnvelope{}
	env.Message.Data = base64.StdEncoding.EncodeToString(raw)
	body, _ := json.Marshal(env)
	return bytes.NewReader(body)
}

func TestDecodePubSubPushJSON(t *testing.T) {
	var order orderRecord
	reason, err := decodePubSubPushJSON(pubsubOrderBody(orderRecord{ID: "order-1"}), &order)
	if err != nil {
		t.Fatalf("expected valid payload, got reason=%s err=%v", reason, err)
	}
	if order.ID != "order-1" {
		t.Fatalf("unexpected order id: %q", order.ID)
	}
}

func TestDecodePubSubPushJSONRejectsMalformedInputs(t *testing.T) {
	tests := []struct {
		name   string
		body   string
		reason string
	}{
		{name: "invalid envelope", body: "{", reason: pubsubDecodeInvalidEnvelope},
		{name: "missing data", body: `{"message":{}}`, reason: pubsubDecodeMissingData},
		{name: "invalid base64", body: `{"message":{"data":"not base64"}}`, reason: pubsubDecodeInvalidBase64},
		{
			name:   "invalid payload",
			body:   `{"message":{"data":"` + base64.StdEncoding.EncodeToString([]byte("{")) + `"}}`,
			reason: pubsubDecodeInvalidPayload,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			var order orderRecord
			reason, err := decodePubSubPushJSON(strings.NewReader(tc.body), &order)
			if err == nil {
				t.Fatalf("expected error")
			}
			if reason != tc.reason {
				t.Fatalf("expected reason %q, got %q", tc.reason, reason)
			}
		})
	}
}

func TestHandleOrdersEventsAcknowledgesMalformedPubSubMessages(t *testing.T) {
	req := httptest.NewRequest(http.MethodPost, "/events/orders", strings.NewReader(`{"message":{}}`))
	rec := httptest.NewRecorder()

	handleOrdersEvents(rec, req, nil, &serviceConfig{}, nil, nil, nil)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected status 200, got %d body=%s", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), pubsubDecodeMissingData) {
		t.Fatalf("expected response reason %q, got %s", pubsubDecodeMissingData, rec.Body.String())
	}
}
