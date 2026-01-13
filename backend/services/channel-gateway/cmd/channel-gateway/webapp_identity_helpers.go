package main

import (
	"context"
	"log"
	"strings"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
)

func resolveCustomerID(
	ctx context.Context,
	cfg *serviceConfig,
	channel string,
	userID string,
	displayName string,
	tenantID string,
	seen customerResolveContext,
) (string, error) {
	base := strings.TrimSpace(cfg.CustomerProfileServiceURL)
	if base == "" || strings.TrimSpace(userID) == "" {
		return "", nil
	}
	seen = normalizeCustomerResolveContext(channel, seen)
	resp, err := resolveCustomerProfile(ctx, base, customerProfileResolveRequest{
		TenantID:    strings.TrimSpace(tenantID),
		Channel:     strings.TrimSpace(channel),
		UserID:      strings.TrimSpace(userID),
		DisplayName: strings.TrimSpace(displayName),
		AllowCreate: true,
		StoreID:     seen.StoreID,
		Platform:    seen.Platform,
		Provider:    seen.Provider,
	})
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(resp.CustomerID), nil
}

type customerResolveContext struct {
	StoreID  string
	Platform string
	Provider string
}

func normalizeCustomerResolveContext(channel string, ctx customerResolveContext) customerResolveContext {
	ctx.StoreID = strings.TrimSpace(ctx.StoreID)
	ctx.Platform = strings.TrimSpace(strings.ToLower(ctx.Platform))
	ctx.Provider = strings.TrimSpace(strings.ToLower(ctx.Provider))
	if ctx.Provider == "" {
		ctx.Provider = normalizeProviderFromChannel(channel)
	}
	return ctx
}

func loadSessionWithCustomer(
	ctx context.Context,
	cfg *serviceConfig,
	firestoreClient *cloudfirestore.Client,
	sessionID string,
) (channelSession, error) {
	session, err := loadSessionByID(ctx, firestoreClient, sessionID)
	if err != nil {
		return channelSession{}, err
	}
	if session.CustomerID != "" {
		return session, nil
	}
	platform := strings.TrimSpace(session.ClientPlatform)
	if platform == "" {
		platform = "web"
	}
	customerID, err := resolveCustomerID(ctx, cfg, session.Channel, session.UserID, session.DisplayName, session.TenantID, customerResolveContext{
		StoreID:  session.StoreID,
		Platform: platform,
		Provider: strings.TrimSpace(session.AuthProvider),
	})
	if err != nil {
		log.Printf("customer-profile resolve failed: %v", err)
		return session, nil
	}
	if customerID == "" {
		return session, nil
	}
	session.CustomerID = customerID
	session.LastSeenAt = time.Now().UTC()
	if err := upsertSession(ctx, firestoreClient, session); err != nil {
		log.Printf("session update failed: %v", err)
		return session, nil
	}
	return session, nil
}
