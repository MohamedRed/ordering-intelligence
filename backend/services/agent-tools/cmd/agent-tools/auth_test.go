package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v4"
)

func testAuthConfig() *serviceConfig {
	return &serviceConfig{
		OAuthClientID:     "agent-client",
		OAuthClientSecret: "agent-secret",
		JWTSigningSecret:  "jwt-secret",
		JWTIssuer:         "ordering-intelligence",
		JWTAudience:       "agent-tools",
		TokenTTLSeconds:   900,
	}
}

func TestNormalizeRequestedScopesDefaultsToAllAllowedToolScopes(t *testing.T) {
	scope, err := normalizeRequestedScopes("")
	if err != nil {
		t.Fatalf("normalizeRequestedScopes returned error: %v", err)
	}
	for _, required := range []string{
		"menu:read",
		"orders:read",
		"orders:write",
		"wait_time:read",
		"group_orders:read",
		"group_orders:write",
	} {
		if !scopeSet(scope)[required] {
			t.Fatalf("default scope missing %q in %q", required, scope)
		}
	}
}

func TestHandleTokenRejectsUnsupportedScope(t *testing.T) {
	cfg := testAuthConfig()
	form := url.Values{
		"grant_type":    {"client_credentials"},
		"client_id":     {cfg.OAuthClientID},
		"client_secret": {cfg.OAuthClientSecret},
		"scope":         {"menu:read admin:write"},
	}
	req := httptest.NewRequest(http.MethodPost, "/oauth/token", strings.NewReader(form.Encode()))
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	rr := httptest.NewRecorder()

	handleToken(cfg, rr, req)

	if rr.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for unsupported scope, got %d: %s", rr.Code, rr.Body.String())
	}
	var body map[string]string
	if err := json.Unmarshal(rr.Body.Bytes(), &body); err != nil {
		t.Fatalf("invalid json body: %v", err)
	}
	if body["error"] != "invalid_scope" {
		t.Fatalf("expected invalid_scope, got %#v", body)
	}
}

func TestHandleTokenIssuesRequestedAllowedScopes(t *testing.T) {
	cfg := testAuthConfig()
	form := url.Values{
		"grant_type":    {"client_credentials"},
		"client_id":     {cfg.OAuthClientID},
		"client_secret": {cfg.OAuthClientSecret},
		"scope":         {"menu:read group_orders:read menu:read"},
	}
	req := httptest.NewRequest(http.MethodPost, "/oauth/token", strings.NewReader(form.Encode()))
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	rr := httptest.NewRecorder()

	handleToken(cfg, rr, req)

	if rr.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", rr.Code, rr.Body.String())
	}
	var body struct {
		AccessToken string `json:"access_token"`
		Scope       string `json:"scope"`
	}
	if err := json.Unmarshal(rr.Body.Bytes(), &body); err != nil {
		t.Fatalf("invalid json body: %v", err)
	}
	if body.Scope != "menu:read group_orders:read" {
		t.Fatalf("unexpected normalized scope %q", body.Scope)
	}

	claims := parseSignedTestToken(t, cfg, body.AccessToken)
	if claims.Scope != body.Scope {
		t.Fatalf("token scope %q does not match response scope %q", claims.Scope, body.Scope)
	}
}

func TestBearerMiddlewareRejectsSignedTokenWithUnsupportedScope(t *testing.T) {
	cfg := testAuthConfig()
	token := signTestToken(t, cfg, "menu:read admin:write")
	req := httptest.NewRequest(http.MethodGet, "/v1/stores/demo/menu/snapshot", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	rr := httptest.NewRecorder()

	called := false
	handler := apiKeyOrBearerJWTMiddleware(cfg)(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		called = true
	}))
	handler.ServeHTTP(rr, req)

	if called {
		t.Fatal("middleware forwarded request with unsupported token scope")
	}
	if rr.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d: %s", rr.Code, rr.Body.String())
	}
}

func TestAPIKeyMiddlewareUsesDefaultAllowedScopes(t *testing.T) {
	cfg := testAuthConfig()
	req := httptest.NewRequest(http.MethodGet, "/v1/group-orders/demo", nil)
	req.Header.Set("X-API-Key", cfg.OAuthClientSecret)
	rr := httptest.NewRecorder()

	handler := apiKeyOrBearerJWTMiddleware(cfg)(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !requireScopes(r.Context(), w, "group_orders:write") {
			return
		}
		w.WriteHeader(http.StatusNoContent)
	}))
	handler.ServeHTTP(rr, req)

	if rr.Code != http.StatusNoContent {
		t.Fatalf("expected API key to include group order write scope, got %d: %s", rr.Code, rr.Body.String())
	}
}

func signTestToken(t *testing.T, cfg *serviceConfig, scope string) string {
	t.Helper()
	now := time.Now().UTC()
	claims := accessTokenClaims{
		Scope: scope,
		RegisteredClaims: jwt.RegisteredClaims{
			Issuer:    cfg.JWTIssuer,
			Subject:   cfg.OAuthClientID,
			Audience:  []string{cfg.JWTAudience},
			IssuedAt:  jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(now.Add(time.Hour)),
		},
	}
	token, err := jwt.NewWithClaims(jwt.SigningMethodHS256, claims).SignedString([]byte(cfg.JWTSigningSecret))
	if err != nil {
		t.Fatalf("sign token: %v", err)
	}
	return token
}

func parseSignedTestToken(t *testing.T, cfg *serviceConfig, token string) accessTokenClaims {
	t.Helper()
	var claims accessTokenClaims
	parsed, err := jwt.ParseWithClaims(token, &claims, func(t *jwt.Token) (interface{}, error) {
		return []byte(cfg.JWTSigningSecret), nil
	})
	if err != nil {
		t.Fatalf("parse token: %v", err)
	}
	if !parsed.Valid {
		t.Fatal("token is not valid")
	}
	return claims
}
