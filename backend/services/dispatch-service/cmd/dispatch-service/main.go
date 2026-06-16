package main

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"math"
	"net/http"
	"net/url"
	"os"
	"sort"
	"strconv"
	"strings"
	"sync/atomic"
	"time"

	cloudtasks "cloud.google.com/go/cloudtasks/apiv2"
	cloudfirestore "cloud.google.com/go/firestore"
	cloudpubsub "cloud.google.com/go/pubsub"
	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/auth"
	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/joho/godotenv"
	sharedconfig "github.com/ordering-intelligence/sharedconfig"
	"golang.org/x/oauth2"
	"google.golang.org/api/idtoken"
	"google.golang.org/api/iterator"
	"google.golang.org/api/option"
	taskspb "google.golang.org/genproto/googleapis/cloud/tasks/v2"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"google.golang.org/protobuf/types/known/timestamppb"
)

type ctxKey string

const authContextKey ctxKey = "auth_ctx"

const (
	defaultPort = "8080"

	storesCollection         = "stores"
	driversSubcollection     = "drivers"
	shiftsSubcollection      = "driver_shifts"
	locationsSubcollection   = "driver_locations"
	routesSubcollection      = "driver_routes"
	assignmentsSubcollection = "driver_assignments"
	dispatchDedupCollection  = "dispatch_assignments_dedup"
)

type serviceConfig struct {
	Port               string
	Environment        string
	FirestoreProjectID string
	CredentialsFile    string
	RequireAuth        bool
	CORSOrigins        []string

	InternalAuthAudience  string
	InternalAllowedEmails []string

	OrderServiceURL           string
	DispatchEventsTopic       string
	RadarAPIKey               string
	AssignmentTTLSeconds      int
	TopKCandidates            int
	MarketplaceCandidateLimit int

	CloudTasksProjectID          string
	CloudTasksLocation           string
	CloudTasksAssignmentQueue    string
	CloudTasksOIDCServiceAccount string
	CloudTasksOIDCAudience       string
	DispatchServiceBaseURL       string
}

type authContext struct {
	UID      string
	Role     string
	StoreIDs []string
}

type tokenVerifier interface {
	VerifyIDToken(ctx context.Context, idToken string) (*auth.Token, error)
}

type pubsubPushEnvelope struct {
	Message struct {
		Data      string            `json:"data"`
		MessageID string            `json:"messageId"`
		Attrs     map[string]string `json:"attributes"`
	} `json:"message"`
	Subscription string `json:"subscription"`
}

type deliveryLatLng struct {
	Lat float64 `json:"lat"`
	Lng float64 `json:"lng"`
}

type deliveryAddress struct {
	Line1      string `json:"line1,omitempty"`
	Line2      string `json:"line2,omitempty"`
	City       string `json:"city,omitempty"`
	State      string `json:"state,omitempty"`
	PostalCode string `json:"postalCode,omitempty"`
	Country    string `json:"country,omitempty"`
	Formatted  string `json:"formatted,omitempty"`
}

type orderDelivery struct {
	FleetMode      string           `json:"fleetMode,omitempty"`
	DropoffLatLng  *deliveryLatLng  `json:"dropoffLatLng,omitempty"`
	DropoffAddress *deliveryAddress `json:"dropoffAddress,omitempty"`
	Instructions   string           `json:"instructions,omitempty"`
	OfferCents     int64            `json:"offerCents,omitempty"`
	TrackingURL    string           `json:"trackingUrl,omitempty"`
}

type orderRecord struct {
	ID              string         `json:"id"`
	StoreID         string         `json:"storeId"`
	Status          string         `json:"status"`
	FulfillmentType string         `json:"fulfillmentType"`
	Delivery        *orderDelivery `json:"delivery,omitempty"`
	CreatedAt       time.Time      `json:"createdAt"`
}

type storeDeliveryLocation struct {
	Lat float64 `json:"lat"`
	Lng float64 `json:"lng"`
}

type storeDeliverySettings struct {
	Enabled       bool                   `json:"enabled"`
	FleetMode     string                 `json:"fleet_mode"`
	StoreLocation *storeDeliveryLocation `json:"store_location"`
}

type driverRecord struct {
	DisplayName    string    `json:"displayName" firestore:"displayName"`
	PhoneE164      string    `json:"phoneE164" firestore:"phoneE164"`
	Active         bool      `json:"active" firestore:"active"`
	UID            string    `json:"uid,omitempty" firestore:"uid,omitempty"`
	MaxActiveStops int       `json:"maxActiveStops,omitempty" firestore:"maxActiveStops,omitempty"`
	CreatedAt      time.Time `json:"createdAt" firestore:"createdAt"`
	UpdatedAt      time.Time `json:"updatedAt" firestore:"updatedAt"`
}

type driverShift struct {
	DriverID  string    `json:"driverId" firestore:"driverId"`
	Status    string    `json:"status" firestore:"status"` // on_shift|paused|off_shift
	StartedAt time.Time `json:"startedAt,omitempty" firestore:"startedAt,omitempty"`
	UpdatedAt time.Time `json:"updatedAt" firestore:"updatedAt"`
}

type driverLocation struct {
	Lat        float64   `json:"lat" firestore:"lat"`
	Lng        float64   `json:"lng" firestore:"lng"`
	AccuracyM  float64   `json:"accuracyM" firestore:"accuracyM"`
	RecordedAt time.Time `json:"recordedAt" firestore:"recordedAt"`
	ExpiresAt  time.Time `json:"expiresAt" firestore:"expiresAt"`
}

type assignmentCandidate struct {
	DriverID        string `json:"driverId" firestore:"driverId"`
	EtaToPickupSecs int    `json:"etaToPickupSecs" firestore:"etaToPickupSecs"`
}

type driverAssignment struct {
	AssignmentID string                `json:"assignmentId" firestore:"assignmentId"`
	OrderID      string                `json:"orderId" firestore:"orderId"`
	DriverID     string                `json:"driverId,omitempty" firestore:"driverId,omitempty"`
	Status       string                `json:"status" firestore:"status"` // pending|assigned|declined|expired
	Candidates   []assignmentCandidate `json:"candidates,omitempty" firestore:"candidates,omitempty"`
	CandidateIdx int                   `json:"candidateIdx" firestore:"candidateIdx"`
	ExpiresAt    time.Time             `json:"expiresAt" firestore:"expiresAt"`
	CreatedAt    time.Time             `json:"createdAt" firestore:"createdAt"`
	UpdatedAt    time.Time             `json:"updatedAt" firestore:"updatedAt"`
}

type driverRoute struct {
	RouteID     string    `json:"routeId" firestore:"routeId"`
	DriverID    string    `json:"driverId" firestore:"driverId"`
	DeliveryIDs []string  `json:"deliveryIds" firestore:"deliveryIds"`
	Status      string    `json:"status" firestore:"status"` // planned|in_progress|completed|cancelled
	CreatedAt   time.Time `json:"createdAt" firestore:"createdAt"`
	UpdatedAt   time.Time `json:"updatedAt" firestore:"updatedAt"`
}

type dispatchEvent struct {
	Kind         string         `json:"kind"`
	StoreID      string         `json:"storeId"`
	OrderID      string         `json:"orderId,omitempty"`
	AssignmentID string         `json:"assignmentId,omitempty"`
	DriverID     string         `json:"driverId,omitempty"`
	RouteID      string         `json:"routeId,omitempty"`
	CreatedAt    string         `json:"createdAt"`
	Payload      map[string]any `json:"payload,omitempty"`
}

var assignmentsCreatedCounter uint64

