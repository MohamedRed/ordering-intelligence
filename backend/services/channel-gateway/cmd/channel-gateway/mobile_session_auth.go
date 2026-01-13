package main

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time"
)

var (
	errMobileAuthMissing      = errors.New("mobile_auth_missing")
	errMobileAuthInvalid      = errors.New("mobile_auth_invalid")
	errMobileAuthExpired      = errors.New("mobile_auth_expired")
	errMobileAuthNotSupported = errors.New("mobile_auth_not_supported")
)

type mobileAuthContext struct {
	signature string
	timestamp time.Time
}

func extractMobileAuth(r *http.Request, payload mobileSessionStartRequest) (mobileAuthContext, error) {
	signature := strings.TrimSpace(payload.Signature)
	if signature == "" {
		signature = strings.TrimSpace(r.Header.Get("X-Mobile-Auth-Signature"))
	}
	timestampRaw := strings.TrimSpace(payload.Timestamp)
	if timestampRaw == "" {
		timestampRaw = strings.TrimSpace(r.Header.Get("X-Mobile-Auth-Timestamp"))
	}
	return extractMobileAuthParts(signature, timestampRaw)
}

func extractMobileAuthParts(signature, timestampRaw string) (mobileAuthContext, error) {
	if signature == "" || timestampRaw == "" {
		return mobileAuthContext{}, errMobileAuthMissing
	}
	timestamp, err := parseMobileTimestamp(timestampRaw)
	if err != nil {
		return mobileAuthContext{}, errMobileAuthInvalid
	}
	return mobileAuthContext{signature: signature, timestamp: timestamp}, nil
}

func parseMobileTimestamp(raw string) (time.Time, error) {
	if raw == "" {
		return time.Time{}, errMobileAuthInvalid
	}
	if unix, err := strconv.ParseInt(raw, 10, 64); err == nil {
		return time.Unix(unix, 0).UTC(), nil
	}
	t, err := time.Parse(time.RFC3339, raw)
	if err != nil {
		return time.Time{}, err
	}
	return t.UTC(), nil
}

func verifyMobileSessionAuth(cfg *serviceConfig, provider, subject string, auth mobileAuthContext) error {
	secret := strings.TrimSpace(cfg.MobileSessionSecret)
	if secret == "" {
		if strings.ToLower(strings.TrimSpace(cfg.Environment)) == "production" {
			return errMobileAuthNotSupported
		}
		return nil
	}
	maxSkew := time.Duration(cfg.MobileSessionSkewSeconds) * time.Second
	now := time.Now().UTC()
	if auth.timestamp.IsZero() || now.Sub(auth.timestamp) > maxSkew || auth.timestamp.Sub(now) > maxSkew {
		return errMobileAuthExpired
	}
	base := strings.Join([]string{provider, subject, strconv.FormatInt(auth.timestamp.Unix(), 10)}, ":")
	mac := hmac.New(sha256.New, []byte(secret))
	_, _ = mac.Write([]byte(base))
	expected := hex.EncodeToString(mac.Sum(nil))
	if !hmac.Equal([]byte(expected), []byte(auth.signature)) {
		return errMobileAuthInvalid
	}
	return nil
}

func verifyMobileSessionIDAuth(cfg *serviceConfig, sessionID string, auth mobileAuthContext) error {
	secret := strings.TrimSpace(cfg.MobileSessionSecret)
	if secret == "" {
		if strings.ToLower(strings.TrimSpace(cfg.Environment)) == "production" {
			return errMobileAuthNotSupported
		}
		return nil
	}
	maxSkew := time.Duration(cfg.MobileSessionSkewSeconds) * time.Second
	now := time.Now().UTC()
	if auth.timestamp.IsZero() || now.Sub(auth.timestamp) > maxSkew || auth.timestamp.Sub(now) > maxSkew {
		return errMobileAuthExpired
	}
	base := strings.Join([]string{"session", sessionID, strconv.FormatInt(auth.timestamp.Unix(), 10)}, ":")
	mac := hmac.New(sha256.New, []byte(secret))
	_, _ = mac.Write([]byte(base))
	expected := hex.EncodeToString(mac.Sum(nil))
	if !hmac.Equal([]byte(expected), []byte(auth.signature)) {
		return errMobileAuthInvalid
	}
	return nil
}
