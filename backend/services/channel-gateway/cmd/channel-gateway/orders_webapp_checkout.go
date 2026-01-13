package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
)

type orderCheckoutResponse struct {
	CheckoutURL string `json:"checkoutUrl"`
	PaymentID   string `json:"paymentId"`
	SessionID   string `json:"sessionId"`
}

func createOrderCheckout(
	ctx context.Context,
	cfg *serviceConfig,
	client *http.Client,
	orderID string,
	successURL string,
	cancelURL string,
	currency string,
) (orderCheckoutResponse, error) {
	payload := map[string]string{
		"successUrl": successURL,
		"cancelUrl":  cancelURL,
	}
	if strings.TrimSpace(currency) != "" {
		payload["currency"] = currency
	}
	body, _ := json.Marshal(payload)
	endpoint := fmt.Sprintf("%s/orders/%s/checkout", strings.TrimRight(cfg.PaymentsServiceURL, "/"), orderID)
	req, _ := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err := client.Do(req)
	if err != nil {
		return orderCheckoutResponse{}, err
	}
	defer resp.Body.Close()
	respBody, _ := io.ReadAll(resp.Body)
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return orderCheckoutResponse{}, fmt.Errorf("payments_service_error: %s", string(respBody))
	}
	var checkout orderCheckoutResponse
	if err := json.Unmarshal(respBody, &checkout); err != nil {
		return orderCheckoutResponse{}, err
	}
	return checkout, nil
}

func createOrderPreauthCheckout(
	ctx context.Context,
	cfg *serviceConfig,
	client *http.Client,
	orderID string,
	successURL string,
	cancelURL string,
	currency string,
	amountCents int64,
) (orderCheckoutResponse, error) {
	payload := map[string]any{
		"successUrl": successURL,
		"cancelUrl":  cancelURL,
		"amountCents": amountCents,
	}
	if strings.TrimSpace(currency) != "" {
		payload["currency"] = currency
	}
	body, _ := json.Marshal(payload)
	endpoint := fmt.Sprintf("%s/orders/%s/preauth", strings.TrimRight(cfg.PaymentsServiceURL, "/"), orderID)
	req, _ := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err := client.Do(req)
	if err != nil {
		return orderCheckoutResponse{}, err
	}
	defer resp.Body.Close()
	respBody, _ := io.ReadAll(resp.Body)
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return orderCheckoutResponse{}, fmt.Errorf("payments_service_error: %s", string(respBody))
	}
	var checkout orderCheckoutResponse
	if err := json.Unmarshal(respBody, &checkout); err != nil {
		return orderCheckoutResponse{}, err
	}
	return checkout, nil
}
