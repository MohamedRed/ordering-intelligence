package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"strings"
)

var errWebAppOrderForbidden = errors.New("order_forbidden")
var errWebAppOrderNotFound = errors.New("order_not_found")
var errWebAppOrderLookupFailed = errors.New("order_lookup_failed")
var errWebAppSessionMissingOrderStore = errors.New("session_store_missing")
var errWebAppSessionMissingCustomer = errors.New("session_customer_missing")

var fetchWebAppOrderFn = fetchWebAppOrder

type webAppOrderSnapshot struct {
	ID         string `json:"id"`
	StoreID    string `json:"storeId"`
	CustomerID string `json:"customerId,omitempty"`
}

func resolveSessionOrderStore(session channelSession, requestedStoreID string) (string, error) {
	sessionStoreID := strings.TrimSpace(session.StoreID)
	if sessionStoreID == "" {
		return "", errWebAppSessionMissingOrderStore
	}
	requestedStoreID = strings.TrimSpace(requestedStoreID)
	if requestedStoreID != "" && requestedStoreID != sessionStoreID {
		return "", errWebAppOrderForbidden
	}
	return sessionStoreID, nil
}

func authorizeSessionOrder(
	ctx context.Context,
	cfg *serviceConfig,
	client *http.Client,
	session channelSession,
	orderID string,
) (webAppOrderSnapshot, error) {
	order, err := fetchWebAppOrderFn(ctx, cfg, client, orderID)
	if err != nil {
		return webAppOrderSnapshot{}, err
	}
	sessionStoreID, err := resolveSessionOrderStore(session, "")
	if err != nil {
		return webAppOrderSnapshot{}, err
	}
	if strings.TrimSpace(order.StoreID) == "" || strings.TrimSpace(order.StoreID) != sessionStoreID {
		return webAppOrderSnapshot{}, errWebAppOrderForbidden
	}
	sessionCustomerID := strings.TrimSpace(session.CustomerID)
	if sessionCustomerID == "" {
		return webAppOrderSnapshot{}, errWebAppSessionMissingCustomer
	}
	if strings.TrimSpace(order.CustomerID) == "" || strings.TrimSpace(order.CustomerID) != sessionCustomerID {
		return webAppOrderSnapshot{}, errWebAppOrderForbidden
	}
	return order, nil
}

func fetchWebAppOrder(
	ctx context.Context,
	cfg *serviceConfig,
	client *http.Client,
	orderID string,
) (webAppOrderSnapshot, error) {
	orderID = strings.TrimSpace(orderID)
	if orderID == "" {
		return webAppOrderSnapshot{}, errWebAppOrderNotFound
	}
	baseURL := strings.TrimSpace(cfg.OrderServiceURL)
	if baseURL == "" {
		return webAppOrderSnapshot{}, errWebAppOrderLookupFailed
	}
	endpoint := fmt.Sprintf("%s/orders/%s", strings.TrimRight(baseURL, "/"), url.PathEscape(orderID))
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		return webAppOrderSnapshot{}, errWebAppOrderLookupFailed
	}
	resp, err := client.Do(req)
	if err != nil {
		return webAppOrderSnapshot{}, errWebAppOrderLookupFailed
	}
	defer resp.Body.Close()
	if resp.StatusCode == http.StatusNotFound {
		return webAppOrderSnapshot{}, errWebAppOrderNotFound
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return webAppOrderSnapshot{}, errWebAppOrderLookupFailed
	}
	var order webAppOrderSnapshot
	if err := json.NewDecoder(resp.Body).Decode(&order); err != nil {
		return webAppOrderSnapshot{}, errWebAppOrderLookupFailed
	}
	if strings.TrimSpace(order.ID) == "" {
		return webAppOrderSnapshot{}, errWebAppOrderNotFound
	}
	return order, nil
}

func writeWebAppOrderAccessError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, errWebAppSessionMissingOrderStore):
		writeJSON(w, http.StatusConflict, map[string]string{"error": "session_store_missing"})
	case errors.Is(err, errWebAppSessionMissingCustomer):
		writeJSON(w, http.StatusConflict, map[string]string{"error": "customer_not_resolved"})
	case errors.Is(err, errWebAppOrderNotFound):
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "order_not_found"})
	case errors.Is(err, errWebAppOrderForbidden):
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "forbidden"})
	default:
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "order_lookup_failed"})
	}
}
