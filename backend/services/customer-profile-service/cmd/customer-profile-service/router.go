package main

import (
	"net/http"

	cloudfirestore "cloud.google.com/go/firestore"
	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
)

func buildRouter(cfg *serviceConfig, fs *cloudfirestore.Client) http.Handler {
	router := chi.NewRouter()
	router.Use(middleware.RequestID)
	router.Use(middleware.Logger)
	router.Use(middleware.Recoverer)

	router.Get("/healthz", handleHealthz(cfg))
	router.Get("/healthz/", handleHealthz(cfg))

	router.Get("/v1/customers/by-phone", handleCustomerByPhone(fs))
	router.Get("/v1/customers/contact", handleCustomerContact(fs))
	router.Post("/tasks/orders-events", handleOrdersEvents(fs))

	router.Post("/v1/customers/resolve", handleResolveCustomer(fs))
	router.Get("/v1/customers/{customerId}", handleGetCustomer(fs))
	router.Post("/v1/customers/{customerId}/fuel-preauth-cap", handleFuelPreauthCap(fs))
	router.Post("/v1/customers/link/start", handleLinkStart(fs))
	router.Post("/v1/customers/link/complete", handleLinkComplete(fs))
	router.Post("/v1/customers/unlink", handleUnlink(fs))

	return router
}