func main() {
	_ = godotenv.Load()

	cfg, err := loadConfig()
	if err != nil {
		log.Fatalf("failed loading config: %v", err)
	}

	ctx := context.Background()
	fs, err := newFirestoreClient(ctx, cfg)
	if err != nil {
		log.Fatalf("failed to create firestore client: %v", err)
	}
	defer fs.Close()

	var authClient *auth.Client
	if cfg.RequireAuth {
		authClient, err = newFirebaseAuthClient(ctx, cfg)
		if err != nil {
			log.Fatalf("failed to create firebase auth client: %v", err)
		}
	}

	pubsubClient, err := cloudpubsub.NewClient(ctx, cfg.FirestoreProjectID)
	if err != nil {
		log.Printf("pubsub client not initialised: %v", err)
		pubsubClient = nil
	}
	defer func() {
		if pubsubClient != nil {
			_ = pubsubClient.Close()
		}
	}()

	var tasksClient *cloudtasks.Client
	if cfg.CloudTasksProjectID != "" && cfg.CloudTasksLocation != "" && cfg.CloudTasksAssignmentQueue != "" {
		tc, err := cloudtasks.NewClient(ctx)
		if err != nil {
			log.Printf("cloud tasks client not initialised: %v", err)
		} else {
			tasksClient = tc
			defer func() { _ = tasksClient.Close() }()
		}
	}

	httpClient := &http.Client{Timeout: 20 * time.Second}
	var orderTokenSrc oauth2.TokenSource
	if strings.TrimSpace(cfg.OrderServiceURL) != "" {
		ts, err := idtoken.NewTokenSource(ctx, cfg.OrderServiceURL)
		if err != nil {
			log.Printf("order-service token source not initialised: %v", err)
		} else {
			orderTokenSrc = ts
		}
	}

	router := chi.NewRouter()
	router.Use(middleware.RequestID)
	router.Use(middleware.Logger)
	router.Use(middleware.Recoverer)
	router.Use(dispatchCORSMiddleware(cfg.CORSOrigins))

	router.Get("/healthz", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, map[string]any{
			"status":      "ok",
			"service":     "dispatch-service",
			"environment": cfg.Environment,
		})
	})

	router.Get("/metrics", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/plain; version=0.0.4")
		_, _ = fmt.Fprintf(w, "dispatch_assignments_created_total %d\n", atomic.LoadUint64(&assignmentsCreatedCounter))
	})

	// Pub/Sub push endpoint for orders-events (invocation protected by Cloud Run IAM).
	router.Post("/tasks/orders-events", func(w http.ResponseWriter, r *http.Request) {
		handleOrdersEvents(w, r, fs, cfg, pubsubClient, tasksClient, httpClient, orderTokenSrc)
	})
	router.Post("/tasks/assignments/expire", func(w http.ResponseWriter, r *http.Request) {
		handleAssignmentExpiry(w, r, fs, cfg, pubsubClient, tasksClient, httpClient, orderTokenSrc)
	})
	router.Post("/tasks/marketplace/offers/{offerId}/finalize", func(w http.ResponseWriter, r *http.Request) {
		offerID := strings.TrimSpace(chi.URLParam(r, "offerId"))
		if offerID == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_offer_id"})
			return
		}
		handleMarketplaceFinalize(w, r, fs, cfg, pubsubClient, httpClient, orderTokenSrc, offerID)
	})

	router.Route("/v1", func(r chi.Router) {
		if cfg.RequireAuth {
			r.Use(firebaseOrInternalMiddleware(authClient, cfg.InternalAuthAudience, cfg.InternalAllowedEmails))
		}

		r.Post("/stores/{storeID}/quote", func(w http.ResponseWriter, r *http.Request) {
			storeID := strings.TrimSpace(chi.URLParam(r, "storeID"))
			if storeID == "" {
				writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_store_id"})
				return
			}
			if !canAccessStore(r.Context(), storeID) && !isDriverForStore(r.Context(), fs, storeID) {
				writeJSON(w, http.StatusForbidden, map[string]string{"error": "forbidden"})
				return
			}
			handleQuoteOwnedFleet(w, r, fs, cfg, storeID)
		})
		r.Post("/stores/{storeID}/routes/optimize", func(w http.ResponseWriter, r *http.Request) {
			storeID := strings.TrimSpace(chi.URLParam(r, "storeID"))
			if storeID == "" {
				writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_store_id"})
				return
			}
			if !canAccessStore(r.Context(), storeID) && !isDriverForStore(r.Context(), fs, storeID) {
				writeJSON(w, http.StatusForbidden, map[string]string{"error": "forbidden"})
				return
			}
			handleOptimizeRoute(w, r, cfg)
		})
		r.Post("/stores/{storeID}/routes/{routeID}/stops/{deliveryID}/status", func(w http.ResponseWriter, r *http.Request) {
			storeID := strings.TrimSpace(chi.URLParam(r, "storeID"))
			routeID := strings.TrimSpace(chi.URLParam(r, "routeID"))
			deliveryID := strings.TrimSpace(chi.URLParam(r, "deliveryID"))
			if storeID == "" || routeID == "" || deliveryID == "" {
				writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_ids"})
				return
			}
			if !isDriverForStore(r.Context(), fs, storeID) {
				writeJSON(w, http.StatusForbidden, map[string]string{"error": "forbidden"})
				return
			}
			updateStopStatus(w, r, fs, cfg, pubsubClient, httpClient, orderTokenSrc, storeID, routeID, deliveryID)
		})
		r.Post("/stores/{storeID}/marketplace/prewarm", func(w http.ResponseWriter, r *http.Request) {
			storeID := strings.TrimSpace(chi.URLParam(r, "storeID"))
			if storeID == "" {
				writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_store_id"})
				return
			}
			if !canAccessStore(r.Context(), storeID) {
				writeJSON(w, http.StatusForbidden, map[string]string{"error": "forbidden"})
				return
			}
			handleMarketplacePrewarm(w, r, fs, cfg, pubsubClient, storeID)
		})

		// Business-facing driver management.
		r.Route("/stores/{storeID}/drivers", func(rr chi.Router) {
			rr.Get("/", func(w http.ResponseWriter, r *http.Request) {
				storeID := strings.TrimSpace(chi.URLParam(r, "storeID"))
				if storeID == "" {
					writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_store_id"})
					return
				}
				if !canAccessStore(r.Context(), storeID) {
					writeJSON(w, http.StatusForbidden, map[string]string{"error": "forbidden"})
					return
				}
				listDrivers(w, r, fs, storeID)
			})
			rr.Post("/", func(w http.ResponseWriter, r *http.Request) {
				storeID := strings.TrimSpace(chi.URLParam(r, "storeID"))
				if storeID == "" {
					writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_store_id"})
					return
				}
				if !canAccessStore(r.Context(), storeID) {
					writeJSON(w, http.StatusForbidden, map[string]string{"error": "forbidden"})
					return
				}
				createDriver(w, r, fs, storeID)
			})
			rr.Patch("/{driverID}", func(w http.ResponseWriter, r *http.Request) {
				storeID := strings.TrimSpace(chi.URLParam(r, "storeID"))
				driverID := strings.TrimSpace(chi.URLParam(r, "driverID"))
				if storeID == "" || driverID == "" {
					writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_ids"})
					return
				}
				if !canAccessStore(r.Context(), storeID) {
					writeJSON(w, http.StatusForbidden, map[string]string{"error": "forbidden"})
					return
				}
				patchDriver(w, r, fs, storeID, driverID)
			})
		})

		// Driver endpoints (store-scoped for v1).
		r.Route("/stores/{storeID}/drivers/me", func(rr chi.Router) {
			rr.Post("/claim", func(w http.ResponseWriter, r *http.Request) {
				storeID := strings.TrimSpace(chi.URLParam(r, "storeID"))
				if storeID == "" {
					writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_store_id"})
					return
				}
				claimDriver(w, r, fs, storeID)
			})
			rr.Post("/shift/start", func(w http.ResponseWriter, r *http.Request) {
				storeID := strings.TrimSpace(chi.URLParam(r, "storeID"))
				if storeID == "" {
					writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_store_id"})
					return
				}
				updateShift(w, r, fs, storeID, "on_shift")
			})
			rr.Post("/shift/pause", func(w http.ResponseWriter, r *http.Request) {
				storeID := strings.TrimSpace(chi.URLParam(r, "storeID"))
				if storeID == "" {
					writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_store_id"})
					return
				}
				updateShift(w, r, fs, storeID, "paused")
			})
			rr.Post("/shift/end", func(w http.ResponseWriter, r *http.Request) {
				storeID := strings.TrimSpace(chi.URLParam(r, "storeID"))
				if storeID == "" {
					writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_store_id"})
					return
				}
				updateShift(w, r, fs, storeID, "off_shift")
			})
			rr.Post("/location", func(w http.ResponseWriter, r *http.Request) {
				storeID := strings.TrimSpace(chi.URLParam(r, "storeID"))
				if storeID == "" {
					writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_store_id"})
					return
				}
				postLocation(w, r, fs, storeID)
			})
			rr.Post("/assignments/{assignmentID}/accept", func(w http.ResponseWriter, r *http.Request) {
				storeID := strings.TrimSpace(chi.URLParam(r, "storeID"))
				assignmentID := strings.TrimSpace(chi.URLParam(r, "assignmentID"))
				if storeID == "" || assignmentID == "" {
					writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_ids"})
					return
				}
				acceptOrDecline(w, r, fs, cfg, pubsubClient, tasksClient, httpClient, orderTokenSrc, storeID, assignmentID, true)
			})
			rr.Post("/assignments/{assignmentID}/decline", func(w http.ResponseWriter, r *http.Request) {
				storeID := strings.TrimSpace(chi.URLParam(r, "storeID"))
				assignmentID := strings.TrimSpace(chi.URLParam(r, "assignmentID"))
				if storeID == "" || assignmentID == "" {
					writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_ids"})
					return
				}
				acceptOrDecline(w, r, fs, cfg, pubsubClient, tasksClient, httpClient, orderTokenSrc, storeID, assignmentID, false)
			})
			rr.Get("/routes/current", func(w http.ResponseWriter, r *http.Request) {
				storeID := strings.TrimSpace(chi.URLParam(r, "storeID"))
				if storeID == "" {
					writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_store_id"})
					return
				}
				getCurrentRoute(w, r, fs, storeID)
			})
		})

		// Marketplace deliverer endpoints (store-agnostic).
		r.Route("/marketplace", func(rr chi.Router) {
			rr.Post("/deliverers/me/register", func(w http.ResponseWriter, r *http.Request) {
				handleMarketplaceDelivererRegister(w, r, fs)
			})
			rr.Post("/deliverers/me/availability", func(w http.ResponseWriter, r *http.Request) {
				handleMarketplaceAvailability(w, r, fs)
			})
			rr.Post("/deliverers/me/location", func(w http.ResponseWriter, r *http.Request) {
				handleMarketplaceLocation(w, r, fs)
			})
			rr.Get("/offers", func(w http.ResponseWriter, r *http.Request) {
				handleMarketplaceOffersList(w, r, fs)
			})
			rr.Post("/offers/{offerId}/accept", func(w http.ResponseWriter, r *http.Request) {
				offerID := strings.TrimSpace(chi.URLParam(r, "offerId"))
				if offerID == "" {
					writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_offer_id"})
					return
				}
				handleMarketplaceOfferAccept(w, r, fs, offerID)
			})
			rr.Post("/orders/{orderId}/status", func(w http.ResponseWriter, r *http.Request) {
				orderID := strings.TrimSpace(chi.URLParam(r, "orderId"))
				if orderID == "" {
					writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_order_id"})
					return
				}
				handleMarketplaceOrderStatus(w, r, fs, cfg, pubsubClient, httpClient, orderTokenSrc, orderID)
			})
		})
	})

	log.Printf("dispatch-service listening on :%s", cfg.Port)
	log.Fatal(http.ListenAndServe(":"+cfg.Port, router))
}

