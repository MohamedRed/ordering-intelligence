package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"

	"golang.org/x/oauth2"
	"google.golang.org/api/idtoken"
)

var errCustomerProfileUnavailable = errors.New("customer_profile_unavailable")

func resolveCustomerProfile(
	ctx context.Context,
	baseURL string,
	payload customerProfileResolveRequest,
) (customerProfileResponse, error) {
	status, body, err := doCustomerProfileRequest(ctx, baseURL, http.MethodPost, "/v1/customers/resolve", payload)
	if err != nil {
		return customerProfileResponse{}, err
	}
	if status < 200 || status >= 300 {
		return customerProfileResponse{}, fmt.Errorf("customer_profile_resolve_failed status=%d", status)
	}
	var out customerProfileResponse
	if err := json.Unmarshal(body, &out); err != nil {
		return customerProfileResponse{}, err
	}
	return out, nil
}

func fetchCustomerProfile(ctx context.Context, baseURL, customerID string) (customerProfileResponse, error) {
	customerID = strings.TrimSpace(customerID)
	if customerID == "" {
		return customerProfileResponse{}, errCustomerProfileUnavailable
	}
	path := fmt.Sprintf("/v1/customers/%s", url.PathEscape(customerID))
	status, body, err := doCustomerProfileRequest(ctx, baseURL, http.MethodGet, path, nil)
	if err != nil {
		return customerProfileResponse{}, err
	}
	if status < 200 || status >= 300 {
		return customerProfileResponse{}, fmt.Errorf("customer_profile_fetch_failed status=%d", status)
	}
	var out customerProfileResponse
	if err := json.Unmarshal(body, &out); err != nil {
		return customerProfileResponse{}, err
	}
	return out, nil
}

func updateCustomerFuelPreauthCap(
	ctx context.Context,
	baseURL string,
	customerID string,
	capCents int64,
) (customerProfileResponse, error) {
	customerID = strings.TrimSpace(customerID)
	if customerID == "" {
		return customerProfileResponse{}, errCustomerProfileUnavailable
	}
	path := fmt.Sprintf("/v1/customers/%s/fuel-preauth-cap", url.PathEscape(customerID))
	status, body, err := doCustomerProfileRequest(ctx, baseURL, http.MethodPost, path, map[string]any{
		"fuelPreauthCapCents": capCents,
	})
	if err != nil {
		return customerProfileResponse{}, err
	}
	if status < 200 || status >= 300 {
		return customerProfileResponse{}, fmt.Errorf("customer_profile_update_failed status=%d", status)
	}
	var out customerProfileResponse
	if err := json.Unmarshal(body, &out); err != nil {
		return customerProfileResponse{}, err
	}
	return out, nil
}

func doCustomerProfileRequest(
	ctx context.Context,
	baseURL string,
	method string,
	path string,
	payload any,
) (int, []byte, error) {
	base := strings.TrimSpace(baseURL)
	if base == "" {
		return 0, nil, errCustomerProfileUnavailable
	}
	tokenSource, err := idtoken.NewTokenSource(ctx, base)
	if err != nil {
		return 0, nil, err
	}
	client := oauth2.NewClient(ctx, tokenSource)

	var body io.Reader
	if payload != nil {
		raw, err := json.Marshal(payload)
		if err != nil {
			return 0, nil, err
		}
		body = bytes.NewReader(raw)
	}
	endpoint := strings.TrimRight(base, "/") + path
	req, _ := http.NewRequestWithContext(ctx, method, endpoint, body)
	if payload != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	resp, err := client.Do(req)
	if err != nil {
		return 0, nil, err
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(resp.Body)
	return resp.StatusCode, raw, nil
}
