package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
)

var (
	errOrderContactUpdateUnavailable = errors.New("order_service_not_configured")
	errOrderContactUpdateNotFound    = errors.New("order_not_found")
	errOrderContactUpdateConflict    = errors.New("order_contact_conflict")
)

type orderChannelContactUpdateRequest struct {
	Channel     string `json:"channel"`
	AccountID   string `json:"accountId,omitempty"`
	UserID      string `json:"userId"`
	ThreadID    string `json:"threadId,omitempty"`
	DisplayName string `json:"displayName,omitempty"`
	Locale      string `json:"locale,omitempty"`
}

func updateOrderChannelContact(
	ctx context.Context,
	cfg *serviceConfig,
	orderHTTPClient *http.Client,
	orderID string,
	contact channelContact,
) error {
	if strings.TrimSpace(cfg.OrderServiceURL) == "" {
		return errOrderContactUpdateUnavailable
	}
	payload := orderChannelContactUpdateRequest{
		Channel:     strings.TrimSpace(contact.Channel),
		AccountID:   strings.TrimSpace(contact.AccountID),
		UserID:      strings.TrimSpace(contact.UserID),
		ThreadID:    strings.TrimSpace(contact.ThreadID),
		DisplayName: strings.TrimSpace(contact.DisplayName),
		Locale:      strings.TrimSpace(contact.Locale),
	}
	body, _ := json.Marshal(payload)
	endpoint := serviceURL(cfg.OrderServiceURL, "orders", orderID, "channel-contact")
	req, _ := http.NewRequestWithContext(ctx, http.MethodPatch, endpoint, bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err := orderHTTPClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 200 && resp.StatusCode < 300 {
		return nil
	}
	_, _ = io.ReadAll(resp.Body)
	if resp.StatusCode == http.StatusNotFound {
		return errOrderContactUpdateNotFound
	}
	if resp.StatusCode == http.StatusConflict {
		return errOrderContactUpdateConflict
	}
	return fmt.Errorf("order_contact_update_failed status=%d", resp.StatusCode)
}