func loadConfig() (*serviceConfig, error) {
	values, err := sharedconfig.Load("dispatch-service", nil)
	if err != nil {
		return nil, err
	}

	port := strings.TrimSpace(os.Getenv("PORT"))
	if port == "" {
		port = defaultPort
	}

	project := strings.TrimSpace(stringOrDefault(values["FIRESTORE_PROJECT_ID"], strings.TrimSpace(os.Getenv("FIRESTORE_PROJECT_ID"))))
	if project == "" {
		project = strings.TrimSpace(os.Getenv("GOOGLE_CLOUD_PROJECT"))
	}
	if project == "" {
		return nil, fmt.Errorf("FIRESTORE_PROJECT_ID not configured")
	}

	internalAllowed := strings.TrimSpace(stringOrDefault(values["INTERNAL_ALLOWED_EMAILS"], strings.TrimSpace(os.Getenv("INTERNAL_ALLOWED_EMAILS"))))
	internalAllowedEmails := splitCSV(internalAllowed)
	corsOrigins, err := resolveDispatchCORSOrigins(
		strings.TrimSpace(stringOrDefault(values["CORS_ORIGINS"], strings.TrimSpace(os.Getenv("CORS_ORIGINS")))),
	)
	if err != nil {
		return nil, err
	}

	ttlSeconds := intFromEnv("ASSIGNMENT_TTL_SECONDS", 30)
	if ttlSeconds < 10 {
		ttlSeconds = 30
	}
	topK := intFromEnv("TOP_K_CANDIDATES", 5)
	if topK < 1 {
		topK = 5
	}
	if topK > 25 {
		topK = 25
	}
	marketplaceLimit := intFromEnv("MARKETPLACE_CANDIDATE_LIMIT", 25)
	if marketplaceLimit < 5 {
		marketplaceLimit = 5
	}
	if marketplaceLimit > 50 {
		marketplaceLimit = 50
	}

	return &serviceConfig{
		Port:                         port,
		Environment:                  strings.TrimSpace(stringOrDefault(values["ENVIRONMENT"], "development")),
		FirestoreProjectID:           project,
		CredentialsFile:              strings.TrimSpace(stringOrDefault(values["GOOGLE_APPLICATION_CREDENTIALS"], "")),
		RequireAuth:                  strings.TrimSpace(stringOrDefault(values["REQUIRE_AUTH"], strings.TrimSpace(os.Getenv("REQUIRE_AUTH")))) != "false",
		CORSOrigins:                  corsOrigins,
		InternalAuthAudience:         strings.TrimSpace(stringOrDefault(values["INTERNAL_AUTH_AUDIENCE"], strings.TrimSpace(os.Getenv("INTERNAL_AUTH_AUDIENCE")))),
		InternalAllowedEmails:        internalAllowedEmails,
		OrderServiceURL:              strings.TrimSpace(stringOrDefault(values["ORDER_SERVICE_URL"], strings.TrimSpace(os.Getenv("ORDER_SERVICE_URL")))),
		DispatchEventsTopic:          strings.TrimSpace(stringOrDefault(values["DISPATCH_EVENTS_TOPIC"], strings.TrimSpace(os.Getenv("DISPATCH_EVENTS_TOPIC")))),
		RadarAPIKey:                  strings.TrimSpace(stringOrDefault(values["RADAR_API_KEY"], strings.TrimSpace(os.Getenv("RADAR_API_KEY")))),
		AssignmentTTLSeconds:         ttlSeconds,
		TopKCandidates:               topK,
		MarketplaceCandidateLimit:    marketplaceLimit,
		CloudTasksProjectID:          strings.TrimSpace(stringOrDefault(values["CLOUD_TASKS_PROJECT_ID"], strings.TrimSpace(os.Getenv("CLOUD_TASKS_PROJECT_ID")))),
		CloudTasksLocation:           strings.TrimSpace(stringOrDefault(values["CLOUD_TASKS_LOCATION"], strings.TrimSpace(os.Getenv("CLOUD_TASKS_LOCATION")))),
		CloudTasksAssignmentQueue:    strings.TrimSpace(stringOrDefault(values["CLOUD_TASKS_ASSIGNMENT_QUEUE"], strings.TrimSpace(os.Getenv("CLOUD_TASKS_ASSIGNMENT_QUEUE")))),
		CloudTasksOIDCServiceAccount: strings.TrimSpace(stringOrDefault(values["CLOUD_TASKS_OIDC_SERVICE_ACCOUNT_EMAIL"], strings.TrimSpace(os.Getenv("CLOUD_TASKS_OIDC_SERVICE_ACCOUNT_EMAIL")))),
		CloudTasksOIDCAudience:       strings.TrimSpace(stringOrDefault(values["CLOUD_TASKS_OIDC_AUDIENCE"], strings.TrimSpace(os.Getenv("CLOUD_TASKS_OIDC_AUDIENCE")))),
		DispatchServiceBaseURL:       strings.TrimRight(strings.TrimSpace(stringOrDefault(values["DISPATCH_SERVICE_URL"], strings.TrimSpace(os.Getenv("DISPATCH_SERVICE_URL")))), "/"),
	}, nil
}

func newFirestoreClient(ctx context.Context, cfg *serviceConfig) (*cloudfirestore.Client, error) {
	var opts []option.ClientOption
	if strings.TrimSpace(cfg.CredentialsFile) != "" {
		opts = append(opts, option.WithCredentialsFile(cfg.CredentialsFile))
	}
	return cloudfirestore.NewClient(ctx, cfg.FirestoreProjectID, opts...)
}

func newFirebaseAuthClient(ctx context.Context, cfg *serviceConfig) (*auth.Client, error) {
	projectID := strings.TrimSpace(cfg.FirestoreProjectID)
	if projectID == "" {
		return nil, fmt.Errorf("missing FIRESTORE_PROJECT_ID")
	}
	app, err := firebase.NewApp(ctx, &firebase.Config{ProjectID: projectID})
	if err != nil {
		return nil, err
	}
	return app.Auth(ctx)
}

func firebaseOrInternalMiddleware(
	client tokenVerifier,
	internalAudience string,
	internalAllowedEmails []string,
) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if r.Method == http.MethodOptions {
				next.ServeHTTP(w, r)
				return
			}
			authHeader := r.Header.Get("Authorization")
			if strings.TrimSpace(authHeader) == "" {
				writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "missing_auth"})
				return
			}
			tokenString := strings.TrimSpace(strings.TrimPrefix(authHeader, "Bearer "))
			if tokenString == authHeader {
				writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid_auth_header"})
				return
			}

			// Firebase ID token path.
			if client != nil {
				if token, err := client.VerifyIDToken(r.Context(), tokenString); err == nil {
					var storeIDs []string
					if storesClaim, ok := token.Claims["storeIds"]; ok {
						if s, ok := storesClaim.([]interface{}); ok {
							for _, v := range s {
								if str, ok := v.(string); ok {
									storeIDs = append(storeIDs, str)
								}
							}
						}
					}
					role := ""
					if rClaim, ok := token.Claims["role"].(string); ok {
						role = rClaim
					}
					ctx := context.WithValue(r.Context(), authContextKey, authContext{
						UID:      token.UID,
						Role:     role,
						StoreIDs: storeIDs,
					})
					next.ServeHTTP(w, r.WithContext(ctx))
					return
				}
			}

			// Internal IAM-style auth.
			if internalAudience != "" {
				if ok, ac := tryGoogleIDTokenAuth(r.Context(), tokenString, internalAudience, internalAllowedEmails); ok {
					ctx := context.WithValue(r.Context(), authContextKey, ac)
					next.ServeHTTP(w, r.WithContext(ctx))
					return
				}
			}

			writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
		})
	}
}

func tryGoogleIDTokenAuth(ctx context.Context, tokenString, audience string, allowedEmails []string) (bool, authContext) {
	payload, err := idtoken.Validate(ctx, tokenString, audience)
	if err != nil {
		return false, authContext{}
	}
	email := ""
	if v, ok := payload.Claims["email"]; ok {
		if s, ok := v.(string); ok {
			email = s
		}
	}
	email = strings.TrimSpace(email)
	if email == "" {
		return false, authContext{}
	}
	if len(allowedEmails) > 0 {
		ok := false
		for _, a := range allowedEmails {
			if strings.EqualFold(strings.TrimSpace(a), email) {
				ok = true
				break
			}
		}
		if !ok {
			return false, authContext{}
		}
	}
	return true, authContext{UID: email, Role: "internal", StoreIDs: []string{}}
}

func canAccessStore(ctx context.Context, storeID string) bool {
	ac, ok := ctx.Value(authContextKey).(authContext)
	if !ok {
		return false
	}
	if ac.Role == "internal" || ac.Role == "api-key" {
		return true
	}
	if len(ac.StoreIDs) == 0 {
		return false
	}
	for _, s := range ac.StoreIDs {
		if s == storeID {
			return true
		}
	}
	return false
}

func authUID(ctx context.Context) string {
	ac, ok := ctx.Value(authContextKey).(authContext)
	if !ok {
		return ""
	}
	return strings.TrimSpace(ac.UID)
}

