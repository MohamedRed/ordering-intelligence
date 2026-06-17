package main

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"testing"
	"time"
)

func signedMobileSessionParts(secret, sessionID string, now time.Time) (string, string) {
	timestamp := now.UTC().Format(time.RFC3339)
	base := "session:" + sessionID + ":" + strconv.FormatInt(now.UTC().Unix(), 10)
	mac := hmac.New(sha256.New, []byte(secret))
	_, _ = mac.Write([]byte(base))
	return hex.EncodeToString(mac.Sum(nil)), timestamp
}

func TestVerifyMobileSessionRequestAuthRequiresSignatureWhenConfigured(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/mobile/session?sessionId=session-1", nil)
	rec := httptest.NewRecorder()

	ok := verifyMobileSessionRequestAuth(
		&serviceConfig{MobileSessionSecret: "secret", MobileSessionSkewSeconds: 300},
		rec,
		req,
		"session-1",
		"",
		"",
	)

	if ok {
		t.Fatal("expected missing auth to fail")
	}
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d body=%s", rec.Code, rec.Body.String())
	}
}

func TestVerifyMobileSessionRequestAuthAcceptsValidSignature(t *testing.T) {
	now := time.Now().UTC()
	signature, timestamp := signedMobileSessionParts("secret", "session-1", now)
	req := httptest.NewRequest(http.MethodGet, "/mobile/session?sessionId=session-1", nil)
	rec := httptest.NewRecorder()

	ok := verifyMobileSessionRequestAuth(
		&serviceConfig{MobileSessionSecret: "secret", MobileSessionSkewSeconds: 300},
		rec,
		req,
		"session-1",
		signature,
		timestamp,
	)

	if !ok {
		t.Fatalf("expected valid auth to pass, got status=%d body=%s", rec.Code, rec.Body.String())
	}
}

func TestHandleMobilePaymentSetupIntentRequiresSessionAuth(t *testing.T) {
	req := httptest.NewRequest(
		http.MethodPost,
		"/mobile/payment-methods/setup-intent",
		strings.NewReader(`{"sessionId":"session-1"}`),
	)
	rec := httptest.NewRecorder()

	handleMobilePaymentSetupIntent(
		rec,
		req,
		&serviceConfig{
			PaymentsServiceURL:       "https://payments.example",
			MobileSessionSecret:      "secret",
			MobileSessionSkewSeconds: 300,
		},
		nil,
		http.DefaultClient,
	)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d body=%s", rec.Code, rec.Body.String())
	}
}
