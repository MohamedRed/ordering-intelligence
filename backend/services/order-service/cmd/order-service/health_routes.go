package main

import (
	"net/http"

	"github.com/go-chi/chi/v5"
)

func registerHealthRoutes(router chi.Router, cfg *serviceConfig) {
	handler := func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{
			"status":      "ok",
			"service":     "order-service",
			"environment": cfg.Environment,
		})
	}
	router.Get("/healthz", handler)
	router.Get("/healthz/", handler)
}

func isHealthCheckPath(path string) bool {
	return path == "/healthz" || path == "/healthz/"
}
