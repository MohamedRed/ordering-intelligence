package main

import (
	"bytes"
	"context"
	"io"
	"net/http"
	"strings"
	"time"

	"golang.org/x/oauth2"
)

func proxyToPaymentsService(
	cfg *serviceConfig,
	client *http.Client,
	tokenSrc oauth2.TokenSource,
	w http.ResponseWriter,
	r *http.Request,
	method string,
	path string,
	body []byte,
) {
	target := strings.TrimRight(cfg.PaymentsServiceURL, "/") + path

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

	if ct := resp.Header.Get("Content-Type"); ct != "" {
		w.Header().Set("Content-Type", ct)
	}
	w.WriteHeader(resp.StatusCode)
	_, _ = io.Copy(w, resp.Body)
}