func isDriverForStore(ctx context.Context, fs *cloudfirestore.Client, storeID string) bool {
	uid := authUID(ctx)
	if uid == "" {
		return false
	}
	doc, err := fs.Collection(storesCollection).Doc(storeID).Collection(driversSubcollection).Doc(uid).Get(ctx)
	if err == nil && doc.Exists() {
		active, _ := doc.Data()["active"].(bool)
		return active
	}
	// Fall back to query by uid field (for non-uid doc IDs).
	iter := fs.Collection(storesCollection).Doc(storeID).Collection(driversSubcollection).Where("uid", "==", uid).Where("active", "==", true).Limit(1).Documents(ctx)
	defer iter.Stop()
	snap, err := iter.Next()
	return err == nil && snap != nil && snap.Exists()
}

func handleOrdersEvents(
	w http.ResponseWriter,
	r *http.Request,
	fs *cloudfirestore.Client,
	cfg *serviceConfig,
	pubsubClient *cloudpubsub.Client,
	tasksClient *cloudtasks.Client,
	httpClient *http.Client,
	orderTokenSrc oauth2.TokenSource,
) {
	var env pubsubPushEnvelope
	if err := json.NewDecoder(r.Body).Decode(&env); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_pubsub_envelope"})
		return
	}
	if strings.TrimSpace(env.Message.Data) == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_message_data"})
		return
	}

	raw, err := base64.StdEncoding.DecodeString(env.Message.Data)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_base64"})
		return
	}

	var order orderRecord
	if err := json.Unmarshal(raw, &order); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_order_payload"})
		return
	}

	if strings.ToLower(strings.TrimSpace(order.FulfillmentType)) != "delivery" {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ignored_not_delivery"})
		return
	}
	if order.Delivery == nil {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ignored_missing_delivery"})
		return
	}
	fleetMode := strings.ToLower(strings.TrimSpace(order.Delivery.FleetMode))
	if fleetMode == "marketplace" {
		handleMarketplaceOrdersEvent(w, r, fs, cfg, pubsubClient, tasksClient, httpClient, orderTokenSrc, order)
		return
	}
	if fleetMode != "owned_fleet" {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ignored_not_owned_fleet"})
		return
	}
	// Trigger assignment on initial pending state only.
	if strings.ToLower(strings.TrimSpace(order.Status)) != "pending" {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ignored_not_pending"})
		return
	}
	storeID := strings.TrimSpace(order.StoreID)
	orderID := strings.TrimSpace(order.ID)
	if storeID == "" || orderID == "" {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ignored_missing_ids"})
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 8*time.Second)
	defer cancel()

	assignment, created, err := createOrRefreshAssignment(ctx, fs, cfg, tasksClient, storeID, orderID)
	if err != nil {
		log.Printf("orders-events: assignment create failed store=%s order=%s err=%v", storeID, orderID, err)
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "assignment_failed"})
		return
	}
	if !created {
		writeJSON(w, http.StatusOK, map[string]string{"status": "dedup"})
		return
	}

	atomic.AddUint64(&assignmentsCreatedCounter, 1)

	if assignment.DriverID != "" {
		// Best-effort order-service patch (assignment summary).
		_ = patchOrderDelivery(ctx, httpClient, orderTokenSrc, cfg.OrderServiceURL, orderID, map[string]any{
			"assignedDriverId": assignment.DriverID,
			"assignmentStatus": assignment.Status,
		})
		// Publish dispatch event (best-effort).
		_ = publishDispatchEvent(ctx, pubsubClient, cfg, dispatchEvent{
			Kind:         "assignment_request",
			StoreID:      storeID,
			OrderID:      orderID,
			AssignmentID: assignment.AssignmentID,
			DriverID:     assignment.DriverID,
			CreatedAt:    time.Now().UTC().Format(time.RFC3339),
			Payload: map[string]any{
				"expiresAt": assignment.ExpiresAt.UTC().Format(time.RFC3339),
			},
		})
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"status":           "ok",
		"storeId":          storeID,
		"orderId":          orderID,
		"assignmentId":     assignment.AssignmentID,
		"assignedDriverId": assignment.DriverID,
	})
}

func createOrRefreshAssignment(
	ctx context.Context,
	fs *cloudfirestore.Client,
	cfg *serviceConfig,
	tasksClient *cloudtasks.Client,
	storeID string,
	orderID string,
) (*driverAssignment, bool, error) {
	dedupID := storeID + "__" + orderID
	dedupRef := fs.Collection(dispatchDedupCollection).Doc(dedupID)
	assignID := "asgn_" + strings.ReplaceAll(orderID, ":", "_")
	assignRef := fs.Collection(storesCollection).Doc(storeID).Collection(assignmentsSubcollection).Doc(assignID)

	var created bool
	var assignment driverAssignment

	err := fs.RunTransaction(ctx, func(ctx context.Context, tx *cloudfirestore.Transaction) error {
		if snap, err := tx.Get(dedupRef); err == nil && snap.Exists() {
			created = false
			return nil
		} else if err != nil && status.Code(err) != codes.NotFound {
			return err
		}

		// Fetch candidates (on-shift drivers with a fresh location).
		candidates, err := findCandidateDrivers(ctx, fs, storeID, cfg.TopKCandidates, cfg.RadarAPIKey)
		if err != nil {
			return err
		}

		now := time.Now().UTC()
		expires := now.Add(time.Duration(cfg.AssignmentTTLSeconds) * time.Second)

		assignment = driverAssignment{
			AssignmentID: assignID,
			OrderID:      orderID,
			Status:       "pending",
			Candidates:   candidates,
			CandidateIdx: 0,
			ExpiresAt:    expires,
			CreatedAt:    now,
			UpdatedAt:    now,
		}
		if len(candidates) > 0 {
			assignment.DriverID = candidates[0].DriverID
		}

		if err := tx.Set(assignRef, assignment); err != nil {
			return err
		}
		if err := tx.Set(dedupRef, map[string]any{
			"storeId":      storeID,
			"orderId":      orderID,
			"assignmentId": assignID,
			"createdAt":    now,
		}, cloudfirestore.MergeAll); err != nil {
			return err
		}
		created = true
		return nil
	})
	if err != nil {
		return nil, false, err
	}
	if created {
		_ = enqueueAssignmentExpiry(ctx, tasksClient, cfg, storeID, assignment.AssignmentID, assignment.ExpiresAt)
	}
	return &assignment, created, nil
}

func findCandidateDrivers(ctx context.Context, fs *cloudfirestore.Client, storeID string, topK int, radarKey string) ([]assignmentCandidate, error) {
	// Get store location.
	storeLoc, err := fetchStoreLocation(ctx, fs, storeID)
	if err != nil {
		return nil, err
	}
	now := time.Now().UTC()

	// Find on-shift drivers.
	iter := fs.Collection(storesCollection).Doc(storeID).Collection(shiftsSubcollection).Where("status", "==", "on_shift").Documents(ctx)
	defer iter.Stop()

	type candidateLoc struct {
		driverID string
		loc      driverLocation
	}
	var locs []candidateLoc
	for {
		doc, err := iter.Next()
		if err != nil {
			if errors.Is(err, iterator.Done) {
				break
			}
			return nil, err
		}
		driverID := strings.TrimSpace(doc.Ref.ID)
		if driverID == "" {
			continue
		}
		locSnap, err := fs.Collection(storesCollection).Doc(storeID).Collection(locationsSubcollection).Doc(driverID).Get(ctx)
		if err != nil || !locSnap.Exists() {
			continue
		}
		var dl driverLocation
		_ = locSnap.DataTo(&dl)
		if dl.ExpiresAt.Before(now) {
			continue
		}
		locs = append(locs, candidateLoc{driverID: driverID, loc: dl})
	}
	if len(locs) == 0 {
		return []assignmentCandidate{}, nil
	}

	// Compute ETAs using Radar matrix for efficiency; fall back to per-driver distance.
	type scored struct {
		driverID string
		eta      int
	}
	var scoreds []scored
	origins := make([]deliveryLatLng, 0, len(locs))
	for _, c := range locs {
		origins = append(origins, deliveryLatLng{Lat: c.loc.Lat, Lng: c.loc.Lng})
	}
	matrix, err := radarMatrixDurations(ctx, radarKey, origins, []deliveryLatLng{{Lat: storeLoc.Lat, Lng: storeLoc.Lng}}, "car")
	if err == nil && len(matrix) == len(locs) {
		for i, row := range matrix {
			if len(row) == 0 {
				continue
			}
			secs := row[0]
			if secs <= 0 {
				continue
			}
			scoreds = append(scoreds, scored{driverID: locs[i].driverID, eta: int(math.Round(secs))})
		}
	} else {
		for _, c := range locs {
			secs, err := radarDurationSeconds(ctx, radarKey, c.loc.Lat, c.loc.Lng, storeLoc.Lat, storeLoc.Lng)
			if err != nil {
				continue
			}
			scoreds = append(scoreds, scored{driverID: c.driverID, eta: int(math.Round(secs))})
		}
	}
	sort.Slice(scoreds, func(i, j int) bool { return scoreds[i].eta < scoreds[j].eta })
	if topK > 0 && len(scoreds) > topK {
		scoreds = scoreds[:topK]
	}
	out := make([]assignmentCandidate, 0, len(scoreds))
	for _, s := range scoreds {
		out = append(out, assignmentCandidate{DriverID: s.driverID, EtaToPickupSecs: s.eta})
	}
	return out, nil
}

