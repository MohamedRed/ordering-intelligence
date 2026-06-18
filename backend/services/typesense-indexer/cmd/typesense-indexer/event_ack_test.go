package main

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestHandleEventAcknowledgesMalformedNonRetryableEvents(t *testing.T) {
	srv := &service{cfg: typesenseConfig{Host: "http://127.0.0.1:1", APIKey: "test-key", Collection: "stores"}}

	cases := []struct {
		name       string
		body       string
		wantStatus int
		wantBody   string
	}{
		{
			name:       "invalid cloud event JSON",
			body:       "{",
			wantStatus: http.StatusOK,
			wantBody:   "invalid_event",
		},
		{
			name:       "invalid firestore payload",
			body:       `{"type":"google.cloud.firestore.document.v1.created","subject":"documents/stores/store-1","data":"not-firestore"}`,
			wantStatus: http.StatusOK,
			wantBody:   "invalid_firestore_event",
		},
		{
			name:       "missing firestore document path",
			body:       `{"type":"google.cloud.firestore.document.v1.created","data":{"value":{"fields":{}}}}`,
			wantStatus: http.StatusNoContent,
			wantBody:   "",
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodPost, "/", strings.NewReader(tc.body))
			rec := httptest.NewRecorder()

			srv.handleEvent(rec, req)

			if rec.Code != tc.wantStatus {
				t.Fatalf("expected status %d, got %d body=%s", tc.wantStatus, rec.Code, rec.Body.String())
			}
			if tc.wantBody != "" && !strings.Contains(rec.Body.String(), tc.wantBody) {
				t.Fatalf("expected response to contain %q, got %s", tc.wantBody, rec.Body.String())
			}
		})
	}
}

func TestHandleEventKeepsTypesenseFailuresRetryableForProcessableEvents(t *testing.T) {
	srv := &service{cfg: typesenseConfig{Host: "http://127.0.0.1:1", APIKey: "test-key", Collection: "stores"}}
	body := `{"type":"google.cloud.firestore.document.v1.created","subject":"documents/stores/store-1","data":{"value":{"name":"projects/test/databases/(default)/documents/stores/store-1","fields":{}}}}`
	req := httptest.NewRequest(http.MethodPost, "/", strings.NewReader(body))
	rec := httptest.NewRecorder()

	srv.handleEvent(rec, req)

	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("expected retryable status %d, got %d body=%s", http.StatusInternalServerError, rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), "typesense_collection_unavailable") {
		t.Fatalf("expected typesense failure response, got %s", rec.Body.String())
	}
}
