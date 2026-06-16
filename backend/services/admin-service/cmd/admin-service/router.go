package main

import (
	"context"
	"net/http"

	cloudfirestore "cloud.google.com/go/firestore"
	"firebase.google.com/go/v4/auth"
	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
)

func newRouter(
	ctx context.Context,
	cfg *serviceConfig,
	firestoreClient *cloudfirestore.Client,
	authClient *auth.Client,
) http.Handler {
	router := chi.NewRouter()
	router.Use(middleware.RequestID)
	router.Use(middleware.Logger)
	router.Use(middleware.Recoverer)
	router.Use(corsMiddleware(cfg.CORSOrigins))
	if cfg.RequireAuth && authClient != nil {
		router.Use(firebaseAuthMiddleware(authClient))
	}

	registerHealthRoutes(router, cfg)
	registerTenantRoutes(router, ctx, firestoreClient)
	registerChannelRouteRoutes(router, ctx, firestoreClient)
	registerDemoRoutes(router, firestoreClient)

	return router
}
