package main

import (
	"context"
	"net/http"
	"strings"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
	agentcontext "github.com/ordering-intelligence/agentcontext"
)

func handleWebAppChatTurn(
	w http.ResponseWriter,
	r *http.Request,
	cfg *serviceConfig,
	firestoreClient *cloudfirestore.Client,
	manager *sessionManager,
) {
	payload, status, code := decodeWebAppChatTurnRequest(r)
	if status != 0 {
		writeJSON(w, status, map[string]string{"error": code})
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 20*time.Second)
	defer cancel()

	session, err := loadSessionByID(ctx, firestoreClient, payload.SessionID)
	if err != nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "session_not_found"})
		return
	}

	seed := normalizeSeedContext(payload.SeededIntro, payload.SeededCategories, payload.SeededSource)
	applySeedContextToSession(&session, seed)

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
	seedFromSession := seedContextFromSession(session)
	applySeedContextToDyn(dyn, seedFromSession)

	text := payload.Text
	if seedFromSession.hasContent() && !session.SeededContextSent {
		if prefix := seedContextPrefix(seedFromSession); strings.TrimSpace(prefix) != "" {
			text = prefix + "\n\nUtilisateur: " + payload.Text
			session.SeededContextSent = true
		}
	}

	responseText, conversationID, err := manager.SendMessage(ctx, agentID, dyn, text, cfg)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "agent_error"})
		return
	}
	if seedFromSession.hasContent() && looksLikeSeededGreeting(responseText) {
		retryCtx, cancelRetry := context.WithTimeout(ctx, 6*time.Second)
		defer cancelRetry()
		if followup, convID, err := manager.ReadNextResponse(retryCtx, agentID, dyn); err == nil && strings.TrimSpace(followup) != "" {
			responseText = followup
			if convID != "" {
				conversationID = convID
			}
		}
	}

	session.ElevenLabsConversationID = conversationID
	session.LastSeenAt = time.Now().UTC()
	if err := upsertSession(ctx, firestoreClient, session); err != nil {
	}

	writeJSON(w, http.StatusOK, parseWebAppChatResponse(responseText))
}