func fetchStoreLocation(ctx context.Context, fs *cloudfirestore.Client, storeID string) (*storeDeliveryLocation, error) {
	doc, err := fs.Collection(storesCollection).Doc(storeID).Get(ctx)
	if err != nil || !doc.Exists() {
		return nil, fmt.Errorf("store_not_found")
	}
	raw := doc.Data()
	ds, _ := raw["delivery_settings"].(map[string]any)
	if ds == nil {
		// Support legacy key.
		if m, ok := raw["deliverySettings"].(map[string]any); ok {
			ds = m
		}
	}
	loc, _ := ds["store_location"].(map[string]any)
	if loc == nil {
		if m, ok := ds["storeLocation"].(map[string]any); ok {
			loc = m
		}
	}
	lat := anyToFloat64(loc["lat"])
	lng := anyToFloat64(loc["lng"])
	if lat == 0 || lng == 0 {
		return nil, fmt.Errorf("missing_store_location")
	}
	return &storeDeliveryLocation{Lat: lat, Lng: lng}, nil
}

func handleQuoteOwnedFleet(w http.ResponseWriter, r *http.Request, fs *cloudfirestore.Client, cfg *serviceConfig, storeID string) {
	var payload struct {
		DropoffLatLng  *deliveryLatLng  `json:"dropoffLatLng"`
		DropoffAddress *deliveryAddress `json:"dropoffAddress"`
		DropoffQuery   string           `json:"dropoffAddressText"`
	}
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
		return
	}
	if strings.TrimSpace(cfg.RadarAPIKey) == "" {
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "radar_not_configured"})
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()

	storeLoc, err := fetchStoreLocation(ctx, fs, storeID)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
		return
	}

	drop := payload.DropoffLatLng
	if drop == nil || drop.Lat == 0 || drop.Lng == 0 {
		query := strings.TrimSpace(payload.DropoffQuery)
		if query == "" && payload.DropoffAddress != nil {
			query = strings.TrimSpace(firstNonEmpty(
				payload.DropoffAddress.Formatted,
				strings.TrimSpace(payload.DropoffAddress.Line1+" "+payload.DropoffAddress.City+" "+payload.DropoffAddress.State+" "+payload.DropoffAddress.PostalCode),
			))
		}
		if query == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_dropoff"})
			return
		}
		lat, lng, formatted, err := radarForwardGeocode(ctx, cfg.RadarAPIKey, query)
		if err != nil {
			log.Printf("radar geocode failed query=%q err=%v", query, err)
			writeJSON(w, http.StatusBadGateway, map[string]string{"error": "geocode_unavailable"})
			return
		}
		drop = &deliveryLatLng{Lat: lat, Lng: lng}
		if payload.DropoffAddress == nil {
			payload.DropoffAddress = &deliveryAddress{}
		}
		if strings.TrimSpace(payload.DropoffAddress.Formatted) == "" {
			payload.DropoffAddress.Formatted = formatted
		}
	}

	secs, err := radarDurationSeconds(ctx, cfg.RadarAPIKey, storeLoc.Lat, storeLoc.Lng, drop.Lat, drop.Lng)
	if err != nil {
		log.Printf("radar distance failed: %v", err)
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "radar_unavailable"})
		return
	}
	mins := int(math.Round(secs / 60.0))
	if mins < 1 {
		mins = 1
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"provider":          "radar",
		"currency":          "USD",
		"providerFeeCents":  0,
		"dropoffEtaMinutes": mins,
		"quoteExpiresAt":    time.Now().UTC().Add(10 * time.Minute).Format(time.RFC3339),
		"dropoffLatLng":     drop,
		"dropoffAddress":    payload.DropoffAddress,
	})
}

func handleOptimizeRoute(w http.ResponseWriter, r *http.Request, cfg *serviceConfig) {
	var payload struct {
		Locations []deliveryLatLng `json:"locations"`
		Mode      string           `json:"mode"`
		Units     string           `json:"units"`
	}
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
		return
	}
	if len(payload.Locations) < 2 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "need_at_least_two_locations"})
		return
	}
	mode := strings.TrimSpace(payload.Mode)
	if mode == "" {
		mode = "car"
	}
	units := strings.TrimSpace(payload.Units)
	if units == "" {
		units = "metric"
	}

	ctx, cancel := context.WithTimeout(r.Context(), 6*time.Second)
	defer cancel()

	order, err := radarOptimizeOrder(ctx, cfg.RadarAPIKey, payload.Locations, mode, units)
	if err != nil {
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "radar_unavailable"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"order": order,
	})
}

func radarForwardGeocode(ctx context.Context, apiKey string, query string) (lat, lng float64, formatted string, err error) {
	apiKey = strings.TrimSpace(apiKey)
	query = strings.TrimSpace(query)
	if apiKey == "" {
		return 0, 0, "", fmt.Errorf("radar_api_key_missing")
	}
	if query == "" {
		return 0, 0, "", fmt.Errorf("query_missing")
	}
	u, _ := url.Parse("https://api.radar.io/v1/geocode/forward")
	q := u.Query()
	q.Set("query", query)
	u.RawQuery = q.Encode()

	req, _ := http.NewRequestWithContext(ctx, http.MethodGet, u.String(), nil)
	req.Header.Set("Authorization", apiKey)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return 0, 0, "", err
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return 0, 0, "", fmt.Errorf("radar_status_%d: %s", resp.StatusCode, strings.TrimSpace(string(body)))
	}

	var m map[string]any
	if err := json.Unmarshal(body, &m); err != nil {
		return 0, 0, "", err
	}
	addrs, _ := m["addresses"].([]any)
	if len(addrs) == 0 {
		return 0, 0, "", fmt.Errorf("no_addresses")
	}
	a0, _ := addrs[0].(map[string]any)
	if a0 == nil {
		return 0, 0, "", fmt.Errorf("invalid_addresses")
	}
	lat = anyToFloat64(firstNonNil(a0["latitude"], a0["lat"], dig(a0, "location", "latitude"), dig(a0, "location", "lat")))
	lng = anyToFloat64(firstNonNil(a0["longitude"], a0["lng"], dig(a0, "location", "longitude"), dig(a0, "location", "lng")))
	formatted, _ = firstNonNil(a0["formattedAddress"], a0["formatted_address"], a0["addressLabel"], a0["addressLabel"]).(string)
	formatted = strings.TrimSpace(formatted)
	if lat == 0 || lng == 0 {
		return 0, 0, "", fmt.Errorf("missing_latlng")
	}
	return lat, lng, formatted, nil
}

func dig(m map[string]any, keys ...string) any {
	var cur any = m
	for _, k := range keys {
		mm, ok := cur.(map[string]any)
		if !ok {
			return nil
		}
		cur = mm[k]
	}
	return cur
}

func firstNonNil(vals ...any) any {
	for _, v := range vals {
		if v != nil {
			return v
		}
	}
	return nil
}

func firstNonEmpty(vals ...string) string {
	for _, v := range vals {
		if strings.TrimSpace(v) != "" {
			return strings.TrimSpace(v)
		}
	}
	return ""
}

func radarDurationSeconds(ctx context.Context, apiKey string, originLat, originLng, destLat, destLng float64) (float64, error) {
	apiKey = strings.TrimSpace(apiKey)
	if apiKey == "" {
		return 0, fmt.Errorf("radar_api_key_missing")
	}

	u, _ := url.Parse("https://api.radar.io/v1/route/distance")
	q := u.Query()
	q.Set("origin", fmt.Sprintf("%.6f,%.6f", originLat, originLng))
	q.Set("destination", fmt.Sprintf("%.6f,%.6f", destLat, destLng))
	q.Set("modes", "car")
	q.Set("units", "metric")
	u.RawQuery = q.Encode()

	req, _ := http.NewRequestWithContext(ctx, http.MethodGet, u.String(), nil)
	req.Header.Set("Authorization", apiKey)

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return 0, err
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return 0, fmt.Errorf("radar_status_%d: %s", resp.StatusCode, strings.TrimSpace(string(body)))
	}
	return extractRadarDurationSeconds(body)
}

func radarMatrixDurations(ctx context.Context, apiKey string, origins []deliveryLatLng, destinations []deliveryLatLng, mode string) ([][]float64, error) {
	apiKey = strings.TrimSpace(apiKey)
	if apiKey == "" {
		return nil, fmt.Errorf("radar_api_key_missing")
	}
	if len(origins) == 0 || len(destinations) == 0 {
		return nil, fmt.Errorf("missing_locations")
	}
	mode = strings.TrimSpace(mode)
	if mode == "" {
		mode = "car"
	}
	u, _ := url.Parse("https://api.radar.io/v1/route/matrix")
	q := u.Query()
	q.Set("origins", joinLatLngs(origins))
	q.Set("destinations", joinLatLngs(destinations))
	q.Set("mode", mode)
	q.Set("units", "metric")
	u.RawQuery = q.Encode()

	req, _ := http.NewRequestWithContext(ctx, http.MethodGet, u.String(), nil)
	req.Header.Set("Authorization", apiKey)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("radar_status_%d: %s", resp.StatusCode, strings.TrimSpace(string(body)))
	}
	return extractRadarMatrixDurations(body)
}

func extractRadarMatrixDurations(body []byte) ([][]float64, error) {
	var m map[string]any
	if err := json.Unmarshal(body, &m); err != nil {
		return nil, err
	}
	raw, ok := m["matrix"].([]any)
	if !ok || len(raw) == 0 {
		return nil, fmt.Errorf("matrix_missing")
	}
	matrix := make([][]float64, 0, len(raw))
	for _, row := range raw {
		items, ok := row.([]any)
		if !ok {
			return nil, fmt.Errorf("matrix_row_invalid")
		}
		outRow := make([]float64, 0, len(items))
		for _, item := range items {
			cell, ok := item.(map[string]any)
			if !ok {
				outRow = append(outRow, 0)
				continue
			}
			durRaw, _ := cell["duration"].(map[string]any)
			outRow = append(outRow, anyToFloat64(durRaw["value"]))
		}
		matrix = append(matrix, outRow)
	}
	return matrix, nil
}

