package main

import (
	"context"
	"errors"
	"fmt"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
	"google.golang.org/api/iterator"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

type auditRecord struct {
	Action     string    `firestore:"action"`
	TenantID   string    `firestore:"tenantId"`
	Actor      string    `firestore:"actor"`
	OccurredAt time.Time `firestore:"occurredAt"`
}

var errTenantNotFound = errors.New("tenant_not_found")

func listTenants(ctx context.Context, client *cloudfirestore.Client) ([]tenant, error) {
	snapshots, err := client.Collection(tenantsCollection).Documents(ctx).GetAll()
	if err != nil {
		return nil, err
	}

	result := make([]tenant, 0, len(snapshots))
	for _, snap := range snapshots {
		var entry tenant
		if err := snap.DataTo(&entry); err != nil {
			return nil, err
		}
		result = append(result, entry)
	}
	return result, nil
}

func createTenant(ctx context.Context, client *cloudfirestore.Client, record tenant) error {
	doc := client.Collection(tenantsCollection).Doc(record.ID)
	_, err := doc.Create(ctx, record)
	return err
}

func fetchTenant(ctx context.Context, client *cloudfirestore.Client, tenantID string) (*tenant, error) {
	snapshot, err := client.Collection(tenantsCollection).Doc(tenantID).Get(ctx)
	if err != nil {
		if status.Code(err) == codes.NotFound {
			return nil, errTenantNotFound
		}
		return nil, err
	}

	var entry tenant
	if err := snapshot.DataTo(&entry); err != nil {
		return nil, err
	}
	return &entry, nil
}

func logAudit(ctx context.Context, client *cloudfirestore.Client, action string, tenantID string, actor string) error {
	record := auditRecord{
		Action:     action,
		TenantID:   tenantID,
		Actor:      actor,
		OccurredAt: time.Now().UTC(),
	}
	_, _, err := client.Collection("audits").Add(ctx, record)
	return err
}

func updateTenantFlags(ctx context.Context, client *cloudfirestore.Client, tenantID string, flags map[string]bool) (*tenant, error) {
	docRef := client.Collection(tenantsCollection).Doc(tenantID)
	_, err := docRef.Get(ctx)
	if err != nil {
		if status.Code(err) == codes.NotFound {
			return nil, errTenantNotFound
		}
		return nil, err
	}
	if flags == nil {
		flags = map[string]bool{}
	}
	if _, err := docRef.Update(ctx, []cloudfirestore.Update{{Path: "featureFlags", Value: flags}, {Path: "updatedAt", Value: time.Now().UTC()}}); err != nil {
		return nil, err
	}
	return fetchTenant(ctx, client, tenantID)
}

func listChannelRoutes(ctx context.Context, client *cloudfirestore.Client) ([]map[string]any, error) {
	iter := client.Collection(channelRoutesCollection).Documents(ctx)
	defer iter.Stop()

	var routes []map[string]any
	for {
		doc, err := iter.Next()
		if err != nil {
			if errors.Is(err, iterator.Done) {
				break
			}
			return nil, err
		}
		data := doc.Data()
		data["id"] = doc.Ref.ID
		routes = append(routes, data)
	}
	return routes, nil
}

func defaultStatus(statusValue string) string {
	if statusValue == "" {
		return "active"
	}
	return statusValue
}

func generateTenantID() string {
	return fmt.Sprintf("tenant-%d", time.Now().UTC().UnixNano())
}
