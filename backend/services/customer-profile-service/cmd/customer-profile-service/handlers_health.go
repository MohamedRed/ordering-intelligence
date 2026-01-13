package main

import "net/http"

func handleHealthz(cfg *serviceConfig) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, map[string]any{
			"status":      "ok",
			"service":     "customer-profile-service",
			"environment": cfg.Environment,
		})
	}
}
