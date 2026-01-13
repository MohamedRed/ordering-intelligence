package main

import (
	"context"
	"net/http"
	"strings"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
)

func handleCustomerByPhone(fs *cloudfirestore.Client) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		callerID := normalizePhone(strings.TrimSpace(r.URL.Query().Get("callerId")))
		if callerID == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_caller"})
			return
		}
		ctx, cancel := context.WithTimeout(r.Context(), 800*time.Millisecond)
		defer cancel()

		identity, found, err := fetchIdentity(ctx, fs, "phone", callerID)
		if err != nil || !found {
			writeJSON(w, http.StatusOK, map[string]any{
				"isReturning":  false,
				"customerName": "",
			})
			return
		}
		customer, err := resolveActiveCustomer(ctx, fs, identity.CustomerID)
		if err != nil {
			writeJSON(w, http.StatusOK, map[string]any{
				"isReturning":  false,
				"customerName": "",
			})
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{
			"isReturning":  strings.TrimSpace(customer.DisplayName) != "",
			"customerName": strings.TrimSpace(customer.DisplayName),
			"lastOrderAt":  customer.LastOrderAt,
		})
	}
}

func handleCustomerContact(fs *cloudfirestore.Client) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		callerID := normalizePhone(strings.TrimSpace(r.URL.Query().Get("callerId")))
		if callerID == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_caller"})
			return
		}

		ctx, cancel := context.WithTimeout(r.Context(), 800*time.Millisecond)
		defer cancel()

		identity, found, err := fetchIdentity(ctx, fs, "phone", callerID)
		if err != nil || !found {
			writeJSON(w, http.StatusOK, map[string]any{
				"phoneE164":     callerID,
				"customerName":  "",
				"profileExists": false,
			})
			return
		}
		customer, err := resolveActiveCustomer(ctx, fs, identity.CustomerID)
		if err != nil {
			writeJSON(w, http.StatusOK, map[string]any{
				"phoneE164":     callerID,
				"customerName":  "",
				"profileExists": false,
			})
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{
			"phoneE164":     callerID,
			"customerName":  strings.TrimSpace(customer.DisplayName),
			"profileExists": true,
		})
	}
}
