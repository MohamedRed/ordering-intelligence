package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"

	cloudtasks "cloud.google.com/go/cloudtasks/apiv2"
	cloudfirestore "cloud.google.com/go/firestore"
	cloudpubsub "cloud.google.com/go/pubsub"
	"golang.org/x/oauth2"
	"google.golang.org/api/iterator"
	taskspb "google.golang.org/genproto/googleapis/cloud/tasks/v2"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"google.golang.org/protobuf/types/known/timestamppb"
)

type marketplaceConfig struct {
	OfferCents        int64
	InitialRadiusM    int
	ExpandRadiusM     int
	MaxRadiusM        int
	OfferTTLSeconds   int
	PrewarmTTLSeconds int
}

func fetchMarketplaceConfig(ctx context.Context, fs *cloudfirestore.Client, storeID string) marketplaceConfig {
	cfg := marketplaceConfig{
		OfferCents:        300,
		InitialRadiusM:    marketplaceDefaultInitialRadiusMeters,
		ExpandRadiusM:     marketplaceDefaultExpandRadiusMeters,
		MaxRadiusM:        marketplaceDefaultMaxRadiusMeters,
		OfferTTLSeconds:   marketplaceDefaultOfferTTLSeconds,
		PrewarmTTLSeconds: marketplaceDefaultPrewarmTTLSeconds,
	}
	if fs == nil || storeID == "" {
		return cfg
	}
	doc, err := fs.Collection(storesCollection).Doc(storeID).Get(ctx)
	if err != nil {
		return cfg
	}
	data := doc.Data()
	settings, _ := data["delivery_settings"].(map[string]any)
	if settings == nil {
		if alt, ok := data["deliverySettings"].(map[string]any); ok {
			settings = alt
		}
	}
	if settings == nil {
		return cfg
	}
	if v := toInt(settings["marketplace_offer_cents"]); v > 0 {
		cfg.OfferCents = v
	}
	if v := toInt(settings["marketplace_initial_radius_m"]); v > 0 {
		cfg.InitialRadiusM = v
	}
	if v := toInt(settings["marketplace_expand_radius_m"]); v > 0 {
		cfg.ExpandRadiusM = v
	}
	if v := toInt(settings["marketplace_max_radius_m"]); v > 0 {
		cfg.MaxRadiusM = v
	}
	if v := toInt(settings["marketplace_offer_ttl_seconds"]); v > 0 {
		cfg.OfferTTLSeconds = v
	}
	if v := toInt(settings["marketplace_prewarm_ttl_seconds"]); v > 0 {
		cfg.PrewarmTTLSeconds = v
	}
	return cfg
}

func prewarmMarketplaceOffer(
	ctx context.Context,
	fs *cloudfirestore.Client,
	cfg *serviceConfig,
	pubsubClient *cloudpubsub.Client,
	storeID string,
	storeLoc *storeDeliveryLocation,
	dropoff *deliveryLatLng,
	address *deliveryAddress,
) ([]string, error) {
	deliverers, err := listActiveMarketplaceDeliverers(ctx, fs, cfg.MarketplaceCandidateLimit)
	if err != nil {
		return nil, err
	}
	settings := fetchMarketplaceConfig(ctx, fs, storeID)
	candidates := findMarketplaceCandidates(
		deliverers,
		storeLoc.Lat,
		storeLoc.Lng,
		settings.InitialRadiusM,
		settings.ExpandRadiusM,
		settings.MaxRadiusM,
		cfg.MarketplaceCandidateLimit,
	)
	candidateIDs := make([]string, 0, len(candidates))
	for _, c := range candidates {
		candidateIDs = append(candidateIDs, c.Deliverer.DelivererID)
	}

	offerID := fs.Collection(marketplaceOffersCollection).NewDoc().ID
	offer := marketplaceOffer{
		OfferID:        offerID,
		StoreID:        storeID,
		Status:         marketplaceOfferStatusPrewarm,
		PayoutCents:    settings.OfferCents,
		Currency:       marketplaceDefaultCurrency,
		DropoffLatLng:  dropoff,
		DropoffAddress: address,
		CandidateIDs:   candidateIDs,
		ExpiresAt:      time.Now().UTC().Add(time.Duration(settings.PrewarmTTLSeconds) * time.Second),
		CreatedAt:      time.Now().UTC(),
		UpdatedAt:      time.Now().UTC(),
	}
	_ = createMarketplaceOffer(ctx, fs, offer)

	for _, delivererID := range candidateIDs {
		_ = publishDispatchEvent(ctx, pubsubClient, cfg, dispatchEvent{
			Kind:      "marketplace_prewarm",
			StoreID:   storeID,
			DriverID:  delivererID,
			CreatedAt: time.Now().UTC().Format(time.RFC3339),
			Payload: map[string]any{
				"offerId": offerID,
			},
		})
	}
	return candidateIDs, nil
}

