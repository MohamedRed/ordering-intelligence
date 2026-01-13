package main

import (
	"context"
	"crypto/rand"
	"encoding/base64"
	"fmt"
	"net/url"
	"strings"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
	"google.golang.org/api/iterator"
)

const (
	tvPairingCodeLength   = 6
	tvPairingTTL          = 10 * time.Minute
	tvPairingPollSeconds  = 2
	tvSessionTTL          = 30 * 24 * time.Hour
	tvSessionTokenBytes   = 32
	tvPairingCodeAttempts = 6
)

func normalizeTvDeviceType(value string) string {
	v := strings.ToLower(strings.TrimSpace(value))
	switch v {
	case "androidtv", "android_tv", "android-tv":
		return "android_tv"
	case "firetv", "fire_tv", "fire-tv":
		return "fire_tv"
	case "tvos", "apple_tv", "apple-tv":
		return "tvos"
	default:
		return v
	}
}

func generatePairingCode() (string, error) {
	const digits = "0123456789"
	out := make([]byte, tvPairingCodeLength)
	if _, err := rand.Read(out); err != nil {
		return "", err
	}
	for i, b := range out {
		out[i] = digits[int(b)%len(digits)]
	}
	return string(out), nil
}

func generateSessionToken() (string, error) {
	buf := make([]byte, tvSessionTokenBytes)
	if _, err := rand.Read(buf); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(buf), nil
}

func buildPairingURL(baseURL, pairingID, code string) string {
	base := strings.TrimRight(strings.TrimSpace(baseURL), "/")
	if base == "" {
		return ""
	}
	return fmt.Sprintf("%s/tv/pair?pairingId=%s&code=%s",
		base,
		url.QueryEscape(pairingID),
		url.QueryEscape(code),
	)
}

func createTvPairing(
	ctx context.Context,
	client *cloudfirestore.Client,
	payload tvPairingStartRequest,
	baseURL string,
) (tvPairingRecord, tvPairingStartResponse, error) {
	now := time.Now().UTC()
	code, err := allocatePairingCode(ctx, client)
	if err != nil {
		return tvPairingRecord{}, tvPairingStartResponse{}, err
	}
	doc := client.Collection(tvPairingsCollection).NewDoc()
	record := tvPairingRecord{
		PairingID:      doc.ID,
		Code:           code,
		Status:         tvPairingStatusPending,
		DeviceID:       strings.TrimSpace(payload.DeviceID),
		DeviceType:     normalizeTvDeviceType(payload.DeviceType),
		DeviceName:     strings.TrimSpace(payload.DeviceName),
		ClientVersion:  strings.TrimSpace(payload.ClientVersion),
		ClientPlatform: strings.TrimSpace(payload.ClientPlatform),
		Locale:         strings.TrimSpace(payload.Locale),
		CreatedAt:      now,
		ExpiresAt:      now.Add(tvPairingTTL),
	}
	if _, err := doc.Set(ctx, record); err != nil {
		return tvPairingRecord{}, tvPairingStartResponse{}, err
	}
	return record, tvPairingStartResponse{
		PairingID:           record.PairingID,
		Code:                record.Code,
		PairURL:             buildPairingURL(baseURL, record.PairingID, record.Code),
		ExpiresAt:           record.ExpiresAt.Format(time.RFC3339),
		PollIntervalSeconds: tvPairingPollSeconds,
	}, nil
}

func allocatePairingCode(ctx context.Context, client *cloudfirestore.Client) (string, error) {
	for i := 0; i < tvPairingCodeAttempts; i++ {
		code, err := generatePairingCode()
		if err != nil {
			return "", err
		}
		available, err := pairingCodeAvailable(ctx, client, code)
		if err != nil {
			return "", err
		}
		if available {
			return code, nil
		}
	}
	return generatePairingCode()
}

func pairingCodeAvailable(ctx context.Context, client *cloudfirestore.Client, code string) (bool, error) {
	iter := client.Collection(tvPairingsCollection).
		Where("code", "==", code).
		Where("status", "==", tvPairingStatusPending).
		Limit(1).
		Documents(ctx)
	doc, err := iter.Next()
	if err == iterator.Done {
		return true, nil
	}
	if err != nil {
		return false, err
	}
	var record tvPairingRecord
	if err := doc.DataTo(&record); err != nil {
		return false, nil
	}
	if record.ExpiresAt.Before(time.Now().UTC()) {
		return true, nil
	}
	return false, nil
}

func fetchTvPairingByID(
	ctx context.Context,
	client *cloudfirestore.Client,
	pairingID string,
) (tvPairingRecord, error) {
	doc, err := client.Collection(tvPairingsCollection).Doc(pairingID).Get(ctx)
	if err != nil {
		return tvPairingRecord{}, err
	}
	var record tvPairingRecord
	if err := doc.DataTo(&record); err != nil {
		return tvPairingRecord{}, err
	}
	return record, nil
}

func fetchTvPairingByCode(
	ctx context.Context,
	client *cloudfirestore.Client,
	code string,
) (tvPairingRecord, error) {
	iter := client.Collection(tvPairingsCollection).
		Where("code", "==", code).
		Limit(1).
		Documents(ctx)
	doc, err := iter.Next()
	if err != nil {
		return tvPairingRecord{}, err
	}
	var record tvPairingRecord
	if err := doc.DataTo(&record); err != nil {
		return tvPairingRecord{}, err
	}
	return record, nil
}

func upsertTvPairing(
	ctx context.Context,
	client *cloudfirestore.Client,
	record tvPairingRecord,
) error {
	_, err := client.Collection(tvPairingsCollection).Doc(record.PairingID).Set(ctx, record)
	return err
}

func fetchTvSessionByToken(
	ctx context.Context,
	client *cloudfirestore.Client,
	token string,
) (tvSessionRecord, error) {
	doc, err := client.Collection(tvSessionsCollection).Doc(token).Get(ctx)
	if err != nil {
		return tvSessionRecord{}, err
	}
	var record tvSessionRecord
	if err := doc.DataTo(&record); err != nil {
		return tvSessionRecord{}, err
	}
	return record, nil
}

func upsertTvSession(
	ctx context.Context,
	client *cloudfirestore.Client,
	record tvSessionRecord,
) error {
	_, err := client.Collection(tvSessionsCollection).Doc(record.SessionToken).Set(ctx, record)
	return err
}

func deleteTvSession(
	ctx context.Context,
	client *cloudfirestore.Client,
	token string,
) error {
	_, err := client.Collection(tvSessionsCollection).Doc(token).Delete(ctx)
	return err
}
