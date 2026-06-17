package main

import (
	"bytes"
	"context"
	"io"
	"log"
	"net/http"
	"strings"
	"time"

	"golang.org/x/oauth2"
)

func proxyToOrderService(
	cfg *serviceConfig,
	client *http.Client,
	tokenSrc oauth2.TokenSource,
	w http.ResponseWriter,
	r *http.Request,
	method string,
	path string,
	body []byte,
) {
	target := strings.TrimRight(cfg.OrderServiceURL, "/") + path

	ctx, cancel := context.WithTimeout(r.Context(), 15*time.Second)
	defer cancel()

	var reqBody io.Reader
	if body != nil {
		reqBody = bytes.NewReader(body)
	}

	req, err := http.NewRequestWithContext(ctx, method, target, reqBody)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "proxy_failed"})
		return
	}
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}

	if v := r.Header.Get("Idempotency-Key"); v != "" {
		req.Header.Set("Idempotency-Key", v)
	}

	tok, err := tokenSrc.Token()
	if err != nil {
		log.Printf("failed minting idtoken: %v", err)
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "upstream_auth_failed"})
		return
	}
	req.Header.Set("Authorization", "Bearer "+tok.AccessToken)

	resp, err := client.Do(req)
	if err != nil {
		log.Printf("order-service proxy error: %v", err)
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "upstream_unavailable"})
		return
	}
	defer resp.Body.Close()

	if path == "/orders" && resp.StatusCode >= 400 {
		respBody, _ := io.ReadAll(resp.Body)
		log.Printf("order-service /orders failed status=%d body=%s", resp.StatusCode, truncateForLog(respBody, 1200))
		w.Header().Set("Content-Type", resp.Header.Get("Content-Type"))
		w.WriteHeader(resp.StatusCode)
		_, _ = w.Write(respBody)
		return
	}

	w.Header().Set("Content-Type", resp.Header.Get("Content-Type"))
	w.WriteHeader(resp.StatusCode)
	_, _ = io.Copy(w, resp.Body)
}

func proxyToWaitTimeService(
	cfg *serviceConfig,
	client *http.Client,
	tokenSrc oauth2.TokenSource,
	w http.ResponseWriter,
	r *http.Request,
	method string,
	path string,
	body []byte,
) {
	proxyToService(cfg.WaitTimeServiceURL, client, tokenSrc, w, r, method, path, body, 8*time.Second)
}

func proxyToDispatchService(
	cfg *serviceConfig,
	client *http.Client,
	tokenSrc oauth2.TokenSource,
	w http.ResponseWriter,
	r *http.Request,
	method string,
	path string,
	body []byte,
) {
	proxyToService(cfg.DispatchServiceURL, client, tokenSrc, w, r, method, path, body, 10*time.Second)
}

func proxyToDeliveryService(
	cfg *serviceConfig,
	client *http.Client,
	tokenSrc oauth2.TokenSource,
	w http.ResponseWriter,
	r *http.Request,
	method string,
	path string,
	body []byte,
) {
	proxyToService(cfg.DeliveryServiceURL, client, tokenSrc, w, r, method, path, body, 10*time.Second)
}

func proxyToService(
	baseURL string,
	client *http.Client,
	tokenSrc oauth2.TokenSource,
	w http.ResponseWriter,
	r *http.Request,
	method string,
	path string,
	body []byte,
	timeout time.Duration,
) {
	target := strings.TrimRight(baseURL, "/") + path

	ctx, cancel := context.WithTimeout(r.Context(), timeout)
	defer cancel()

	var reqBody io.Reader
	if body != nil {
		reqBody = bytes.NewReader(body)
	}

	req, err := http.NewRequestWithContext(ctx, method, target, reqBody)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "proxy_failed"})
		return
	}
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}

	tok, err := tokenSrc.Token()
	if err != nil {
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "upstream_auth_failed"})
		return
	}
	req.Header.Set("Authorization", "Bearer "+tok.AccessToken)

	resp, err := client.Do(req)
	if err != nil {
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "upstream_unavailable"})
		return
	}
	defer resp.Body.Close()

	w.Header().Set("Content-Type", resp.Header.Get("Content-Type"))
	w.WriteHeader(resp.StatusCode)
	_, _ = io.Copy(w, resp.Body)
}

func fetchFromOrderService(
	cfg *serviceConfig,
	client *http.Client,
	tokenSrc oauth2.TokenSource,
	r *http.Request,
	method string,
	path string,
	body []byte,
) (status int, contentType string, respBody []byte, err error) {
	target := strings.TrimRight(cfg.OrderServiceURL, "/") + path

	ctx, cancel := context.WithTimeout(r.Context(), 15*time.Second)
	defer cancel()

	var reqBody io.Reader
	if body != nil {
		reqBody = bytes.NewReader(body)
	}

	req, err := http.NewRequestWithContext(ctx, method, target, reqBody)
	if err != nil {
		return 0, "", nil, err
	}
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}

	if v := r.Header.Get("Idempotency-Key"); v != "" {
		req.Header.Set("Idempotency-Key", v)
	}

	tok, err := tokenSrc.Token()
	if err != nil {
		return 0, "", nil, err
	}
	req.Header.Set("Authorization", "Bearer "+tok.AccessToken)

	resp, err := client.Do(req)
	if err != nil {
		return 0, "", nil, err
	}
	defer resp.Body.Close()

	b, err := io.ReadAll(resp.Body)
	if err != nil {
		return 0, "", nil, err
	}
	return resp.StatusCode, resp.Header.Get("Content-Type"), b, nil
}
