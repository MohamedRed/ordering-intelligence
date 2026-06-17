package main

import (
	"net/http"
	"strings"

	cloudfirestore "cloud.google.com/go/firestore"
	"github.com/go-chi/chi/v5"
)

func registerWebAppGroupOrderRoutes(
	router chi.Router,
	basePath string,
	cfg *serviceConfig,
	firestoreClient *cloudfirestore.Client,
	orderHTTPClient *http.Client,
	paymentsHTTPClient *http.Client,
) {
	pathPrefix := strings.TrimRight(basePath, "/")
	if pathPrefix == "" {
		pathPrefix = "/telegram/webapp"
	}
	router.Route(pathPrefix+"/group-orders", func(r chi.Router) {
		r.Post("/", func(w http.ResponseWriter, req *http.Request) {
			handleWebAppGroupOrderCreate(w, req, cfg, firestoreClient, orderHTTPClient)
		})
		r.Get("/join/{joinCode}", func(w http.ResponseWriter, req *http.Request) {
			handleWebAppGroupOrderLookup(w, req, cfg, orderHTTPClient)
		})
		r.Get("/{groupOrderId}", func(w http.ResponseWriter, req *http.Request) {
			handleWebAppGroupOrderGet(w, req, cfg, orderHTTPClient)
		})
		r.Post("/{groupOrderId}/join", func(w http.ResponseWriter, req *http.Request) {
			handleWebAppGroupOrderJoin(w, req, cfg, firestoreClient, orderHTTPClient)
		})
		r.Post("/{groupOrderId}/items", func(w http.ResponseWriter, req *http.Request) {
			handleWebAppGroupOrderAddItems(w, req, cfg, firestoreClient, orderHTTPClient)
		})
		r.Post("/{groupOrderId}/invites", func(w http.ResponseWriter, req *http.Request) {
			handleWebAppGroupOrderInviteCreate(w, req, cfg, firestoreClient, orderHTTPClient)
		})
		r.Post("/{groupOrderId}/lock", func(w http.ResponseWriter, req *http.Request) {
			handleWebAppGroupOrderLock(w, req, cfg, firestoreClient, orderHTTPClient)
		})
		r.Post("/{groupOrderId}/checkout", func(w http.ResponseWriter, req *http.Request) {
			handleWebAppGroupOrderCheckout(w, req, cfg, firestoreClient, orderHTTPClient, paymentsHTTPClient)
		})
		r.Post("/{groupOrderId}/submit", func(w http.ResponseWriter, req *http.Request) {
			handleWebAppGroupOrderSubmit(w, req, cfg, firestoreClient, orderHTTPClient)
		})
	})
}
