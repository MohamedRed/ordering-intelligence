package main

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
	agentcontext "github.com/ordering-intelligence/agentcontext"
)

type webappChatPrewarmRequest struct {
	SessionID        string   `json:"sessionId"`
	SeededIntro      string   `json:"seededIntro,omitempty"`
	SeededSource     string   `json:"seededSource,omitempty"`
	SeededCategories []string `json:"seededCategories,omitempty"`
}

type webappChatPrewarmResponse struct {
	Status         string `json:"status"`
	ConversationID string `json:"conversationId,omitempty"`
}

func decodeWebAppChatPrewarmRequest(r *http.Request) (webappChatPrewarmRequest, int, string) {
	var payload webappChatPrewarmRequest
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		return payload, http.StatusBadRequest, "invalid_payload"
	}
	payload.SessionID = strings.TrimSpace(payload.SessionID)
	payload.SeededIntro = strings.TrimSpace(payload.SeededIntro)
	payload.SeededSource = strings.TrimSpace(payload.SeededSource)
	if len(payload.SeededCategories) > 0 {
		categories := make([]string, 0, len(payload.SeededCategories))
		for _, raw := range payload.SeededCategories {
			if trimmed := strings.TrimSpace(raw); trimmed != "" {
				categories = append(categories, trimmed)
			}
		}
		payload.SeededCategories = categories
	}
	if payload.SessionID == "" {
		return payload, http.StatusBadRequest, "missing_session"
	}
	return payload, 0, ""
}

func handleWebAppChatPrewarm(
	w http.ResponseWriter,
	r *http.Request,
	cfg *serviceConfig,
	firestoreClient *cloudfirestore.Client,
	manager *sessionManager,
) {
	payload, status, code := decodeWebAppChatPrewarmRequest(r)
	if status != 0 {
		writeJSON(w, status, map[string]string{"error": code})
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 12*time.Second)
	defer cancel()

	session, err := loadSessionByID(ctx, firestoreClient, payload.SessionID)
	if err != nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "session_not_found"})
		return
	}

	seed := normalizeSeedContext(payload.SeededIntro, payload.SeededCategories, payload.SeededSource)
	seedUpdated := applySeedContextToSession(&session, seed)

	route, err := agentcontext.ResolveRoute(ctx, firestoreClient, agentcontext.RouteLookup{
		Channel:          session.Channel,
		ChannelAccountID: session.AccountID,
	})
	if err != nil || route == nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "route_not_found"})
		return
	}

	agentID := resolveAgentID(route.Data, cfg.DefaultAgentID)
	if agentID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_agent"})
		return
	}

	dyn := agentcontext.BuildDynamicVariables(
		ctx,
		*route,
		agentcontext.DynamicVarsInput{
			CallerID:             session.Channel + ":" + session.UserID,
			AgentID:              agentID,
			Channel:              session.Channel,
			ChannelAccountID:     session.AccountID,
			ChannelUserID:        session.UserID,
			ChannelDisplayName:   session.DisplayName,
			FallbackCustomerName: session.DisplayName,
		},
		agentcontext.ServicesConfig{
			CustomerProfileServiceURL: stringOrDefaultEnv("CUSTOMER_PROFILE_SERVICE_URL"),
			RecommendationServiceURL:  stringOrDefaultEnv("RECOMMENDATION_SERVICE_URL"),
			WaitTimeServiceURL:        stringOrDefaultEnv("WAIT_TIME_SERVICE_URL"),
		},
		agentcontext.DynamicVarsOptions{IncludeChannelVars: true},
	)
	applySeedContextToDyn(dyn, seedContextFromSession(session))

	conversationID, err := manager.PrewarmSession(ctx, agentID, dyn, cfg)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "agent_error"})
		return
	}
	if seed.hasContent() {
		drainCtx, cancelDrain := context.WithTimeout(ctx, 900*time.Millisecond)
		defer cancelDrain()
		if drained, convID, err := manager.ReadNextResponse(drainCtx, agentID, dyn); err == nil && strings.TrimSpace(drained) != "" {
			conversationID = convID
		}
	}

	if conversationID != "" {
		session.ElevenLabsConversationID = conversationID
	}
	if seedUpdated || conversationID != "" {
		if err := upsertSession(ctx, firestoreClient, session); err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "session_write_failed"})
			return
		}
	}

	writeJSON(w, http.StatusOK, webappChatPrewarmResponse{
		Status:         "ok",
		ConversationID: conversationID,
	})
}