func radarOptimizeOrder(ctx context.Context, apiKey string, locations []deliveryLatLng, mode, units string) ([]int, error) {
	apiKey = strings.TrimSpace(apiKey)
	if apiKey == "" {
		return nil, fmt.Errorf("radar_api_key_missing")
	}
	if len(locations) < 2 {
		return nil, fmt.Errorf("need_at_least_two_locations")
	}
	mode = strings.TrimSpace(mode)
	if mode == "" {
		mode = "car"
	}
	units = strings.TrimSpace(units)
	if units == "" {
		units = "metric"
	}
	u, _ := url.Parse("https://api.radar.io/v1/route/optimize")
	q := u.Query()
	q.Set("locations", joinLatLngs(locations))
	q.Set("mode", mode)
	q.Set("units", units)
	u.RawQuery = q.Encode()

	req, _ := http.NewRequestWithContext(ctx, http.MethodGet, u.String(), nil)
	req.Header.Set("Authorization", apiKey)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("radar_status_%d: %s", resp.StatusCode, strings.TrimSpace(string(body)))
	}
	return extractRadarOptimizeOrder(body)
}

func extractRadarOptimizeOrder(body []byte) ([]int, error) {
	var m map[string]any
	if err := json.Unmarshal(body, &m); err != nil {
		return nil, err
	}
	route, _ := m["route"].(map[string]any)
	legs, _ := route["legs"].([]any)
	if len(legs) == 0 {
		return nil, fmt.Errorf("legs_missing")
	}
	order := make([]int, 0, len(legs)+1)
	for i, leg := range legs {
		lm, ok := leg.(map[string]any)
		if !ok {
			return nil, fmt.Errorf("leg_invalid")
		}
		start := int(anyToFloat64(lm["startIndex"]))
		end := int(anyToFloat64(lm["endIndex"]))
		if i == 0 {
			order = append(order, start)
		}
		order = append(order, end)
	}
	if len(order) == 0 {
		return nil, fmt.Errorf("order_empty")
	}
	return order, nil
}

func joinLatLngs(locations []deliveryLatLng) string {
	parts := make([]string, 0, len(locations))
	for _, loc := range locations {
		parts = append(parts, fmt.Sprintf("%f,%f", loc.Lat, loc.Lng))
	}
	return strings.Join(parts, "|")
}

func extractRadarDurationSeconds(body []byte) (float64, error) {
	var m map[string]any
	if err := json.Unmarshal(body, &m); err != nil {
		return 0, err
	}
	// Possible shapes:
	// - { route: { duration: { value: 123 } } }
	// - { routes: [ { duration: { value: 123 } } ] }
	// - { routes: { car: { duration: { value: 123 }}}}
	if v, ok := m["route"]; ok {
		if secs := findDurationSeconds(v); secs > 0 {
			return secs, nil
		}
	}
	if v, ok := m["routes"]; ok {
		if secs := findDurationSeconds(v); secs > 0 {
			return secs, nil
		}
	}
	// As a last resort, scan the whole object.
	if secs := findDurationSeconds(m); secs > 0 {
		return secs, nil
	}
	return 0, fmt.Errorf("duration_not_found")
}

func findDurationSeconds(v any) float64 {
	switch t := v.(type) {
	case map[string]any:
		if d, ok := t["duration"]; ok {
			// duration may be { value: seconds } or numeric seconds.
			if secs := anyToFloat64(d); secs > 0 {
				return secs
			}
			if dm, ok := d.(map[string]any); ok {
				if secs := anyToFloat64(dm["value"]); secs > 0 {
					return secs
				}
			}
		}
		for _, vv := range t {
			if secs := findDurationSeconds(vv); secs > 0 {
				return secs
			}
		}
	case []any:
		for _, vv := range t {
			if secs := findDurationSeconds(vv); secs > 0 {
				return secs
			}
		}
	}
	return 0
}

func listDrivers(w http.ResponseWriter, r *http.Request, fs *cloudfirestore.Client, storeID string) {
	ctx, cancel := context.WithTimeout(r.Context(), 4*time.Second)
	defer cancel()
	iter := fs.Collection(storesCollection).Doc(storeID).Collection(driversSubcollection).OrderBy("createdAt", cloudfirestore.Asc).Documents(ctx)
	defer iter.Stop()
	var out []map[string]any
	for {
		doc, err := iter.Next()
		if err != nil {
			if strings.Contains(err.Error(), "no more items") {
				break
			}
			break
		}
		out = append(out, map[string]any{
			"id":   doc.Ref.ID,
			"data": doc.Data(),
		})
	}
	writeJSON(w, http.StatusOK, map[string]any{"drivers": out})
}

func createDriver(w http.ResponseWriter, r *http.Request, fs *cloudfirestore.Client, storeID string) {
	var payload struct {
		DisplayName    string `json:"displayName"`
		PhoneE164      string `json:"phoneE164"`
		MaxActiveStops int    `json:"maxActiveStops"`
	}
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
		return
	}
	payload.DisplayName = strings.TrimSpace(payload.DisplayName)
	payload.PhoneE164 = strings.TrimSpace(payload.PhoneE164)
	if payload.DisplayName == "" || payload.PhoneE164 == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_fields"})
		return
	}
	if payload.MaxActiveStops <= 0 {
		payload.MaxActiveStops = 3
	}
	now := time.Now().UTC()
	rec := driverRecord{
		DisplayName:    payload.DisplayName,
		PhoneE164:      payload.PhoneE164,
		Active:         true,
		MaxActiveStops: payload.MaxActiveStops,
		CreatedAt:      now,
		UpdatedAt:      now,
	}
	ctx, cancel := context.WithTimeout(r.Context(), 4*time.Second)
	defer cancel()
	ref := fs.Collection(storesCollection).Doc(storeID).Collection(driversSubcollection).NewDoc()
	if _, err := ref.Set(ctx, rec); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "create_failed"})
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"driverId": ref.ID})
}

func patchDriver(w http.ResponseWriter, r *http.Request, fs *cloudfirestore.Client, storeID, driverID string) {
	var payload struct {
		Active         *bool   `json:"active"`
		DisplayName    *string `json:"displayName"`
		MaxActiveStops *int    `json:"maxActiveStops"`
	}
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
		return
	}
	updates := []cloudfirestore.Update{{Path: "updatedAt", Value: time.Now().UTC()}}
	if payload.Active != nil {
		updates = append(updates, cloudfirestore.Update{Path: "active", Value: *payload.Active})
	}
	if payload.DisplayName != nil {
		updates = append(updates, cloudfirestore.Update{Path: "displayName", Value: strings.TrimSpace(*payload.DisplayName)})
	}
	if payload.MaxActiveStops != nil {
		updates = append(updates, cloudfirestore.Update{Path: "maxActiveStops", Value: *payload.MaxActiveStops})
	}
	if len(updates) <= 1 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_fields"})
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 4*time.Second)
	defer cancel()
	ref := fs.Collection(storesCollection).Doc(storeID).Collection(driversSubcollection).Doc(driverID)
	if _, err := ref.Update(ctx, updates); err != nil {
		if status.Code(err) == codes.NotFound {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "not_found"})
			return
		}
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "update_failed"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func claimDriver(w http.ResponseWriter, r *http.Request, fs *cloudfirestore.Client, storeID string) {
	uid := authUID(r.Context())
	if uid == "" {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
		return
	}
	var payload struct {
		PhoneE164 string `json:"phoneE164"`
	}
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
		return
	}
	phone := strings.TrimSpace(payload.PhoneE164)
	if phone == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_phone"})
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()

	iter := fs.Collection(storesCollection).Doc(storeID).Collection(driversSubcollection).
		Where("phoneE164", "==", phone).Limit(1).Documents(ctx)
	defer iter.Stop()
	doc, err := iter.Next()
	if err != nil || doc == nil || !doc.Exists() {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "driver_not_found"})
		return
	}
	driverID := doc.Ref.ID
	if _, err := doc.Ref.Update(ctx, []cloudfirestore.Update{
		{Path: "uid", Value: uid},
		{Path: "updatedAt", Value: time.Now().UTC()},
	}); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "claim_failed"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"driverId": driverID})
}

