package main

import (
	"net/http"

	cloudfirestore "cloud.google.com/go/firestore"
	cloudpubsub "cloud.google.com/go/pubsub"
	"github.com/go-chi/chi/v5"
)

func registerGroupOrderRoutes(
	router chi.Router,
	firestoreClient *cloudfirestore.Client,
	pubsubClient *cloudpubsub.Client,
	cfg *serviceConfig,
) {
	router.Route("/group_orders", func(r chi.Router) {
		r.Post("/", func(w http.ResponseWriter, req *http.Request) {
			handleGroupOrderCreate(w, req, firestoreClient, cfg)
		})
		r.Get("/join/{joinCode}", func(w http.ResponseWriter, req *http.Request) {
			handleGroupOrderLookup(w, req, firestoreClient, cfg)
		})
		r.Get("/{groupOrderId}", func(w http.ResponseWriter, req *http.Request) {
			handleGroupOrderGet(w, req, firestoreClient, cfg)
		})
		r.Post("/{groupOrderId}/join", func(w http.ResponseWriter, req *http.Request) {
			handleGroupOrderJoin(w, req, firestoreClient, cfg)
		})
		r.Post("/{groupOrderId}/items", func(w http.ResponseWriter, req *http.Request) {
			handleGroupOrderAddItems(w, req, firestoreClient, cfg)
		})
		r.Post("/{groupOrderId}/invites", func(w http.ResponseWriter, req *http.Request) {
			handleGroupOrderInviteCreate(w, req, firestoreClient, cfg)
		})
		r.Post("/{groupOrderId}/lock", func(w http.ResponseWriter, req *http.Request) {
			handleGroupOrderLock(w, req, firestoreClient, cfg)
		})
		r.Post("/{groupOrderId}/submit", func(w http.ResponseWriter, req *http.Request) {
			handleGroupOrderSubmit(w, req, firestoreClient, pubsubClient, cfg)
		})
		r.Post("/{groupOrderId}/refund", func(w http.ResponseWriter, req *http.Request) {
			groupID := chi.URLParam(req, "groupOrderId")
			if groupID == "" {
				writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_group_order_id"})
				return
			}
			handleGroupOrderRefund(req.Context(), firestoreClient, cfg, w, req, groupID)
		})
	})
}
