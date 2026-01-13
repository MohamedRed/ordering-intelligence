package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"

	cloudfirestore "cloud.google.com/go/firestore"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

var errWebAppSessionNotFound = errors.New("session_not_found")

func loadWebAppSession(ctx context.Context, client *cloudfirestore.Client, sessionID string) (channelSession, error) {
	snap, err := client.Collection(channelSessionsCollection).Doc(sessionID).Get(ctx)
	if err != nil {
		if status.Code(err) == codes.NotFound {
			return channelSession{}, errWebAppSessionNotFound
		}
		return channelSession{}, err
	}
	var session channelSession
	if err := snap.DataTo(&session); err != nil {
		return channelSession{}, err
	}
	return session, nil
}

func loadWebAppSessionWithCustomer(
	ctx context.Context,
	cfg *serviceConfig,
	client *cloudfirestore.Client,
	sessionID string,
) (channelSession, error) {
	session, err := loadSessionWithCustomer(ctx, cfg, client, sessionID)
	if err != nil {
		if status.Code(err) == codes.NotFound {
			return channelSession{}, errWebAppSessionNotFound
		}
		return channelSession{}, err
	}
	return session, nil
}

func buildWebAppContact(session channelSession) channelContact {
	return channelContact{
		Channel:     webAppContactChannel(session.Channel),
		AccountID:   session.AccountID,
		UserID:      session.UserID,
		DisplayName: session.DisplayName,
	}
}

func proxyJSON(
	ctx context.Context,
	client *http.Client,
	method string,
	url string,
	payload any,
	w http.ResponseWriter,
) error {
	var body io.Reader
	if payload != nil {
		raw, _ := json.Marshal(payload)
		body = bytes.NewReader(raw)
	}
	req, _ := http.NewRequestWithContext(ctx, method, url, body)
	req.Header.Set("Content-Type", "application/json")
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(resp.StatusCode)
	_, _ = io.Copy(w, resp.Body)
	return nil
}
