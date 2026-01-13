package main

import (
	"net/http"
	"strings"

	cloudfirestore "cloud.google.com/go/firestore"
	"github.com/go-chi/chi/v5"
)

func registerWebAppRoutes(
	router chi.Router,
	basePath string,
	cfg *serviceConfig,
	firestoreClient *cloudfirestore.Client,
	orderHTTPClient *http.Client,
	paymentsHTTPClient *http.Client,
	manager *sessionManager,
) {
	pathPrefix := strings.TrimRight(basePath, "/")
	if pathPrefix == "" {
		pathPrefix = "/telegram/webapp"
	}

	router.Route(pathPrefix, func(r chi.Router) {
		r.Get("/stores/search", func(w http.ResponseWriter, req *http.Request) {
			handleWebAppStoreSearch(w, req, cfg, firestoreClient)
		})
		r.Get("/stores/{storeID}", func(w http.ResponseWriter, req *http.Request) {
			handleWebAppStoreDetails(w, req, firestoreClient)
		})
		r.Get("/reorders/recent", func(w http.ResponseWriter, req *http.Request) {
			handleWebAppRecentReorders(w, req, cfg, firestoreClient)
		})
		r.Get("/reorders/top", func(w http.ResponseWriter, req *http.Request) {
			handleWebAppStoreReorders(w, req, cfg, firestoreClient)
		})
		r.Post("/stores/select", func(w http.ResponseWriter, req *http.Request) {
			handleWebAppStoreSelect(w, req, cfg, firestoreClient)
		})
		r.Get("/stores/{storeID}/menu", func(w http.ResponseWriter, req *http.Request) {
			handleWebAppMenu(w, req, cfg, orderHTTPClient)
		})
		r.Post("/chat/turn", func(w http.ResponseWriter, req *http.Request) {
			handleWebAppChatTurn(w, req, cfg, firestoreClient, manager)
		})
		r.Post("/orders", func(w http.ResponseWriter, req *http.Request) {
			handleWebAppOrderCreate(w, req, cfg, firestoreClient, orderHTTPClient, paymentsHTTPClient)
		})
		r.Post("/orders/{orderId}/fuel/pump", func(w http.ResponseWriter, req *http.Request) {
			orderID := chi.URLParam(req, "orderId")
			if orderID == "" {
				writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_order_id"})
				return
			}
			handleWebAppFuelPumpUpdate(w, req, cfg, firestoreClient, orderHTTPClient, orderID)
		})
		r.Post("/orders/{orderId}/link-updates", func(w http.ResponseWriter, req *http.Request) {
			handleWebAppOrderUpdatesLink(w, req, cfg, firestoreClient, orderHTTPClient)
		})
		r.Get("/identity", func(w http.ResponseWriter, req *http.Request) {
			handleWebAppIdentity(w, req, cfg, firestoreClient)
		})
		r.Post("/identity/link/start", func(w http.ResponseWriter, req *http.Request) {
			handleWebAppIdentityLinkStart(w, req, cfg, firestoreClient)
		})
		r.Post("/identity/link/complete", func(w http.ResponseWriter, req *http.Request) {
			handleWebAppIdentityLinkComplete(w, req, cfg, firestoreClient)
		})
		r.Post("/identity/unlink", func(w http.ResponseWriter, req *http.Request) {
			handleWebAppIdentityUnlink(w, req, cfg, firestoreClient)
		})
		r.Post("/identity/fuel-preauth-cap", func(w http.ResponseWriter, req *http.Request) {
			handleWebAppFuelPreauthCap(w, req, cfg, firestoreClient)
		})
	})

	registerWebAppGroupOrderRoutes(router, pathPrefix, cfg, firestoreClient, orderHTTPClient, paymentsHTTPClient)
}
