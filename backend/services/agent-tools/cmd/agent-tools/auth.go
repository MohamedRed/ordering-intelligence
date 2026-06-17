package main

import (
	"context"
	"crypto/subtle"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/golang-jwt/jwt/v4"
)

var defaultAgentScopes = []string{
	"menu:read",
	"orders:read",
	"orders:write",
	"wait_time:read",
	"group_orders:read",
	"group_orders:write",
}

var allowedAgentScopes = func() map[string]struct{} {
	scopes := make(map[string]struct{}, len(defaultAgentScopes))
	for _, scope := range defaultAgentScopes {
		scopes[scope] = struct{}{}
	}
	return scopes
}()

type accessTokenClaims struct {
	Scope string `json:"scope"`
	jwt.RegisteredClaims
}

func handleToken(cfg *serviceConfig, w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeOAuthError(w, http.StatusMethodNotAllowed, "invalid_request", "method not allowed")
		return
	}

	grantType, scope, clientID, clientSecret, err := parseOAuthClientCredentials(r)
	if err != nil {
		writeOAuthError(w, http.StatusBadRequest, "invalid_request", err.Error())
		return
	}
	if grantType != "client_credentials" {
		writeOAuthError(w, http.StatusBadRequest, "unsupported_grant_type", "unsupported grant_type")
		return
	}

	if clientID == "" {
		clientID = cfg.OAuthClientID
	}

	if subtle.ConstantTimeCompare([]byte(clientID), []byte(cfg.OAuthClientID)) != 1 ||
		subtle.ConstantTimeCompare([]byte(clientSecret), []byte(cfg.OAuthClientSecret)) != 1 {
		// OAuth spec expects 401 + WWW-Authenticate for invalid_client.
		w.Header().Set("WWW-Authenticate", `Basic realm="agent-tools", charset="UTF-8"`)
		writeOAuthError(w, http.StatusUnauthorized, "invalid_client", "invalid client credentials")
		return
	}

	normalizedScope, err := normalizeRequestedScopes(scope)
	if err != nil {
		writeOAuthError(w, http.StatusBadRequest, "invalid_scope", err.Error())
		return
	}

	now := time.Now().UTC()
	exp := now.Add(time.Duration(cfg.TokenTTLSeconds) * time.Second)
	claims := accessTokenClaims{
		Scope: normalizedScope,
		RegisteredClaims: jwt.RegisteredClaims{
			Issuer:    cfg.JWTIssuer,
			Subject:   clientID,
			Audience:  []string{cfg.JWTAudience},
			IssuedAt:  jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(exp),
		},
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	signed, err := token.SignedString([]byte(cfg.JWTSigningSecret))
	if err != nil {
		writeOAuthError(w, http.StatusInternalServerError, "server_error", "failed to sign token")
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"access_token": signed,
		"token_type":   "Bearer",
		"expires_in":   cfg.TokenTTLSeconds,
		"scope":        normalizedScope,
	})
}

func parseOAuthClientCredentials(r *http.Request) (grantType, scope, clientID, clientSecret string, err error) {
	// OAuth2 token endpoint is typically form-encoded. We support:
	// - Authorization: Basic base64(client_id:client_secret)
	// - client_id/client_secret in the body
	var form url.Values
	ct := strings.ToLower(strings.TrimSpace(strings.Split(r.Header.Get("Content-Type"), ";")[0]))
	switch ct {
	case "", "application/x-www-form-urlencoded":
		if err := r.ParseForm(); err != nil {
			return "", "", "", "", errors.New("invalid form")
		}
		form = r.PostForm
	case "application/json":
		var body map[string]any
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			return "", "", "", "", errors.New("invalid json")
		}
		form = make(url.Values)
		for k, v := range body {
			form.Set(k, fmt.Sprintf("%v", v))
		}
	default:
		return "", "", "", "", errors.New("unsupported content-type")
	}

	grantType = strings.TrimSpace(form.Get("grant_type"))
	scope = strings.TrimSpace(form.Get("scope"))
	clientID = strings.TrimSpace(form.Get("client_id"))
	clientSecret = strings.TrimSpace(form.Get("client_secret"))

	if u, p, ok := basicAuthClientCreds(r.Header.Get("Authorization")); ok {
		if clientID == "" {
			clientID = u
		}
		if clientSecret == "" {
			clientSecret = p
		}
	}

	if grantType == "" {
		return "", "", "", "", errors.New("missing grant_type")
	}
	if clientSecret == "" {
		return "", "", "", "", errors.New("missing client_secret")
	}
	return grantType, scope, clientID, clientSecret, nil
}

