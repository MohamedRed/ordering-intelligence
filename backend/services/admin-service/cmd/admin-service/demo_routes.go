package main

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"strings"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
	"github.com/go-chi/chi/v5"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

func registerDemoRoutes(router chi.Router, firestoreClient *cloudfirestore.Client) {
	router.Post("/demo/agent-route", func(w http.ResponseWriter, r *http.Request) {
		var payload struct {
			AgentID                 string   `json:"agentId"`
			TenantID                string   `json:"tenantId"`
			StoreID                 string   `json:"storeId"`
			BusinessType            string   `json:"businessType"`
			Environment             string   `json:"environment"`
			DemoSessionID           string   `json:"demoSessionId"`
			DemoCallerID            string   `json:"demoCallerId"`
			DemoCallSid             string   `json:"demoCallSid"`
			DemoCustomerName        string   `json:"demoCustomerName"`
			DemoIsReturningCustomer *bool    `json:"demoIsReturningCustomer"`
			DemoTopReorders         []string `json:"demoTopReorders"`
			DemoETAMinutes          *int     `json:"demoEtaMinutes"`
		}
		if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
			return
		}
		payload.AgentID = strings.TrimSpace(payload.AgentID)
		payload.TenantID = strings.TrimSpace(payload.TenantID)
		payload.StoreID = strings.TrimSpace(payload.StoreID)
		payload.BusinessType = strings.TrimSpace(payload.BusinessType)
		if payload.AgentID == "" || payload.StoreID == "" || payload.TenantID == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_required_fields"})
			return
		}

		docID := "agent_" + payload.AgentID
		now := time.Now().UTC()
		doc := map[string]any{
			"agent_id":        payload.AgentID,
			"tenant_id":       payload.TenantID,
			"store_id":        payload.StoreID,
			"business_type":   payload.BusinessType,
			"environment":     payload.Environment,
			"demo_session_id": payload.DemoSessionID,
			"updated_at":      now,
			"created_at":      now,
		}
		if strings.TrimSpace(payload.DemoCallerID) != "" {
			doc["demo_caller_id"] = strings.TrimSpace(payload.DemoCallerID)
		}
		if strings.TrimSpace(payload.DemoCallSid) != "" {
			doc["demo_call_sid"] = strings.TrimSpace(payload.DemoCallSid)
		}
		if strings.TrimSpace(payload.DemoCustomerName) != "" {
			doc["demo_customer_name"] = strings.TrimSpace(payload.DemoCustomerName)
		}
		if payload.DemoIsReturningCustomer != nil {
			doc["demo_is_returning_customer"] = *payload.DemoIsReturningCustomer
		}
		if len(payload.DemoTopReorders) > 0 {
			doc["demo_top_reorders"] = payload.DemoTopReorders
		}
		if payload.DemoETAMinutes != nil && *payload.DemoETAMinutes > 0 {
			doc["demo_eta_minutes"] = *payload.DemoETAMinutes
		}
		_, err := firestoreClient.Collection(agentRoutesCollection).Doc(docID).Set(r.Context(), doc, cloudfirestore.MergeAll)
		if err != nil {
			log.Printf("failed to upsert agent route: %v", err)
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "write_failed"})
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{
			"ok":      true,
			"agentId": payload.AgentID,
			"docId":   docID,
		})
	})

	router.Get("/demo/agent-route/{agentId}", func(w http.ResponseWriter, r *http.Request) {
		agentID := strings.TrimSpace(chi.URLParam(r, "agentId"))
		if agentID == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_agent_id"})
			return
		}

		ctx, cancel := context.WithTimeout(r.Context(), 4*time.Second)
		defer cancel()

		docID := "agent_" + agentID

		var route map[string]any
		routeSnap, err := firestoreClient.Collection(agentRoutesCollection).Doc(docID).Get(ctx)
		if err != nil && status.Code(err) != codes.NotFound {
			log.Printf("demo route fetch failed agent=%s err=%v", agentID, err)
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "fetch_failed"})
			return
		}
		if err == nil && routeSnap.Exists() {
			route = routeSnap.Data()
		}

		var lastEvent map[string]any
		evSnap, err := firestoreClient.Collection(agentWebhookEventsCollection).Doc(docID).Get(ctx)
		if err != nil && status.Code(err) != codes.NotFound {
			log.Printf("demo last event fetch failed agent=%s err=%v", agentID, err)
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "fetch_failed"})
			return
		}
		if err == nil && evSnap.Exists() {
			lastEvent = evSnap.Data()
		}

		writeJSON(w, http.StatusOK, map[string]any{
			"ok":        true,
			"agentId":   agentID,
			"route":     route,
			"lastEvent": lastEvent,
		})
	})
}