func updateShift(w http.ResponseWriter, r *http.Request, fs *cloudfirestore.Client, storeID, nextStatus string) {
	uid := authUID(r.Context())
	if uid == "" {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
		return
	}
	if !isDriverForStore(r.Context(), fs, storeID) {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "forbidden"})
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 4*time.Second)
	defer cancel()
	ref := fs.Collection(storesCollection).Doc(storeID).Collection(shiftsSubcollection).Doc(uid)
	now := time.Now().UTC()
	data := map[string]any{
		"driverId":  uid,
		"status":    nextStatus,
		"updatedAt": now,
	}
	if nextStatus == "on_shift" {
		data["startedAt"] = now
	}
	if _, err := ref.Set(ctx, data, cloudfirestore.MergeAll); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "shift_update_failed"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func postLocation(w http.ResponseWriter, r *http.Request, fs *cloudfirestore.Client, storeID string) {
	uid := authUID(r.Context())
	if uid == "" {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
		return
	}
	if !isDriverForStore(r.Context(), fs, storeID) {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "forbidden"})
		return
	}
	var payload struct {
		Lat       float64 `json:"lat"`
		Lng       float64 `json:"lng"`
		AccuracyM float64 `json:"accuracyM"`
	}
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
		return
	}
	if payload.Lat == 0 || payload.Lng == 0 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_latlng"})
		return
	}
	now := time.Now().UTC()
	exp := now.Add(2 * time.Minute)
	loc := driverLocation{
		Lat:        payload.Lat,
		Lng:        payload.Lng,
		AccuracyM:  payload.AccuracyM,
		RecordedAt: now,
		ExpiresAt:  exp,
	}
	ctx, cancel := context.WithTimeout(r.Context(), 4*time.Second)
	defer cancel()
	ref := fs.Collection(storesCollection).Doc(storeID).Collection(locationsSubcollection).Doc(uid)
	if _, err := ref.Set(ctx, loc); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "location_update_failed"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func acceptOrDecline(
	w http.ResponseWriter,
	r *http.Request,
	fs *cloudfirestore.Client,
	cfg *serviceConfig,
	pubsubClient *cloudpubsub.Client,
	tasksClient *cloudtasks.Client,
	httpClient *http.Client,
	orderTokenSrc oauth2.TokenSource,
	storeID string,
	assignmentID string,
	accept bool,
) {
	uid := authUID(r.Context())
	if uid == "" {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
		return
	}
	if !isDriverForStore(r.Context(), fs, storeID) {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "forbidden"})
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 8*time.Second)
	defer cancel()

	assignRef := fs.Collection(storesCollection).Doc(storeID).Collection(assignmentsSubcollection).Doc(assignmentID)
	routeID := "route_" + assignmentID
	routeRef := fs.Collection(storesCollection).Doc(storeID).Collection(routesSubcollection).Doc(routeID)

	var updated driverAssignment
	var reassigned bool
	err := fs.RunTransaction(ctx, func(ctx context.Context, tx *cloudfirestore.Transaction) error {
		snap, err := tx.Get(assignRef)
		if err != nil {
			if status.Code(err) == codes.NotFound {
				return fmt.Errorf("not_found")
			}
			return err
		}
		_ = snap.DataTo(&updated)
		if updated.DriverID != uid {
			return fmt.Errorf("not_assigned_driver")
		}
		if updated.Status != "pending" {
			return fmt.Errorf("not_pending")
		}
		if updated.ExpiresAt.Before(time.Now().UTC()) {
			updated.Status = "expired"
			updated.UpdatedAt = time.Now().UTC()
			return tx.Set(assignRef, updated)
		}
		if accept {
			updated.Status = "assigned"
			updated.UpdatedAt = time.Now().UTC()
			if err := tx.Set(assignRef, updated); err != nil {
				return err
			}
			// Create route.
			now := time.Now().UTC()
			rt := driverRoute{
				RouteID:     routeID,
				DriverID:    uid,
				DeliveryIDs: []string{updated.OrderID},
				Status:      "planned",
				CreatedAt:   now,
				UpdatedAt:   now,
			}
			if err := tx.Set(routeRef, rt); err != nil {
				return err
			}
			return nil
		}

		now := time.Now().UTC()
		if updated.ExpiresAt.Before(now) {
			updated.Status = "expired"
			updated.DriverID = ""
			updated.UpdatedAt = now
			return tx.Set(assignRef, updated)
		}
		nextIdx := updated.CandidateIdx + 1
		if nextIdx < len(updated.Candidates) {
			updated.DriverID = updated.Candidates[nextIdx].DriverID
			updated.CandidateIdx = nextIdx
			updated.Status = "pending"
			updated.ExpiresAt = now.Add(time.Duration(cfg.AssignmentTTLSeconds) * time.Second)
			updated.UpdatedAt = now
			reassigned = true
			return tx.Set(assignRef, updated)
		}

		updated.Status = "expired"
		updated.DriverID = ""
		updated.UpdatedAt = now
		return tx.Set(assignRef, updated)
	})
	if err != nil {
		msg := err.Error()
		switch msg {
		case "not_found":
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "not_found"})
		case "not_assigned_driver":
			writeJSON(w, http.StatusForbidden, map[string]string{"error": "forbidden"})
		case "not_pending":
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "not_pending"})
		default:
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "update_failed"})
		}
		return
	}

	// Best-effort patch order-service + publish event.
	if accept {
		if updated.Status != "assigned" {
			writeJSON(w, http.StatusConflict, map[string]string{"error": "assignment_expired"})
			return
		}
		_ = patchOrderDelivery(ctx, httpClient, orderTokenSrc, cfg.OrderServiceURL, updated.OrderID, map[string]any{
			"assignedDriverId":      updated.DriverID,
			"assignedRouteId":       routeID,
			"assignmentStatus":      "assigned",
			"deliveryStatusSummary": "driver_assigned",
		})
		_ = publishDispatchEvent(ctx, pubsubClient, cfg, dispatchEvent{
			Kind:         "driver_assigned",
			StoreID:      storeID,
			OrderID:      updated.OrderID,
			AssignmentID: updated.AssignmentID,
			DriverID:     updated.DriverID,
			RouteID:      routeID,
			CreatedAt:    time.Now().UTC().Format(time.RFC3339),
		})
	} else {
		prevDriver := uid
		_ = publishDispatchEvent(ctx, pubsubClient, cfg, dispatchEvent{
			Kind:         "assignment_declined",
			StoreID:      storeID,
			OrderID:      updated.OrderID,
			AssignmentID: updated.AssignmentID,
			DriverID:     prevDriver,
			CreatedAt:    time.Now().UTC().Format(time.RFC3339),
		})
		if reassigned {
			_ = enqueueAssignmentExpiry(ctx, tasksClient, cfg, storeID, assignmentID, updated.ExpiresAt)
			_ = patchOrderDelivery(ctx, httpClient, orderTokenSrc, cfg.OrderServiceURL, updated.OrderID, map[string]any{
				"assignedDriverId": updated.DriverID,
				"assignmentStatus": "pending",
			})
			_ = publishDispatchEvent(ctx, pubsubClient, cfg, dispatchEvent{
				Kind:         "assignment_request",
				StoreID:      storeID,
				OrderID:      updated.OrderID,
				AssignmentID: updated.AssignmentID,
				DriverID:     updated.DriverID,
				CreatedAt:    time.Now().UTC().Format(time.RFC3339),
				Payload: map[string]any{
					"expiresAt": updated.ExpiresAt.UTC().Format(time.RFC3339),
				},
			})
		} else if updated.Status == "expired" {
			_ = patchOrderDelivery(ctx, httpClient, orderTokenSrc, cfg.OrderServiceURL, updated.OrderID, map[string]any{
				"assignedDriverId": "",
				"assignmentStatus": "expired",
			})
			_ = publishDispatchEvent(ctx, pubsubClient, cfg, dispatchEvent{
				Kind:         "assignment_expired",
				StoreID:      storeID,
				OrderID:      updated.OrderID,
				AssignmentID: updated.AssignmentID,
				CreatedAt:    time.Now().UTC().Format(time.RFC3339),
			})
		}
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func handleAssignmentExpiry(
	w http.ResponseWriter,
	r *http.Request,
	fs *cloudfirestore.Client,
	cfg *serviceConfig,
	pubsubClient *cloudpubsub.Client,
	tasksClient *cloudtasks.Client,
	httpClient *http.Client,
	orderTokenSrc oauth2.TokenSource,
) {
	if strings.TrimSpace(cfg.CloudTasksOIDCAudience) != "" {
		if !verifyGoogleOidc(r, cfg.CloudTasksOIDCAudience) {
			writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
			return
		}
	}

	var payload struct {
		StoreID      string `json:"storeId"`
		AssignmentID string `json:"assignmentId"`
	}
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
		return
	}
	storeID := strings.TrimSpace(payload.StoreID)
	assignmentID := strings.TrimSpace(payload.AssignmentID)
	if storeID == "" || assignmentID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_ids"})
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 8*time.Second)
	defer cancel()

	reassigned, updated, err := advanceAssignment(ctx, fs, cfg, tasksClient, storeID, assignmentID)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "advance_failed"})
		return
	}
	if reassigned {
		_ = patchOrderDelivery(ctx, httpClient, orderTokenSrc, cfg.OrderServiceURL, updated.OrderID, map[string]any{
			"assignedDriverId": updated.DriverID,
			"assignmentStatus": "pending",
		})
		_ = publishDispatchEvent(ctx, pubsubClient, cfg, dispatchEvent{
			Kind:         "assignment_request",
			StoreID:      storeID,
			OrderID:      updated.OrderID,
			AssignmentID: updated.AssignmentID,
			DriverID:     updated.DriverID,
			CreatedAt:    time.Now().UTC().Format(time.RFC3339),
			Payload: map[string]any{
				"expiresAt": updated.ExpiresAt.UTC().Format(time.RFC3339),
			},
		})
	} else if updated.Status == "expired" {
		_ = patchOrderDelivery(ctx, httpClient, orderTokenSrc, cfg.OrderServiceURL, updated.OrderID, map[string]any{
			"assignedDriverId": "",
			"assignmentStatus": "expired",
		})
		_ = publishDispatchEvent(ctx, pubsubClient, cfg, dispatchEvent{
			Kind:         "assignment_expired",
			StoreID:      storeID,
			OrderID:      updated.OrderID,
			AssignmentID: updated.AssignmentID,
			CreatedAt:    time.Now().UTC().Format(time.RFC3339),
		})
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func advanceAssignment(
	ctx context.Context,
	fs *cloudfirestore.Client,
	cfg *serviceConfig,
	tasksClient *cloudtasks.Client,
	storeID string,
	assignmentID string,
) (bool, driverAssignment, error) {
	assignRef := fs.Collection(storesCollection).Doc(storeID).Collection(assignmentsSubcollection).Doc(assignmentID)
	var updated driverAssignment
	var reassigned bool
	err := fs.RunTransaction(ctx, func(ctx context.Context, tx *cloudfirestore.Transaction) error {
		snap, err := tx.Get(assignRef)
		if err != nil {
			return err
		}
		_ = snap.DataTo(&updated)
		if updated.Status != "pending" {
			return nil
		}
		now := time.Now().UTC()
		nextIdx := updated.CandidateIdx + 1
		if nextIdx < len(updated.Candidates) {
			updated.DriverID = updated.Candidates[nextIdx].DriverID
			updated.CandidateIdx = nextIdx
			updated.Status = "pending"
			updated.ExpiresAt = now.Add(time.Duration(cfg.AssignmentTTLSeconds) * time.Second)
			updated.UpdatedAt = now
			reassigned = true
		} else {
			updated.Status = "expired"
			updated.DriverID = ""
			updated.UpdatedAt = now
		}
		return tx.Set(assignRef, updated)
	})
	if err != nil {
		return false, driverAssignment{}, err
	}
	if reassigned {
		_ = enqueueAssignmentExpiry(ctx, tasksClient, cfg, storeID, assignmentID, updated.ExpiresAt)
	}
	return reassigned, updated, nil
}

func getCurrentRoute(w http.ResponseWriter, r *http.Request, fs *cloudfirestore.Client, storeID string) {
	uid := authUID(r.Context())
	if uid == "" {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
		return
	}
	if !isDriverForStore(r.Context(), fs, storeID) {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "forbidden"})
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 4*time.Second)
	defer cancel()
	iter := fs.Collection(storesCollection).Doc(storeID).Collection(routesSubcollection).Where("driverId", "==", uid).Where("status", "in", []any{"planned", "in_progress"}).Limit(1).Documents(ctx)
	defer iter.Stop()
	doc, err := iter.Next()
	if err != nil || doc == nil || !doc.Exists() {
		writeJSON(w, http.StatusOK, map[string]any{"route": nil})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"routeId": doc.Ref.ID, "route": doc.Data()})
}

