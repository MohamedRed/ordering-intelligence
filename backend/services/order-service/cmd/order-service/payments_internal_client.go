package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"time"

	"google.golang.org/api/idtoken"
)

const paymentsRequestTimeout = 12 * time.Second

func doPaymentsJSONRequest(
	ctx context.Context,
	cfg *serviceConfig,
	method string,
	path string,
	payload any,
) (*http.Response, error) {
	if cfg == nil || strings.TrimSpace(cfg.PaymentsServiceURL) == "" {
		return nil, errors.New("payments_service_not_configured")
	}
	body, err := json.Marshal(payload)
	if err != nil {
		return nil, err
	}
	endpoint := strings.TrimRight(cfg.PaymentsServiceURL, "/") + path
	req, err := http.NewRequestWithContext(ctx, method, endpoint, bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")

	tokenSource, err := idtoken.NewTokenSource(ctx, strings.TrimRight(cfg.PaymentsServiceURL, "/"))
	if err != nil {
		return nil, err
	}
	token, err := tokenSource.Token()
	if err != nil {
		return nil, err
	}
	token.SetAuthHeader(req)

	client := &http.Client{Timeout: paymentsRequestTimeout}
	return client.Do(req)
}
