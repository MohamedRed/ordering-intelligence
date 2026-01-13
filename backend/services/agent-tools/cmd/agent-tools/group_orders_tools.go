package main

import (
	"net/http"

	"github.com/go-chi/chi/v5"
	"golang.org/x/oauth2"
)

func registerGroupOrderTools(
	r chi.Router,
	cfg *serviceConfig,
	httpClient *http.Client,
	orderTokenSrc oauth2.TokenSource,
	paymentsTokenSrc oauth2.TokenSource,
) {
	registerGroupOrderReadTools(r, cfg, httpClient, orderTokenSrc)
	registerGroupOrderWriteTools(r, cfg, httpClient, orderTokenSrc, paymentsTokenSrc)
}