func updateStopStatus(
	w http.ResponseWriter,
	r *http.Request,
	fs *cloudfirestore.Client,
	cfg *serviceConfig,
	pubsubClient *cloudpubsub.Client,
	httpClient *http.Client,
	orderTokenSrc oauth2.TokenSource,
	storeID string,
	routeID string,
	deliveryID string,
) {
	uid := authUID(r.Context())
	if uid == "" {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
		return
	}

	var payload struct {
		Status string `json:"status"`
	}
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
		return
	}
	statusKey := normalizeDeliveryStatus(payload.Status)
	if statusKey == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_status"})
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 8*time.Second)
	defer cancel()

	routeRef := fs.Collection(storesCollection).Doc(storeID).Collection(routesSubcollection).Doc(routeID)
	routeSnap, err := routeRef.Get(ctx)
	if err != nil {
		if status.Code(err) == codes.NotFound {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "route_not_found"})
			return
		}
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "route_fetch_failed"})
		return
	}
	var route driverRoute
	if err := routeSnap.DataTo(&route); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "route_parse_failed"})
		return
	}
	if route.DriverID != uid {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "forbidden"})
		return
	}
	found := false
	for _, id := range route.DeliveryIDs {
		if id == deliveryID {
			found = true
			break
		}
	}
	if !found {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "delivery_not_in_route"})
		return
	}

	if statusKey == "picked_up" || statusKey == "out_for_delivery" {
		if strings.TrimSpace(route.Status) == "" || route.Status == "planned" {
			route.Status = "in_progress"
			route.UpdatedAt = time.Now().UTC()
			_, _ = routeRef.Set(ctx, route)
		}
	}

	_ = patchOrderDelivery(ctx, httpClient, orderTokenSrc, cfg.OrderServiceURL, deliveryID, map[string]any{
		"deliveryStatusSummary": statusKey,
	})
	_ = publishDispatchEvent(ctx, pubsubClient, cfg, dispatchEvent{
		Kind:      statusKey,
		StoreID:   storeID,
		OrderID:   deliveryID,
		RouteID:   routeID,
		DriverID:  uid,
		CreatedAt: time.Now().UTC().Format(time.RFC3339),
	})

	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func normalizeDeliveryStatus(value string) string {
	raw := strings.ToLower(strings.TrimSpace(value))
	switch raw {
	case "picked", "picked_up", "pickup", "picked-up":
		return "picked_up"
	case "out_for_delivery", "out for delivery", "en_route", "enroute", "in_transit", "in transit":
		return "out_for_delivery"
	case "delivered", "complete", "completed":
		return "delivered"
	case "failed", "delivery_failed":
		return "delivery_failed"
	case "cancelled", "canceled":
		return "cancelled"
	case "delayed", "delay", "delivery_delayed":
		return "delivery_delayed"
	default:
		return ""
	}
}

func publishDispatchEvent(ctx context.Context, client *cloudpubsub.Client, cfg *serviceConfig, evt dispatchEvent) error {
	if client == nil {
		return nil
	}
	topicID := strings.TrimSpace(cfg.DispatchEventsTopic)
	if topicID == "" {
		topicID = "dispatch-events"
	}
	topic := client.Topic(topicID)
	payload, err := json.Marshal(evt)
	if err != nil {
		return err
	}
	res := topic.Publish(ctx, &cloudpubsub.Message{Data: payload})
	_, err = res.Get(ctx)
	return err
}

func enqueueAssignmentExpiry(
	ctx context.Context,
	client *cloudtasks.Client,
	cfg *serviceConfig,
	storeID string,
	assignmentID string,
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

	safeID := sanitizeTaskID(storeID + "-" + assignmentID)
	taskName := fmt.Sprintf("projects/%s/locations/%s/queues/%s/tasks/assignment-expire-%s", projectID, location, queue, safeID)
	parent := fmt.Sprintf("projects/%s/locations/%s/queues/%s", projectID, location, queue)

	body, _ := json.Marshal(map[string]string{
		"storeId":      storeID,
		"assignmentId": assignmentID,
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
					Url:        strings.TrimRight(targetBase, "/") + "/tasks/assignments/expire",
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
		// Ignore already-exists errors for idempotency.
		if status.Code(err) == codes.AlreadyExists {
			return nil
		}
		return err
	}
	return nil
}

func sanitizeTaskID(id string) string {
	if id == "" {
		return "unknown"
	}
	out := make([]rune, 0, len(id))
	for _, r := range id {
		if (r >= 'a' && r <= 'z') ||
			(r >= 'A' && r <= 'Z') ||
			(r >= '0' && r <= '9') ||
			r == '-' || r == '_' {
			out = append(out, r)
		} else {
			out = append(out, '_')
		}
	}
	return string(out)
}

func patchOrderDelivery(ctx context.Context, httpClient *http.Client, tokenSrc oauth2.TokenSource, baseURL, orderID string, fields map[string]any) error {
	if httpClient == nil || tokenSrc == nil {
		return nil
	}
	baseURL = strings.TrimRight(strings.TrimSpace(baseURL), "/")
	if baseURL == "" || orderID == "" {
		return nil
	}
	b, _ := json.Marshal(fields)
	req, _ := http.NewRequestWithContext(ctx, http.MethodPatch, baseURL+"/orders/"+url.PathEscape(orderID)+"/delivery", bytes.NewReader(b))
	req.Header.Set("Content-Type", "application/json")
	tok, err := tokenSrc.Token()
	if err == nil && tok != nil && tok.AccessToken != "" {
		req.Header.Set("Authorization", "Bearer "+tok.AccessToken)
	}
	resp, err := httpClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("order_service_patch_failed status=%d body=%s", resp.StatusCode, strings.TrimSpace(string(body)))
	}
	return nil
}

func writeJSON(w http.ResponseWriter, status int, payload interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(payload)
}

func verifyGoogleOidc(r *http.Request, audience string) bool {
	authHeader := r.Header.Get("Authorization")
	if !strings.HasPrefix(authHeader, "Bearer ") {
		return false
	}
	token := strings.TrimSpace(strings.TrimPrefix(authHeader, "Bearer "))
	if token == "" {
		return false
	}
	payload, err := idtoken.Validate(r.Context(), token, audience)
	if err != nil || payload == nil {
		return false
	}
	return true
}

func splitCSV(s string) []string {
	if strings.TrimSpace(s) == "" {
		return nil
	}
	parts := strings.Split(s, ",")
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		if v := strings.TrimSpace(p); v != "" {
			out = append(out, v)
		}
	}
	return out
}

func stringOrDefault(value interface{}, fallback string) string {
	if value == nil {
		return fallback
	}
	switch v := value.(type) {
	case string:
		if v == "" {
			return fallback
		}
		return v
	case int64:
		return fmt.Sprintf("%d", v)
	case float64:
		return fmt.Sprintf("%f", v)
	default:
		return fallback
	}
}

func intFromEnv(key string, def int) int {
	raw := strings.TrimSpace(os.Getenv(key))
	if raw == "" {
		return def
	}
	if n, err := strconv.Atoi(raw); err == nil {
		return n
	}
	return def
}

func anyToFloat64(v any) float64 {
	switch t := v.(type) {
	case float64:
		return t
	case float32:
		return float64(t)
	case int:
		return float64(t)
	case int64:
		return float64(t)
	case json.Number:
		f, _ := t.Float64()
		return f
	case string:
		f, _ := strconv.ParseFloat(strings.TrimSpace(t), 64)
		return f
	default:
		return 0
	}
}
