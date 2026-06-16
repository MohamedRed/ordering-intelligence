package main

import (
	"errors"
	"fmt"
	"net/url"
	"strings"
)

func parseCORSOrigins(raw string) ([]string, error) {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return nil, errors.New("CORS_ORIGINS is required")
	}

	parts := strings.Split(raw, ",")
	origins := make([]string, 0, len(parts))
	seen := make(map[string]struct{}, len(parts))
	for _, part := range parts {
		origin := strings.TrimSpace(part)
		if origin == "" {
			continue
		}
		if err := validateCORSOrigin(origin); err != nil {
			return nil, err
		}
		if _, exists := seen[origin]; exists {
			continue
		}
		seen[origin] = struct{}{}
		origins = append(origins, origin)
	}

	if len(origins) == 0 {
		return nil, errors.New("CORS_ORIGINS must include at least one explicit origin")
	}
	return origins, nil
}

func validateCORSOrigin(origin string) error {
	if strings.Contains(origin, "*") {
		return errors.New("CORS_ORIGINS must use explicit origins; wildcards are not allowed")
	}

	parsed, err := url.Parse(origin)
	if err != nil {
		return fmt.Errorf("invalid CORS origin %q: %w", origin, err)
	}
	if parsed.Scheme != "http" && parsed.Scheme != "https" {
		return fmt.Errorf("invalid CORS origin %q: scheme must be http or https", origin)
	}
	if parsed.Host == "" {
		return fmt.Errorf("invalid CORS origin %q: host is required", origin)
	}
	if parsed.Path != "" || parsed.RawQuery != "" || parsed.Fragment != "" {
		return fmt.Errorf("invalid CORS origin %q: origin must not include path, query, or fragment", origin)
	}
	return nil
}