func createMarketplaceOfferForOrder(
	ctx context.Context,
	fs *cloudfirestore.Client,
	cfg *serviceConfig,
	pubsubClient *cloudpubsub.Client,
	tasksClient *cloudtasks.Client,
	order orderRecord,
) (*marketplaceOffer, error) {
	if fs == nil {
		return nil, fmt.Errorf("firestore_not_configured")
	}
	if existing, err := findMarketplaceOfferByOrderID(ctx, fs, order.ID); err == nil && existing != nil {
		return existing, nil
	}
	storeID := strings.TrimSpace(order.StoreID)
	if storeID == "" {
		return nil, fmt.Errorf("missing_store_id")
	}
	storeLoc, err := fetchStoreLocation(ctx, fs, storeID)
	if err != nil {
		return nil, err
	}
	settings := fetchMarketplaceConfig(ctx, fs, storeID)
	payoutCents := settings.OfferCents
	if order.Delivery != nil && order.Delivery.OfferCents > 0 {
		payoutCents = order.Delivery.OfferCents
	}
	deliverers, err := listActiveMarketplaceDeliverers(ctx, fs, cfg.MarketplaceCandidateLimit)
	if err != nil {
		return nil, err
	}
	candidates := findMarketplaceCandidates(
		deliverers,
		storeLoc.Lat,
		storeLoc.Lng,
		settings.InitialRadiusM,
		settings.ExpandRadiusM,
		settings.MaxRadiusM,
		cfg.MarketplaceCandidateLimit,
	)
	candidateIDs := make([]string, 0, len(candidates))
	for _, c := range candidates {
		candidateIDs = append(candidateIDs, c.Deliverer.DelivererID)
	}

	offerID := fs.Collection(marketplaceOffersCollection).NewDoc().ID
	now := time.Now().UTC()
	offer := marketplaceOffer{
		OfferID:        offerID,
		OrderID:        order.ID,
		StoreID:        storeID,
		Status:         marketplaceOfferStatusOpen,
		PayoutCents:    payoutCents,
		Currency:       marketplaceDefaultCurrency,
		DropoffLatLng:  order.Delivery.DropoffLatLng,
		DropoffAddress: order.Delivery.DropoffAddress,
		Instructions:   order.Delivery.Instructions,
		CandidateIDs:   candidateIDs,
		ExpiresAt:      now.Add(time.Duration(settings.OfferTTLSeconds) * time.Second),
		CreatedAt:      now,
		UpdatedAt:      now,
	}
	if err := createMarketplaceOffer(ctx, fs, offer); err != nil {
		return nil, err
	}

	for _, delivererID := range candidateIDs {
		_ = publishDispatchEvent(ctx, pubsubClient, cfg, dispatchEvent{
			Kind:      "marketplace_offer",
			StoreID:   storeID,
			OrderID:   order.ID,
			DriverID:  delivererID,
			CreatedAt: now.Format(time.RFC3339),
			Payload: map[string]any{
				"offerId": offerID,
				"payout":  settings.OfferCents,
			},
		})
	}

	_ = enqueueMarketplaceFinalize(ctx, tasksClient, cfg, offerID, offer.ExpiresAt)
	return &offer, nil
}

func finalizeMarketplaceOffer(
	ctx context.Context,
	fs *cloudfirestore.Client,
	cfg *serviceConfig,
	pubsubClient *cloudpubsub.Client,
	httpClient *http.Client,
	orderTokenSrc oauth2.TokenSource,
	offerID string,
) error {
	offer, err := fetchMarketplaceOffer(ctx, fs, offerID)
	if err != nil {
		return err
	}
	if offer == nil {
		return nil
	}
	if offer.Status != marketplaceOfferStatusOpen {
		return nil
	}
	if time.Now().UTC().After(offer.ExpiresAt) == false {
		return nil
	}
	acceptances, err := listMarketplaceAcceptances(ctx, fs, offerID)
	if err != nil {
		return err
	}
	if len(acceptances) == 0 {
		offer.Status = marketplaceOfferStatusExpired
		offer.UpdatedAt = time.Now().UTC()
		return updateMarketplaceOffer(ctx, fs, *offer)
	}
	best := selectBestAcceptance(ctx, fs, offer, acceptances)
	if best == nil {
		offer.Status = marketplaceOfferStatusExpired
		offer.UpdatedAt = time.Now().UTC()
		return updateMarketplaceOffer(ctx, fs, *offer)
	}

	offer.Status = marketplaceOfferStatusAssigned
	offer.SelectedDeliverer = best.DelivererID
	offer.UpdatedAt = time.Now().UTC()
	if err := updateMarketplaceOffer(ctx, fs, *offer); err != nil {
		return err
	}

	deliverer, _ := fetchMarketplaceDeliverer(ctx, fs, best.DelivererID)
	if deliverer != nil {
		deliverer.CurrentOrderID = offer.OrderID
		deliverer.Available = false
		deliverer.Status = marketplaceDelivererStatusUnavailable
		deliverer.UpdatedAt = time.Now().UTC()
		_ = upsertMarketplaceDeliverer(ctx, fs, *deliverer)
	}

	if offer.OrderID != "" {
		_ = patchOrderDelivery(ctx, httpClient, orderTokenSrc, cfg.OrderServiceURL, offer.OrderID, map[string]any{
			"assignedDriverId":      best.DelivererID,
			"assignmentStatus":      "assigned",
			"deliveryStatusSummary": "delivery_assigned",
			"offerCents":            offer.PayoutCents,
		})
		_ = publishDispatchEvent(ctx, pubsubClient, cfg, dispatchEvent{
			Kind:      "driver_assigned",
			StoreID:   offer.StoreID,
			OrderID:   offer.OrderID,
			DriverID:  best.DelivererID,
			CreatedAt: time.Now().UTC().Format(time.RFC3339),
			Payload: map[string]any{
				"offerId": offerID,
			},
		})
	}
	return nil
}

