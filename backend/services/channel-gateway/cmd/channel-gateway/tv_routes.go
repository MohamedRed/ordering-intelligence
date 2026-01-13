package main

import (
	"net/http"

	cloudfirestore "cloud.google.com/go/firestore"
	"github.com/go-chi/chi/v5"
)

func registerTvRoutes(
	router chi.Router,
	cfg *serviceConfig,
	firestoreClient *cloudfirestore.Client,
) {
	router.Get("/tv/pair", func(w http.ResponseWriter, r *http.Request) {
		handleTvPairLanding(w, r)
	})
	router.Post("/tv/pair/start", func(w http.ResponseWriter, r *http.Request) {
		handleTvPairStart(w, r, cfg, firestoreClient)
	})
	router.Get("/tv/pair/state", func(w http.ResponseWriter, r *http.Request) {
		handleTvPairState(w, r, firestoreClient)
	})
	router.Post("/tv/pair/complete", func(w http.ResponseWriter, r *http.Request) {
		handleTvPairComplete(w, r, cfg, firestoreClient)
	})
	router.Get("/tv/session", func(w http.ResponseWriter, r *http.Request) {
		handleTvSessionGet(w, r, cfg, firestoreClient)
	})
	router.Delete("/tv/session", func(w http.ResponseWriter, r *http.Request) {
		handleTvSessionEnd(w, r, firestoreClient)
	})
	router.Get("/tv/reorders", func(w http.ResponseWriter, r *http.Request) {
		handleTvReorders(w, r, cfg, firestoreClient)
	})
}
