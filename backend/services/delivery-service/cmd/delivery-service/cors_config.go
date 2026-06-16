package main

import (
	"fmt"
	"net/http"
	"net/url"
	"strings"

	"github.com/go-chi/cors"
)

func resolveDeliveryCORSOrigins(rawOrigins string) ([]string, error) {
	parts := splitCSV(rawOrigins)
	if len(parts) == 0 {
		return nil, fmt.Errorf("CORS_ORIGINS is required for delivery-service")
	}

	seen := make(map[string]struct{}, len(parts))
	origins := make([]string, 0, len(parts))
	for _, origin := range parts {
		normalized, err := normalizeDeliveryCORSOrigin(origin)
		if err != nil {
			return nil, err
		}
		if _, ok := seen[normalized]; ok {
			continue
		}
		seen[normalized] = struct{}{}
		origins = append(origins, normalized)
	}
	return origins, nil
}

func normalizeDeliveryCORSOrigin(origin string) (string, error) {
	origin = strings.TrimSpace(origin)
	if origin == "" || strings.Contains(origin, "*") {
		return "", fmt.Errorf("invalid CORS origin %q: wildcards and blank origins are not allowed", origin)
	}

	parsed, err := url.Parse(origin)
	if err != nil || parsed.Scheme == "" || parsed.Host == "" {
		return "", fmt.Errorf("invalid CORS origin %q: expected absolute http(s) origin", origin)
	}
	if parsed.Scheme != "http" && parsed.Scheme != "https" {
		return "", fmt.Errorf("invalid CORS origin %q: only http and https are supported", origin)
	}
	if parsed.User != nil || parsed.RawQuery != "" || parsed.Fragment != "" || (parsed.Path != "" && parsed.Path != "/") {
		return "", fmt.Errorf("invalid CORS origin %q: include only scheme, host, and optional port", origin)
	}
	return parsed.Scheme + "://" + parsed.Host, nil
}

func deliveryCORSOptions(allowedOrigins []string) cors.Options {
	return cors.Options{
		AllowedOrigins:   allowedOrigins,
		AllowedMethods:   []string{"GET", "POST", "PATCH", "PUT", "OPTIONS"},
		AllowedHeaders:   []string{"Accept", "Authorization", "Content-Type"},
		AllowCredentials: true,
		MaxAge:           300,
	}
}

func deliveryCORSMiddleware(allowedOrigins []string) func(http.Handler) http.Handler {
	return cors.Handler(deliveryCORSOptions(allowedOrigins))
}
