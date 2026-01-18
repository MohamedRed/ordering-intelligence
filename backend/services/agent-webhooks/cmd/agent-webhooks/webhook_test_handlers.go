package main

import (
	"encoding/json"
	"net/http"
	"strings"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
)

type testConversationInitRequest struct {
	AgentID              string         `json:"agent_id"`
	AgentNumber          string         `json:"agent_number"`
	PhoneNumberID        string         `json:"phone_number_id"`
	CallerID             string         `json:"caller_id"`
	CallSid              string         `json:"call_sid"`
	TenantID             string         `json:"tenant_id"`
	StoreID              string         `json:"store_id"`
	BusinessType         string         `json:"business_type"`
	OnboardingSessionID  string         `json:"onboarding_session_id"`
	DynamicVariables     map[string]any `json:"dynamic_variables"`
	ConversationMetadata map[string]any `json:"metadata"`
}

func handleTestConversationInit(
	w http.ResponseWriter,
	r *http.Request,
	firestoreClient *cloudfirestore.Client,
	cfg *serviceConfig,
) {
	authCtx, ok := requireInternalAuth(cfg, w, r)
	if !ok {
		return
	}

	var payload testConversationInitRequest
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
		return
	}

	agentID := strings.TrimSpace(payload.AgentID)
	if agentID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_agent_id"})
		return
	}

	dyn := payload.DynamicVariables
	if dyn == nil {
		dyn = map[string]any{}
	}
	if payload.StoreID != "" {
		dyn["storeId"] = strings.TrimSpace(payload.StoreID)
	}
	if payload.TenantID != "" {
		dyn["tenantId"] = strings.TrimSpace(payload.TenantID)
	}
	if payload.BusinessType != "" {
		dyn["businessType"] = strings.TrimSpace(payload.BusinessType)
	}
	if payload.OnboardingSessionID != "" {
		dyn["onboardingSessionId"] = strings.TrimSpace(payload.OnboardingSessionID)
	}
	if payload.AgentNumber != "" {
		dyn["agentNumber"] = strings.TrimSpace(payload.AgentNumber)
	}
	if payload.PhoneNumberID != "" {
		dyn["phoneNumberId"] = strings.TrimSpace(payload.PhoneNumberID)
	}

	storeLastConversationInitEvent(r.Context(), firestoreClient, map[string]any{
		"agent_id":              agentID,
		"received_at":           time.Now().UTC(),
		"route_source":          "internal_test",
		"route_doc_id":          "internal_test",
		"phone_number_id":       strings.TrimSpace(payload.PhoneNumberID),
		"to_number":             strings.TrimSpace(payload.AgentNumber),
		"caller_id":             maskPhone(payload.CallerID),
		"call_sid":              orNull(strings.TrimSpace(payload.CallSid)),
		"tenant_id":             strings.TrimSpace(payload.TenantID),
		"store_id":              strings.TrimSpace(payload.StoreID),
		"business_type":         strings.TrimSpace(payload.BusinessType),
		"onboarding_session_id": strings.TrimSpace(payload.OnboardingSessionID),
		"dynamic_variables":     dyn,
		"internal_auth_email":   authCtx.Email,
		"metadata":              payload.ConversationMetadata,
	})

	writeJSON(w, http.StatusOK, map[string]any{
		"dynamic_variables": dyn,
	})
}
