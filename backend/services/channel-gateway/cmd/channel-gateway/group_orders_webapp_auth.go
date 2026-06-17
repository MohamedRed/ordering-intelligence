package main

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"strings"
)

var errWebAppGroupOrderForbidden = errors.New("group_order_forbidden")
var errWebAppGroupOrderNotFound = errors.New("group_order_not_found")
var errWebAppGroupOrderLookupFailed = errors.New("group_order_lookup_failed")

var fetchWebAppGroupOrderFn = fetchWebAppGroupOrder

type webAppGroupOrderAccessMode int

const (
	groupOrderAccessStore webAppGroupOrderAccessMode = iota
	groupOrderAccessParticipant
	groupOrderAccessHost
)

type webAppGroupOrderResponse struct {
	GroupOrder webAppGroupOrderSnapshot `json:"groupOrder"`
}

type webAppGroupOrderSnapshot struct {
	ID           string                        `json:"id"`
	StoreID      string                        `json:"storeId"`
	Host         channelContact                `json:"host"`
	Participants []webAppGroupOrderParticipant `json:"participants"`
}

type webAppGroupOrderParticipant struct {
	ParticipantID string         `json:"participantId"`
	Contact       channelContact `json:"channelContact"`
	DisplayName   string         `json:"displayName"`
}

func resolveSessionGroupOrderStore(session channelSession, requestedStoreID string) (string, error) {
	sessionStoreID := strings.TrimSpace(session.StoreID)
	if sessionStoreID == "" {
		return "", errWebAppSessionMissingStore
	}
	requestedStoreID = strings.TrimSpace(requestedStoreID)
	if requestedStoreID != "" && requestedStoreID != sessionStoreID {
		return "", errWebAppGroupOrderForbidden
	}
	return sessionStoreID, nil
}

func authorizeWebAppGroupOrder(
	ctx context.Context,
	cfg *serviceConfig,
	client *http.Client,
	session channelSession,
	groupID string,
	mode webAppGroupOrderAccessMode,
) (webAppGroupOrderSnapshot, error) {
	group, err := fetchWebAppGroupOrderFn(ctx, cfg, client, groupID)
	if err != nil {
		return webAppGroupOrderSnapshot{}, err
	}
	sessionStoreID, err := resolveSessionGroupOrderStore(session, "")
	if err != nil {
		return webAppGroupOrderSnapshot{}, err
	}
	if strings.TrimSpace(group.StoreID) == "" || strings.TrimSpace(group.StoreID) != sessionStoreID {
		return webAppGroupOrderSnapshot{}, errWebAppGroupOrderForbidden
	}

	participantID := groupOrderParticipantIDForSession(session)
	switch mode {
	case groupOrderAccessStore:
		return group, nil
	case groupOrderAccessParticipant:
		if participantID != "" && groupOrderHasParticipant(group, participantID) {
			return group, nil
		}
	case groupOrderAccessHost:
		if participantID != "" && groupOrderContactParticipantID(group.Host) == participantID {
			return group, nil
		}
	}
	return webAppGroupOrderSnapshot{}, errWebAppGroupOrderForbidden
}

func fetchWebAppGroupOrder(
	ctx context.Context,
	cfg *serviceConfig,
	client *http.Client,
	groupID string,
) (webAppGroupOrderSnapshot, error) {
	groupID = strings.TrimSpace(groupID)
	if groupID == "" {
		return webAppGroupOrderSnapshot{}, errWebAppGroupOrderNotFound
	}
	baseURL := strings.TrimSpace(cfg.OrderServiceURL)
	if baseURL == "" {
		return webAppGroupOrderSnapshot{}, errWebAppGroupOrderLookupFailed
	}
	endpoint := serviceURL(baseURL, "group_orders", groupID)
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		return webAppGroupOrderSnapshot{}, errWebAppGroupOrderLookupFailed
	}
	resp, err := client.Do(req)
	if err != nil {
		return webAppGroupOrderSnapshot{}, errWebAppGroupOrderLookupFailed
	}
	defer resp.Body.Close()
	if resp.StatusCode == http.StatusNotFound {
		return webAppGroupOrderSnapshot{}, errWebAppGroupOrderNotFound
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return webAppGroupOrderSnapshot{}, errWebAppGroupOrderLookupFailed
	}
	var payload webAppGroupOrderResponse
	if err := json.NewDecoder(resp.Body).Decode(&payload); err != nil {
		return webAppGroupOrderSnapshot{}, errWebAppGroupOrderLookupFailed
	}
	if strings.TrimSpace(payload.GroupOrder.ID) == "" {
		return webAppGroupOrderSnapshot{}, errWebAppGroupOrderNotFound
	}
	return payload.GroupOrder, nil
}

func groupOrderParticipantIDForSession(session channelSession) string {
	if userID := strings.TrimSpace(session.UserID); userID != "" {
		return userID
	}
	if accountID := strings.TrimSpace(session.AccountID); accountID != "" {
		return accountID
	}
	return strings.TrimSpace(session.DisplayName)
}

func groupOrderContactParticipantID(contact channelContact) string {
	if userID := strings.TrimSpace(contact.UserID); userID != "" {
		return userID
	}
	if accountID := strings.TrimSpace(contact.AccountID); accountID != "" {
		return accountID
	}
	return strings.TrimSpace(contact.DisplayName)
}

func groupOrderHasParticipant(group webAppGroupOrderSnapshot, participantID string) bool {
	participantID = strings.TrimSpace(participantID)
	if participantID == "" {
		return false
	}
	for _, participant := range group.Participants {
		if strings.TrimSpace(participant.ParticipantID) == participantID {
			return true
		}
	}
	return false
}

func resolveSessionParticipantID(session channelSession, requestedID string) (string, error) {
	sessionParticipantID := groupOrderParticipantIDForSession(session)
	if sessionParticipantID == "" {
		return "", errWebAppGroupOrderForbidden
	}
	requestedID = strings.TrimSpace(requestedID)
	if requestedID != "" && requestedID != sessionParticipantID {
		return "", errWebAppGroupOrderForbidden
	}
	return sessionParticipantID, nil
}

func writeWebAppGroupOrderAccessError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, errWebAppSessionMissingStore):
		writeJSON(w, http.StatusConflict, map[string]string{"error": "session_store_missing"})
	case errors.Is(err, errWebAppGroupOrderNotFound):
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "group_order_not_found"})
	case errors.Is(err, errWebAppGroupOrderForbidden):
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "forbidden"})
	default:
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "group_order_lookup_failed"})
	}
}