func selectBestAcceptance(
	ctx context.Context,
	fs *cloudfirestore.Client,
	offer *marketplaceOffer,
	acceptances []marketplaceOfferAcceptance,
) *marketplaceOfferAcceptance {
	if offer == nil || len(acceptances) == 0 {
		return nil
	}
	best := acceptances[0]
	bestScore := acceptanceScore(ctx, fs, offer, best)
	for _, acc := range acceptances[1:] {
		score := acceptanceScore(ctx, fs, offer, acc)
		if score < bestScore {
			bestScore = score
			best = acc
		}
	}
	return &best
}

func acceptanceScore(
	ctx context.Context,
	fs *cloudfirestore.Client,
	offer *marketplaceOffer,
	acc marketplaceOfferAcceptance,
) float64 {
	deliverer, _ := fetchMarketplaceDeliverer(ctx, fs, acc.DelivererID)
	distance := acc.DistanceMeters
	if distance == 0 && deliverer != nil && offer.DropoffLatLng != nil {
		distance = haversineMeters(deliverer.Lat, deliverer.Lng, offer.DropoffLatLng.Lat, offer.DropoffLatLng.Lng)
	}
	now := time.Now().UTC()
	if deliverer == nil {
		return distance
	}
	return scoreMarketplaceDistance(*deliverer, distance, now)
}

func enqueueMarketplaceFinalize(
	ctx context.Context,
	client *cloudtasks.Client,
	cfg *serviceConfig,
	offerID string,
	expiresAt time.Time,
) error {
	if client == nil {
		return nil
	}
	projectID := strings.TrimSpace(cfg.CloudTasksProjectID)
	location := strings.TrimSpace(cfg.CloudTasksLocation)
	queue := strings.TrimSpace(cfg.CloudTasksAssignmentQueue)
	targetBase := strings.TrimSpace(cfg.DispatchServiceBaseURL)
	if targetBase == "" {
		targetBase = strings.TrimSpace(cfg.InternalAuthAudience)
	}
	oidcSA := strings.TrimSpace(cfg.CloudTasksOIDCServiceAccount)
	if projectID == "" || location == "" || queue == "" || targetBase == "" || oidcSA == "" {
		return nil
	}
	audience := strings.TrimSpace(cfg.CloudTasksOIDCAudience)
	if audience == "" {
		audience = targetBase
	}

	safeID := sanitizeTaskID("marketplace-" + offerID)
	taskName := fmt.Sprintf("projects/%s/locations/%s/queues/%s/tasks/marketplace-finalize-%s", projectID, location, queue, safeID)
	parent := fmt.Sprintf("projects/%s/locations/%s/queues/%s", projectID, location, queue)

	body, _ := json.Marshal(map[string]string{
		"offerId": offerID,
	})
	schedule := expiresAt
	if schedule.Before(time.Now().UTC()) {
		schedule = time.Now().UTC().Add(2 * time.Second)
	}

	req := &taskspb.CreateTaskRequest{
		Parent: parent,
		Task: &taskspb.Task{
			Name: taskName,
			ScheduleTime: &timestamppb.Timestamp{
				Seconds: schedule.Unix(),
			},
			MessageType: &taskspb.Task_HttpRequest{
				HttpRequest: &taskspb.HttpRequest{
					HttpMethod: taskspb.HttpMethod_POST,
					Url:        strings.TrimRight(targetBase, "/") + "/tasks/marketplace/offers/" + offerID + "/finalize",
					Headers:    map[string]string{"Content-Type": "application/json"},
					Body:       body,
					AuthorizationHeader: &taskspb.HttpRequest_OidcToken{
						OidcToken: &taskspb.OidcToken{
							ServiceAccountEmail: oidcSA,
							Audience:            audience,
						},
					},
				},
			},
		},
	}
	_, err := client.CreateTask(ctx, req)
	if err != nil {
		if status.Code(err) == codes.AlreadyExists {
			return nil
		}
		return err
	}
	return nil
}