func basicAuthClientCreds(authHeader string) (clientID, clientSecret string, ok bool) {
	authHeader = strings.TrimSpace(authHeader)
	if !strings.HasPrefix(authHeader, "Basic ") {
		return "", "", false
	}
	raw := strings.TrimSpace(strings.TrimPrefix(authHeader, "Basic "))
	decoded, err := base64.StdEncoding.DecodeString(raw)
	if err != nil {
		return "", "", false
	}
	parts := strings.SplitN(string(decoded), ":", 2)
	if len(parts) != 2 {
		return "", "", false
	}
	return parts[0], parts[1], true
}

func apiKeyOrBearerJWTMiddleware(cfg *serviceConfig) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			// Allow preflight without auth.
			if r.Method == http.MethodOptions {
				next.ServeHTTP(w, r)
				return
			}

			// ElevenLabs webhook tools support static headers. Keep this path explicit
			// and scope-limited to the same allow-list as OAuth tokens.
			if apiKey := strings.TrimSpace(r.Header.Get("X-API-Key")); apiKey != "" {
				if subtle.ConstantTimeCompare([]byte(apiKey), []byte(cfg.OAuthClientSecret)) == 1 {
					claims := accessTokenClaims{
						Scope: defaultAgentScopeString(),
						RegisteredClaims: jwt.RegisteredClaims{
							Issuer:   cfg.JWTIssuer,
							Subject:  "api-key",
							Audience: []string{cfg.JWTAudience},
						},
					}
					ctx := context.WithValue(r.Context(), tokenClaimsContextKey, claims)
					next.ServeHTTP(w, r.WithContext(ctx))
					return
				}
				writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
				return
			}

			authHeader := strings.TrimSpace(r.Header.Get("Authorization"))
			if authHeader == "" {
				writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "missing_auth"})
				return
			}
			tokenString := strings.TrimSpace(strings.TrimPrefix(authHeader, "Bearer "))
			if tokenString == authHeader {
				writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid_auth_header"})
				return
			}

			var claims accessTokenClaims
			parsed, err := jwt.ParseWithClaims(tokenString, &claims, func(t *jwt.Token) (interface{}, error) {
				if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
					return nil, fmt.Errorf("unexpected signing method")
				}
				return []byte(cfg.JWTSigningSecret), nil
			})
			if err != nil || !parsed.Valid {
				writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
				return
			}
			if claims.Issuer != cfg.JWTIssuer {
				writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
				return
			}
			if !claims.VerifyAudience(cfg.JWTAudience, true) {
				writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
				return
			}
			if err := validateAllowedScopeString(claims.Scope); err != nil {
				writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
				return
			}

			ctx := context.WithValue(r.Context(), tokenClaimsContextKey, claims)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

type ctxKey string

const tokenClaimsContextKey ctxKey = "agent_tools_claims"

func requireScopes(ctx context.Context, w http.ResponseWriter, required ...string) bool {
	val := ctx.Value(tokenClaimsContextKey)
	claims, ok := val.(accessTokenClaims)
	if !ok {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
		return false
	}
	have := scopeSet(claims.Scope)
	for _, req := range required {
		if !have[req] {
			writeJSON(w, http.StatusForbidden, map[string]string{"error": "insufficient_scope", "required": req})
			return false
		}
	}
	return true
}

func normalizeRequestedScopes(scope string) (string, error) {
	if strings.TrimSpace(scope) == "" {
		return defaultAgentScopeString(), nil
	}

	seen := map[string]bool{}
	normalized := []string{}
	for _, requested := range strings.Fields(scope) {
		if _, ok := allowedAgentScopes[requested]; !ok {
			return "", fmt.Errorf("unsupported scope %q", requested)
		}
		if !seen[requested] {
			normalized = append(normalized, requested)
			seen[requested] = true
		}
	}
	if len(normalized) == 0 {
		return defaultAgentScopeString(), nil
	}
	return strings.Join(normalized, " "), nil
}

func validateAllowedScopeString(scope string) error {
	if strings.TrimSpace(scope) == "" {
		return errors.New("scope required")
	}
	_, err := normalizeRequestedScopes(scope)
	return err
}

func defaultAgentScopeString() string {
	return strings.Join(defaultAgentScopes, " ")
}

func scopeSet(scope string) map[string]bool {
	out := make(map[string]bool)
	for _, s := range strings.Fields(scope) {
		out[strings.TrimSpace(s)] = true
	}
	return out
}
