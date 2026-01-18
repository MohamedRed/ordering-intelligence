package main

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"os"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/go-chi/cors"
	"github.com/gorilla/websocket"
	"github.com/joho/godotenv"
	agentcontext "github.com/ordering-intelligence/agentcontext"
	sharedconfig "github.com/ordering-intelligence/sharedconfig"
	"golang.org/x/oauth2"
	"google.golang.org/api/idtoken"
	"google.golang.org/api/iterator"
	"google.golang.org/api/option"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

const (
	channelRoutesCollection   = "channel_routes"
	channelSessionsCollection = "channel_sessions"
	tvPairingsCollection      = "tv_pairings"
	tvSessionsCollection      = "tv_sessions"
	storesCollection          = "stores"
	tenantsCollection         = "tenants"
	orderDraftsCollection     = "order_drafts"
)

type serviceConfig struct {
	Port                      string
	Environment               string
	ProjectID                 string
	Credentials               string
	ElevenLabsAPIKey          string
	ElevenLabsAPIBase         string
	DefaultAgentID            string
	TelegramBotToken          string
	TelegramSecretToken       string
	TelegramBotUsername       string
	TelegramWebAppURL         string
	DiscordClientID           string
	DiscordClientSecret       string
	DiscordPublicKey          string
	DiscordAPIBase            string
	DiscordBotToken           string
	DiscordActivityChannelID  string
	SnapchatClientID          string
	SnapchatClientSecret      string
	SnapchatAccountsBaseURL   string
	SnapchatAPIBaseURL        string
	FacebookAppID             string
	FacebookAppSecret         string
	FacebookGraphBaseURL      string
	TikTokClientKey           string
	TikTokClientSecret        string
	TikTokAPIBaseURL          string
	SessionIdleMinutes        int
	MobileSessionSecret       string
	MobileSessionSkewSeconds  int
	InternalAuthAudience      string
	InternalAllowedEmails     []string
	OrderServiceURL           string
	PaymentsServiceURL        string
	DispatchServiceURL        string
	CustomerProfileServiceURL string
	TypesenseHost             string
	TypesenseAPIKey           string
	TypesenseCollection       string
}

type channelSession struct {
	Channel                  string                   `firestore:"channel" json:"channel"`
	AccountID                string                   `firestore:"account_id" json:"accountId"`
	UserID                   string                   `firestore:"user_id" json:"userId"`
	ThreadID                 string                   `firestore:"thread_id,omitempty" json:"threadId,omitempty"`
	DisplayName              string                   `firestore:"display_name,omitempty" json:"displayName,omitempty"`
	TenantID                 string                   `firestore:"tenant_id,omitempty" json:"tenantId,omitempty"`
	CustomerID               string                   `firestore:"customer_id,omitempty" json:"customerId,omitempty"`
	StoreID                  string                   `firestore:"store_id,omitempty" json:"storeId,omitempty"`
	BusinessType             string                   `firestore:"business_type,omitempty" json:"businessType,omitempty"`
	AuthProvider             string                   `firestore:"auth_provider,omitempty" json:"authProvider,omitempty"`
	ClientPlatform           string                   `firestore:"client_platform,omitempty" json:"clientPlatform,omitempty"`
	ClientApp                string                   `firestore:"client_app,omitempty" json:"clientApp,omitempty"`
	ClientVersion            string                   `firestore:"client_version,omitempty" json:"clientVersion,omitempty"`
	ElevenLabsConversationID string                   `firestore:"elevenlabs_conversation_id,omitempty" json:"conversationId,omitempty"`
	SeededIntro              string                   `firestore:"seeded_intro,omitempty" json:"seededIntro,omitempty"`
	SeededCategories         []string                 `firestore:"seeded_categories,omitempty" json:"seededCategories,omitempty"`
	SeededSource             string                   `firestore:"seeded_source,omitempty" json:"seededSource,omitempty"`
	SeededAt                 time.Time                `firestore:"seeded_at,omitempty" json:"seededAt,omitempty"`
	SeededContextSent        bool                     `firestore:"seeded_context_sent,omitempty" json:"seededContextSent,omitempty"`
	PendingStoreChoices      []storeChoice            `firestore:"pending_store_choices,omitempty" json:"pendingStoreChoices,omitempty"`
	PendingDiscordSelection  *discordPendingSelection `firestore:"pending_discord_selection,omitempty" json:"pendingDiscordSelection,omitempty"`
	LastSeenAt               time.Time                `firestore:"last_seen_at" json:"lastSeenAt"`
	CreatedAt                time.Time                `firestore:"created_at" json:"createdAt"`
}

type storeChoice struct {
	Name              string `firestore:"name" json:"name"`
	TenantID          string `firestore:"tenant_id" json:"tenantId"`
	StoreID           string `firestore:"store_id" json:"storeId"`
	BusinessType      string `firestore:"business_type" json:"businessType"`
	DeliveryEnabled   bool   `firestore:"delivery_enabled,omitempty" json:"deliveryEnabled,omitempty"`
	DeliveryFleetMode string `firestore:"delivery_fleet_mode,omitempty" json:"deliveryFleetMode,omitempty"`
}

type sessionManager struct {
	mu         sync.Mutex
	sessions   map[string]*wsSession
	idleWindow time.Duration
}

type wsSession struct {
	mu             sync.Mutex
	conn           *websocket.Conn
	agentID        string
	conversationID string
	lastUsed       time.Time
}

func main() {
	_ = godotenv.Load()

	cfg, err := loadConfig()
	if err != nil {
		log.Fatalf("failed to load config: %v", err)
	}

	ctx := context.Background()
	firestoreClient, err := newFirestoreClient(ctx, cfg)
	if err != nil {
		log.Fatalf("failed to create firestore client: %v", err)
	}
	defer firestoreClient.Close()

	orderHTTPClient := &http.Client{Timeout: 20 * time.Second}
	var orderTokenSrc oauth2.TokenSource
	if strings.TrimSpace(cfg.OrderServiceURL) != "" {
		orderTokenSrc, err = idtoken.NewTokenSource(ctx, cfg.OrderServiceURL)
		if err != nil {
			log.Fatalf("failed to create order-service idtoken source: %v", err)
		}
		orderHTTPClient = oauth2.NewClient(ctx, orderTokenSrc)
	}
	dispatchHTTPClient := &http.Client{Timeout: 20 * time.Second}
	if strings.TrimSpace(cfg.DispatchServiceURL) != "" {
		dispatchTokenSrc, err := idtoken.NewTokenSource(ctx, cfg.DispatchServiceURL)
		if err != nil {
			log.Fatalf("failed to create dispatch-service idtoken source: %v", err)
		}
		dispatchHTTPClient = oauth2.NewClient(ctx, dispatchTokenSrc)
	}
	paymentsHTTPClient := &http.Client{Timeout: 20 * time.Second}
	if strings.TrimSpace(cfg.PaymentsServiceURL) != "" {
		paymentsTokenSrc, err := idtoken.NewTokenSource(ctx, cfg.PaymentsServiceURL)
		if err != nil {
			log.Fatalf("failed to create payments-service idtoken source: %v", err)
		}
		paymentsHTTPClient = oauth2.NewClient(ctx, paymentsTokenSrc)
	}

	manager := &sessionManager{
		sessions:   make(map[string]*wsSession),
		idleWindow: time.Duration(cfg.SessionIdleMinutes) * time.Minute,
	}
	manager.startCleanupLoop()

	router := chi.NewRouter()
	router.Use(middleware.RequestID)
	router.Use(middleware.Logger)
	router.Use(middleware.Recoverer)
	router.Use(cors.Handler(cors.Options{
		AllowedOrigins:   allowedOrigins(),
		AllowedMethods:   []string{"GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"},
		AllowedHeaders:   []string{"Accept", "Authorization", "Content-Type", "X-Requested-With"},
		ExposedHeaders:   []string{"Link"},
		AllowCredentials: false,
		MaxAge:           300,
	}))

	healthzHandler := func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{
			"status":      "ok",
			"service":     "channel-gateway",
			"environment": cfg.Environment,
		})
	}
	router.Get("/healthz", healthzHandler)
	router.Get("/healthz/", healthzHandler)

	router.Post("/telegram/webhook/{accountId}", func(w http.ResponseWriter, r *http.Request) {
		handleTelegramWebhook(w, r, cfg, firestoreClient, manager, orderHTTPClient)
	})

	router.Post("/telegram/webapp/session/start", func(w http.ResponseWriter, r *http.Request) {
		handleWebAppSessionStart(w, r, cfg, firestoreClient)
	})
	registerWebAppRoutes(router, "/telegram/webapp", cfg, firestoreClient, orderHTTPClient, paymentsHTTPClient, dispatchHTTPClient, manager)

	router.Post("/discord/webapp/session/start", func(w http.ResponseWriter, r *http.Request) {
		handleDiscordWebAppSessionStart(w, r, cfg, firestoreClient)
	})
	registerWebAppRoutes(router, "/discord/webapp", cfg, firestoreClient, orderHTTPClient, paymentsHTTPClient, dispatchHTTPClient, manager)
	router.Post("/discord/interactions", func(w http.ResponseWriter, r *http.Request) {
		handleDiscordInteractions(w, r, cfg, firestoreClient)
	})

	router.Post("/snapchat/webapp/session/start", func(w http.ResponseWriter, r *http.Request) {
		handleSnapchatWebAppSessionStart(w, r, cfg, firestoreClient)
	})
	registerWebAppRoutes(router, "/snapchat/webapp", cfg, firestoreClient, orderHTTPClient, paymentsHTTPClient, dispatchHTTPClient, manager)

	registerWebAppRoutes(router, "/mobile", cfg, firestoreClient, orderHTTPClient, paymentsHTTPClient, dispatchHTTPClient, manager)

	registerWebAppRoutes(router, "/tv", cfg, firestoreClient, orderHTTPClient, paymentsHTTPClient, dispatchHTTPClient, manager)
	registerTvRoutes(router, cfg, firestoreClient)

	router.Post("/internal/test/webapp/session", func(w http.ResponseWriter, r *http.Request) {
		handleWebAppTestSession(w, r, cfg, firestoreClient)
	})

	router.Post("/mobile/session/start", func(w http.ResponseWriter, r *http.Request) {
		handleMobileSessionStart(w, r, cfg, firestoreClient)
	})
	router.Get("/mobile/session", func(w http.ResponseWriter, r *http.Request) {
		handleMobileSessionGet(w, r, cfg, firestoreClient)
	})
	router.Delete("/mobile/session", func(w http.ResponseWriter, r *http.Request) {
		handleMobileSessionEnd(w, r, cfg, firestoreClient)
	})
	router.Post("/mobile/device-tokens", func(w http.ResponseWriter, r *http.Request) {
		handleMobileDeviceTokenRegister(w, r, cfg, firestoreClient)
	})
	router.Delete("/mobile/device-tokens", func(w http.ResponseWriter, r *http.Request) {
		handleMobileDeviceTokenDelete(w, r, cfg, firestoreClient)
	})
	router.Get("/mobile/payment-methods", func(w http.ResponseWriter, r *http.Request) {
		handleMobilePaymentMethodsList(w, r, cfg, firestoreClient, paymentsHTTPClient)
	})
	router.Post("/mobile/payment-methods/setup-intent", func(w http.ResponseWriter, r *http.Request) {
		handleMobilePaymentSetupIntent(w, r, cfg, firestoreClient, paymentsHTTPClient)
	})
	router.Post("/mobile/payment-methods/default", func(w http.ResponseWriter, r *http.Request) {
		handleMobilePaymentDefault(w, r, cfg, firestoreClient, paymentsHTTPClient)
	})
	router.Post("/mobile/orders/{orderId}/payment-intent", func(w http.ResponseWriter, r *http.Request) {
		orderID := chi.URLParam(r, "orderId")
		if orderID == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_order_id"})
			return
		}
		handleMobileOrderPaymentIntent(w, r, cfg, firestoreClient, paymentsHTTPClient, orderID)
	})
	router.Post("/mobile/orders/{orderId}/pay-default", func(w http.ResponseWriter, r *http.Request) {
		orderID := chi.URLParam(r, "orderId")
		if orderID == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_order_id"})
			return
		}
		handleMobileOrderPayDefault(w, r, cfg, firestoreClient, paymentsHTTPClient, orderID)
	})
	router.Post("/mobile/group-orders/{groupOrderId}/payment-intent", func(w http.ResponseWriter, r *http.Request) {
		groupOrderID := chi.URLParam(r, "groupOrderId")
		if groupOrderID == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_group_order_id"})
			return
		}
		handleMobileGroupOrderPaymentIntent(w, r, cfg, firestoreClient, paymentsHTTPClient, groupOrderID)
	})
	router.Post("/mobile/group-orders/{groupOrderId}/pay-default", func(w http.ResponseWriter, r *http.Request) {
		groupOrderID := chi.URLParam(r, "groupOrderId")
		if groupOrderID == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_group_order_id"})
			return
		}
		handleMobileGroupOrderPayDefault(w, r, cfg, firestoreClient, paymentsHTTPClient, groupOrderID)
	})

	router.Post("/snap/lens/session/start", func(w http.ResponseWriter, r *http.Request) {
		handleLensSessionStart(w, r, cfg, firestoreClient)
	})
	router.Post("/snap/lens/store/select", func(w http.ResponseWriter, r *http.Request) {
		handleLensStoreSelect(w, r, firestoreClient)
	})
	router.Post("/snap/lens/cart/update", func(w http.ResponseWriter, r *http.Request) {
		handleLensCartUpdate(w, r, firestoreClient)
	})
	router.Post("/snap/lens/voice/turn", func(w http.ResponseWriter, r *http.Request) {
		handleLensVoiceTurn(w, r, cfg, firestoreClient, manager)
	})

	log.Printf("Channel gateway listening on port %s", cfg.Port)
	if err := http.ListenAndServe(":"+cfg.Port, router); err != nil {
		log.Fatalf("server failed: %v", err)
	}
}

func loadConfig() (*serviceConfig, error) {
	values, err := sharedconfig.Load("channel-gateway", nil)
	if err != nil {
		return nil, err
	}

	port := os.Getenv("PORT")
	if port == "" {
		port = "8090"
	}

	idleMinutes := intOrDefault(values["SESSION_IDLE_MINUTES"], 20)
	mobileSkew := intOrDefault(values["MOBILE_SESSION_MAX_SKEW_SECONDS"], 300)

	return &serviceConfig{
		Port:        port,
		Environment: stringOrDefault(values["ENVIRONMENT"], "development"),
		ProjectID:   stringOrDefault(values["FIRESTORE_PROJECT_ID"], ""),
		Credentials: stringOrDefault(values["GOOGLE_APPLICATION_CREDENTIALS"], ""),
		ElevenLabsAPIKey: strings.TrimSpace(firstNonEmpty(
			os.Getenv("ELEVENLABS_API_KEY"),
			stringOrDefault(values["ELEVENLABS_API_KEY"], ""),
		)),
		ElevenLabsAPIBase: strings.TrimSpace(firstNonEmpty(
			os.Getenv("ELEVENLABS_API_BASE_URL"),
			stringOrDefault(values["ELEVENLABS_API_BASE_URL"], "https://api.elevenlabs.io"),
		)),
		DefaultAgentID: strings.TrimSpace(firstNonEmpty(
			os.Getenv("ELEVENLABS_DEFAULT_AGENT_ID"),
			stringOrDefault(values["ELEVENLABS_DEFAULT_AGENT_ID"], ""),
		)),
		TelegramBotToken: strings.TrimSpace(firstNonEmpty(
			os.Getenv("TELEGRAM_BOT_TOKEN"),
			stringOrDefault(values["TELEGRAM_BOT_TOKEN"], ""),
		)),
		TelegramSecretToken: strings.TrimSpace(firstNonEmpty(
			os.Getenv("TELEGRAM_WEBHOOK_SECRET"),
			stringOrDefault(values["TELEGRAM_WEBHOOK_SECRET"], ""),
		)),
		TelegramBotUsername: strings.TrimSpace(firstNonEmpty(
			os.Getenv("TELEGRAM_BOT_USERNAME"),
			stringOrDefault(values["TELEGRAM_BOT_USERNAME"], ""),
		)),
		TelegramWebAppURL: strings.TrimSpace(firstNonEmpty(
			os.Getenv("TELEGRAM_WEBAPP_URL"),
			stringOrDefault(values["TELEGRAM_WEBAPP_URL"], ""),
		)),
		DiscordClientID: strings.TrimSpace(firstNonEmpty(
			os.Getenv("DISCORD_CLIENT_ID"),
			stringOrDefault(values["DISCORD_CLIENT_ID"], ""),
		)),
		DiscordClientSecret: strings.TrimSpace(firstNonEmpty(
			os.Getenv("DISCORD_CLIENT_SECRET"),
			stringOrDefault(values["DISCORD_CLIENT_SECRET"], ""),
		)),
		DiscordPublicKey: strings.TrimSpace(firstNonEmpty(
			os.Getenv("DISCORD_PUBLIC_KEY"),
			stringOrDefault(values["DISCORD_PUBLIC_KEY"], ""),
		)),
		DiscordAPIBase: strings.TrimSpace(firstNonEmpty(
			os.Getenv("DISCORD_API_BASE_URL"),
			stringOrDefault(values["DISCORD_API_BASE_URL"], "https://discord.com/api/v10"),
		)),
		DiscordBotToken: strings.TrimSpace(firstNonEmpty(
			os.Getenv("DISCORD_BOT_TOKEN"),
			stringOrDefault(values["DISCORD_BOT_TOKEN"], ""),
		)),
		DiscordActivityChannelID: strings.TrimSpace(firstNonEmpty(
			os.Getenv("DISCORD_ACTIVITY_CHANNEL_ID"),
			stringOrDefault(values["DISCORD_ACTIVITY_CHANNEL_ID"], ""),
		)),
		SnapchatClientID: strings.TrimSpace(firstNonEmpty(
			os.Getenv("SNAPCHAT_CLIENT_ID"),
			stringOrDefault(values["SNAPCHAT_CLIENT_ID"], ""),
		)),
		SnapchatClientSecret: strings.TrimSpace(firstNonEmpty(
			os.Getenv("SNAPCHAT_CLIENT_SECRET"),
			stringOrDefault(values["SNAPCHAT_CLIENT_SECRET"], ""),
		)),
		SnapchatAccountsBaseURL: strings.TrimSpace(firstNonEmpty(
			os.Getenv("SNAPCHAT_ACCOUNTS_BASE_URL"),
			stringOrDefault(values["SNAPCHAT_ACCOUNTS_BASE_URL"], "https://accounts.snapchat.com"),
		)),
		SnapchatAPIBaseURL: strings.TrimSpace(firstNonEmpty(
			os.Getenv("SNAPCHAT_API_BASE_URL"),
			stringOrDefault(values["SNAPCHAT_API_BASE_URL"], "https://kit.snapchat.com"),
		)),
		FacebookAppID: strings.TrimSpace(firstNonEmpty(
			os.Getenv("FACEBOOK_APP_ID"),
			stringOrDefault(values["FACEBOOK_APP_ID"], ""),
		)),
		FacebookAppSecret: strings.TrimSpace(firstNonEmpty(
			os.Getenv("FACEBOOK_APP_SECRET"),
			stringOrDefault(values["FACEBOOK_APP_SECRET"], ""),
		)),
		FacebookGraphBaseURL: strings.TrimSpace(firstNonEmpty(
			os.Getenv("FACEBOOK_GRAPH_BASE_URL"),
			stringOrDefault(values["FACEBOOK_GRAPH_BASE_URL"], "https://graph.facebook.com"),
		)),
		TikTokClientKey: strings.TrimSpace(firstNonEmpty(
			os.Getenv("TIKTOK_CLIENT_KEY"),
			stringOrDefault(values["TIKTOK_CLIENT_KEY"], ""),
		)),
		TikTokClientSecret: strings.TrimSpace(firstNonEmpty(
			os.Getenv("TIKTOK_CLIENT_SECRET"),
			stringOrDefault(values["TIKTOK_CLIENT_SECRET"], ""),
		)),
		TikTokAPIBaseURL: strings.TrimSpace(firstNonEmpty(
			os.Getenv("TIKTOK_API_BASE_URL"),
			stringOrDefault(values["TIKTOK_API_BASE_URL"], "https://open.tiktokapis.com"),
		)),
		SessionIdleMinutes: idleMinutes,
		MobileSessionSecret: strings.TrimSpace(firstNonEmpty(
			os.Getenv("MOBILE_SESSION_SHARED_SECRET"),
			stringOrDefault(values["MOBILE_SESSION_SHARED_SECRET"], ""),
		)),
		MobileSessionSkewSeconds: mobileSkew,
		InternalAuthAudience: strings.TrimSpace(firstNonEmpty(
			os.Getenv("INTERNAL_AUTH_AUDIENCE"),
			stringOrDefault(values["INTERNAL_AUTH_AUDIENCE"], ""),
		)),
		InternalAllowedEmails: splitCSV(firstNonEmpty(
			os.Getenv("INTERNAL_ALLOWED_EMAILS"),
			stringOrDefault(values["INTERNAL_ALLOWED_EMAILS"], ""),
		)),
		OrderServiceURL: strings.TrimSpace(firstNonEmpty(
			os.Getenv("ORDER_SERVICE_URL"),
			stringOrDefault(values["ORDER_SERVICE_URL"], ""),
		)),
		PaymentsServiceURL: strings.TrimSpace(firstNonEmpty(
			os.Getenv("PAYMENTS_SERVICE_URL"),
			stringOrDefault(values["PAYMENTS_SERVICE_URL"], ""),
		)),
		DispatchServiceURL: strings.TrimSpace(firstNonEmpty(
			os.Getenv("DISPATCH_SERVICE_URL"),
			stringOrDefault(values["DISPATCH_SERVICE_URL"], ""),
		)),
		CustomerProfileServiceURL: strings.TrimSpace(firstNonEmpty(
			os.Getenv("CUSTOMER_PROFILE_SERVICE_URL"),
			stringOrDefault(values["CUSTOMER_PROFILE_SERVICE_URL"], ""),
		)),
		TypesenseHost: strings.TrimSpace(firstNonEmpty(
			os.Getenv("TYPESENSE_HOST"),
			stringOrDefault(values["TYPESENSE_HOST"], ""),
		)),
		TypesenseAPIKey: strings.TrimSpace(firstNonEmpty(
			os.Getenv("TYPESENSE_SEARCH_API_KEY"),
			stringOrDefault(values["TYPESENSE_SEARCH_API_KEY"], ""),
		)),
		TypesenseCollection: strings.TrimSpace(firstNonEmpty(
			os.Getenv("TYPESENSE_COLLECTION"),
			stringOrDefault(values["TYPESENSE_COLLECTION"], "stores"),
		)),
	}, nil
}

func newFirestoreClient(ctx context.Context, cfg *serviceConfig) (*cloudfirestore.Client, error) {
	if cfg.ProjectID == "" {
		return nil, fmt.Errorf("FIRESTORE_PROJECT_ID not configured")
	}
	var opts []option.ClientOption
	if cfg.Credentials != "" {
		opts = append(opts, option.WithCredentialsFile(cfg.Credentials))
	}
	return cloudfirestore.NewClient(ctx, cfg.ProjectID, opts...)
}

type telegramUpdate struct {
	UpdateID    int64                `json:"update_id"`
	Message     *telegramMessage     `json:"message"`
	InlineQuery *telegramInlineQuery `json:"inline_query,omitempty"`
}

type telegramMessage struct {
	MessageID       int64         `json:"message_id"`
	From            *telegramUser `json:"from"`
	Chat            telegramChat  `json:"chat"`
	Date            int64         `json:"date"`
	Text            string        `json:"text"`
	MessageThreadID *int64        `json:"message_thread_id,omitempty"`
}

type telegramUser struct {
	ID        int64  `json:"id"`
	FirstName string `json:"first_name"`
	LastName  string `json:"last_name"`
	Username  string `json:"username"`
}

type telegramChat struct {
	ID   int64  `json:"id"`
	Type string `json:"type"`
}

func handleTelegramWebhook(
	w http.ResponseWriter,
	r *http.Request,
	cfg *serviceConfig,
	firestoreClient *cloudfirestore.Client,
	manager *sessionManager,
	orderHTTPClient *http.Client,
) {
	accountID := strings.TrimSpace(chi.URLParam(r, "accountId"))
	if accountID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_account_id"})
		return
	}

	if cfg.TelegramSecretToken != "" {
		got := strings.TrimSpace(r.Header.Get("X-Telegram-Bot-Api-Secret-Token"))
		if got != cfg.TelegramSecretToken {
			writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
			return
		}
	}

	var update telegramUpdate
	if err := json.NewDecoder(r.Body).Decode(&update); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
		return
	}
	if update.InlineQuery != nil {
		handleTelegramInlineQuery(w, r, cfg, firestoreClient, accountID, update.InlineQuery)
		return
	}
	if update.Message == nil || strings.TrimSpace(update.Message.Text) == "" {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ignored"})
		return
	}

	chatID := update.Message.Chat.ID
	userID := strconv.FormatInt(chatID, 10)
	threadID := ""
	if update.Message.MessageThreadID != nil {
		threadID = strconv.FormatInt(*update.Message.MessageThreadID, 10)
	}
	from := update.Message.From
	displayName := buildDisplayName(from)
	text := strings.TrimSpace(update.Message.Text)

	ctx, cancel := context.WithTimeout(r.Context(), 20*time.Second)
	defer cancel()

	if orderID := parseTelegramOrderStart(text); orderID != "" {
		contact := channelContact{
			Channel:     "telegram",
			AccountID:   accountID,
			UserID:      userID,
			ThreadID:    threadID,
			DisplayName: displayName,
		}
		err := updateOrderChannelContact(ctx, cfg, orderHTTPClient, orderID, contact)
		if cfg.TelegramBotToken != "" {
			switch {
			case err == nil:
				_ = sendTelegramMessage(ctx, cfg.TelegramBotToken, chatID, threadID,
					fmt.Sprintf("You're all set — we'll send updates for order %s here.", orderID))
			case errors.Is(err, errOrderContactUpdateConflict):
				_ = sendTelegramMessage(ctx, cfg.TelegramBotToken, chatID, threadID,
					"That order is already linked to another Telegram chat.")
			case errors.Is(err, errOrderContactUpdateNotFound):
				_ = sendTelegramMessage(ctx, cfg.TelegramBotToken, chatID, threadID,
					"Sorry — I couldn't find that order. Please check the code and try again.")
			default:
				_ = sendTelegramMessage(ctx, cfg.TelegramBotToken, chatID, threadID,
					"Sorry — I couldn't enable updates right now. Please try again later.")
			}
		}
		writeJSON(w, http.StatusOK, map[string]string{"status": "order_updates_handled"})
		return
	}

	route, err := agentcontext.ResolveRoute(ctx, firestoreClient, agentcontext.RouteLookup{
		Channel:          "telegram",
		ChannelAccountID: accountID,
	})
	if err != nil {
		log.Printf("telegram route lookup failed account=%s err=%v", accountID, err)
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "route_lookup_failed"})
		return
	}
	if route == nil {
		log.Printf("telegram route missing account=%s", accountID)
		writeJSON(w, http.StatusOK, map[string]string{"status": "no_route"})
		return
	}

	agentID := resolveAgentID(route.Data, cfg.DefaultAgentID)
	if agentID == "" {
		log.Printf("telegram route missing agent_id account=%s", accountID)
		writeJSON(w, http.StatusOK, map[string]string{"status": "no_agent"})
		return
	}

	existingSession, err := fetchSession(ctx, firestoreClient, "telegram", accountID, userID)
	if err != nil {
		log.Printf("telegram session read failed account=%s err=%v", accountID, err)
	}

	if isStoreSwitchCommand(text) {
		if err := upsertSession(ctx, firestoreClient, channelSession{
			Channel:             "telegram",
			AccountID:           accountID,
			UserID:              userID,
			ThreadID:            threadID,
			DisplayName:         displayName,
			TenantID:            "",
			StoreID:             "",
			BusinessType:        "",
			PendingStoreChoices: nil,
			LastSeenAt:          time.Now().UTC(),
			CreatedAt:           sessionCreatedAt(existingSession),
		}); err != nil {
			log.Printf("telegram session reset failed: %v", err)
		}
		if cfg.TelegramBotToken != "" {
			_ = sendTelegramMessage(ctx, cfg.TelegramBotToken, chatID, threadID, "Which restaurant would you like to order from? Please type the business name.")
		}
		writeJSON(w, http.StatusOK, map[string]string{"status": "store_reset"})
		return
	}

	if existingSession != nil && len(existingSession.PendingStoreChoices) > 0 {
		if picked := parseChoiceIndex(text); picked > 0 && picked <= len(existingSession.PendingStoreChoices) {
			choice := existingSession.PendingStoreChoices[picked-1]
			updated := *existingSession
			updated.TenantID = strings.TrimSpace(choice.TenantID)
			updated.StoreID = strings.TrimSpace(choice.StoreID)
			updated.BusinessType = strings.TrimSpace(choice.BusinessType)
			updated.PendingStoreChoices = nil
			updated.LastSeenAt = time.Now().UTC()
			if updated.CreatedAt.IsZero() {
				updated.CreatedAt = time.Now().UTC()
			}
			if err := upsertSession(ctx, firestoreClient, updated); err != nil {
				log.Printf("telegram session update failed: %v", err)
			}
			if cfg.TelegramBotToken != "" {
				_ = sendTelegramMessage(ctx, cfg.TelegramBotToken, chatID, threadID,
					fmt.Sprintf("Great — ordering from %s. What would you like?", choice.Name))
			}
			writeJSON(w, http.StatusOK, map[string]string{"status": "store_selected"})
			return
		}
	}

	selectedTenantID := strings.TrimSpace(anyToString(route.Data["tenant_id"]))
	if selectedTenantID == "" {
		selectedTenantID = strings.TrimSpace(anyToString(route.Data["tenantId"]))
	}
	selectedStoreID := strings.TrimSpace(anyToString(route.Data["store_id"]))
	if selectedStoreID == "" {
		selectedStoreID = strings.TrimSpace(anyToString(route.Data["storeId"]))
	}
	selectedBusinessType := strings.TrimSpace(anyToString(route.Data["business_type"]))
	if selectedBusinessType == "" {
		selectedBusinessType = strings.TrimSpace(anyToString(route.Data["businessType"]))
	}

	if existingSession != nil {
		if strings.TrimSpace(existingSession.TenantID) != "" {
			selectedTenantID = strings.TrimSpace(existingSession.TenantID)
		}
		if strings.TrimSpace(existingSession.StoreID) != "" {
			selectedStoreID = strings.TrimSpace(existingSession.StoreID)
		}
		if strings.TrimSpace(existingSession.BusinessType) != "" {
			selectedBusinessType = strings.TrimSpace(existingSession.BusinessType)
		}
	}

	if selectedStoreID == "" {
		query := strings.TrimSpace(text)
		if len(query) < 2 {
			if cfg.TelegramBotToken != "" {
				_ = sendTelegramMessage(ctx, cfg.TelegramBotToken, chatID, threadID, "Which restaurant would you like to order from? Please type the business name.")
			}
			writeJSON(w, http.StatusOK, map[string]string{"status": "store_prompt"})
			return
		}
		choices, err := searchStoreChoices(ctx, cfg, firestoreClient, query)
		if err != nil {
			log.Printf("store search failed account=%s err=%v", accountID, err)
		}
		if len(choices) == 0 {
			if cfg.TelegramBotToken != "" {
				_ = sendTelegramMessage(ctx, cfg.TelegramBotToken, chatID, threadID,
					fmt.Sprintf("I couldn't find a restaurant named \"%s\". Please try another name.", query))
			}
			writeJSON(w, http.StatusOK, map[string]string{"status": "no_match"})
			return
		}
		if len(choices) == 1 {
			choice := choices[0]
			if err := upsertSession(ctx, firestoreClient, channelSession{
				Channel:             "telegram",
				AccountID:           accountID,
				UserID:              userID,
				ThreadID:            threadID,
				DisplayName:         displayName,
				TenantID:            strings.TrimSpace(choice.TenantID),
				StoreID:             strings.TrimSpace(choice.StoreID),
				BusinessType:        strings.TrimSpace(choice.BusinessType),
				PendingStoreChoices: nil,
				LastSeenAt:          time.Now().UTC(),
				CreatedAt:           sessionCreatedAt(existingSession),
			}); err != nil {
				log.Printf("telegram session update failed: %v", err)
			}
			if cfg.TelegramBotToken != "" {
				_ = sendTelegramMessage(ctx, cfg.TelegramBotToken, chatID, threadID,
					fmt.Sprintf("Great — ordering from %s. What would you like?", choice.Name))
			}
			writeJSON(w, http.StatusOK, map[string]string{"status": "store_selected"})
			return
		}

		if err := upsertSession(ctx, firestoreClient, channelSession{
			Channel:             "telegram",
			AccountID:           accountID,
			UserID:              userID,
			ThreadID:            threadID,
			DisplayName:         displayName,
			TenantID:            "",
			StoreID:             "",
			BusinessType:        "",
			PendingStoreChoices: choices,
			LastSeenAt:          time.Now().UTC(),
			CreatedAt:           sessionCreatedAt(existingSession),
		}); err != nil {
			log.Printf("telegram session update failed: %v", err)
		}
		if cfg.TelegramBotToken != "" {
			_ = sendTelegramMessage(ctx, cfg.TelegramBotToken, chatID, threadID, formatStoreChoicesMessage(choices))
		}
		writeJSON(w, http.StatusOK, map[string]string{"status": "store_choices"})
		return
	}

	dyn := agentcontext.BuildDynamicVariables(
		ctx,
		agentcontext.RouteResolution{
			Source: route.Source,
			DocID:  route.DocID,
			Data:   mergeRouteData(route.Data, selectedTenantID, selectedStoreID, selectedBusinessType),
		},
		agentcontext.DynamicVarsInput{
			CallerID:             fmt.Sprintf("telegram:%s", userID),
			AgentID:              agentID,
			Channel:              "telegram",
			ChannelAccountID:     accountID,
			ChannelUserID:        userID,
			ChannelThreadID:      threadID,
			ChannelDisplayName:   displayName,
			FallbackCustomerName: displayName,
		},
		agentcontext.ServicesConfig{
			CustomerProfileServiceURL: stringOrDefaultEnv("CUSTOMER_PROFILE_SERVICE_URL"),
			RecommendationServiceURL:  stringOrDefaultEnv("RECOMMENDATION_SERVICE_URL"),
			WaitTimeServiceURL:        stringOrDefaultEnv("WAIT_TIME_SERVICE_URL"),
		},
		agentcontext.DynamicVarsOptions{IncludeChannelVars: true},
	)

	typingCtx, typingCancel := context.WithCancel(ctx)
	defer typingCancel()
	if cfg.TelegramBotToken != "" {
		go startTelegramTyping(typingCtx, cfg.TelegramBotToken, chatID, threadID)
	}

	responseText, conversationID, err := manager.SendMessage(ctx, agentID, dyn, text, cfg)
	if err != nil {
		log.Printf("telegram conversation error account=%s err=%v", accountID, err)
		writeJSON(w, http.StatusOK, map[string]string{"status": "error"})
		return
	}

	if err := upsertSession(ctx, firestoreClient, channelSession{
		Channel:                  "telegram",
		AccountID:                accountID,
		UserID:                   userID,
		ThreadID:                 threadID,
		DisplayName:              displayName,
		TenantID:                 strings.TrimSpace(anyToString(dyn["tenantId"])),
		StoreID:                  strings.TrimSpace(anyToString(dyn["storeId"])),
		BusinessType:             strings.TrimSpace(anyToString(dyn["businessType"])),
		ElevenLabsConversationID: conversationID,
		LastSeenAt:               time.Now().UTC(),
		CreatedAt:                sessionCreatedAt(existingSession),
	}); err != nil {
		log.Printf("telegram session upsert failed: %v", err)
	}

	if cfg.TelegramBotToken != "" && strings.TrimSpace(responseText) != "" {
		if err := sendTelegramMessage(ctx, cfg.TelegramBotToken, chatID, threadID, responseText); err != nil {
			log.Printf("telegram send failed chat=%d err=%v", chatID, err)
		}
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

type webAppSessionStartRequest struct {
	InitData string `json:"initData"`
	StoreID  string `json:"storeId"`
	Locale   string `json:"locale"`
}

type webAppSessionStartResponse struct {
	SessionID    string `json:"sessionId"`
	AccountID    string `json:"accountId"`
	UserID       string `json:"userId"`
	DisplayName  string `json:"displayName"`
	StoreID      string `json:"storeId,omitempty"`
	StoreName    string `json:"storeName,omitempty"`
	TenantID     string `json:"tenantId,omitempty"`
	CustomerID   string `json:"customerId,omitempty"`
	BusinessType string `json:"businessType,omitempty"`
	StartGroup   bool   `json:"startGroupOrder,omitempty"`
	BotUsername  string `json:"telegramBotUsername,omitempty"`
}

type webAppStoreSearchResponse struct {
	Results []storeChoice `json:"results"`
}

type webAppStoreSelectRequest struct {
	SessionID string `json:"sessionId"`
	StoreID   string `json:"storeId"`
}

type webAppOrderItem struct {
	ItemID             string                    `json:"itemId"`
	Quantity           int                       `json:"quantity"`
	ModifierSelections []webAppModifierSelection `json:"modifierSelections,omitempty"`
}

type webAppModifierSelection struct {
	GroupID    string `json:"groupId"`
	OptionID   string `json:"optionId"`
	Name       string `json:"name,omitempty"`
	PriceCents int64  `json:"priceCents,omitempty"`
}

type webAppOrderRequest struct {
	SessionID       string            `json:"sessionId"`
	StoreID         string            `json:"storeId,omitempty"`
	Items           []webAppOrderItem `json:"items"`
	Fuel            *webAppFuelOrder  `json:"fuel,omitempty"`
	Notes           string            `json:"notes,omitempty"`
	Locale          string            `json:"locale,omitempty"`
	FulfillmentType string            `json:"fulfillmentType,omitempty"`
	Delivery        *webAppDelivery   `json:"delivery,omitempty"`
	IdempotencyKey  string            `json:"idempotencyKey,omitempty"`
	PaymentMethod   string            `json:"paymentMethod,omitempty"`
	SuccessURL      string            `json:"successUrl,omitempty"`
	CancelURL       string            `json:"cancelUrl,omitempty"`
}

type orderServiceOrderRequest struct {
	StoreID         string                  `json:"storeId"`
	Channel         string                  `json:"channel"`
	CustomerName    string                  `json:"customerName,omitempty"`
	TenantID        string                  `json:"tenantId,omitempty"`
	CustomerID      string                  `json:"customerId,omitempty"`
	CallerID        string                  `json:"callerId,omitempty"`
	ChannelContact  *channelContact         `json:"channelContact,omitempty"`
	Origin          *orderOrigin            `json:"origin,omitempty"`
	Notes           string                  `json:"notes,omitempty"`
	BusinessType    string                  `json:"businessType,omitempty"`
	PaymentMethod   string                  `json:"paymentMethod,omitempty"`
	Items           []orderServiceOrderItem `json:"items"`
	Fuel            *orderServiceFuelOrder  `json:"fuel,omitempty"`
	IdempotencyKey  string                  `json:"idempotencyKey,omitempty"`
	FulfillmentType string                  `json:"fulfillmentType,omitempty"`
	Delivery        *orderServiceDelivery   `json:"delivery,omitempty"`
}

type channelContact struct {
	Channel     string         `json:"channel"`
	AccountID   string         `json:"accountId,omitempty"`
	UserID      string         `json:"userId,omitempty"`
	ThreadID    string         `json:"threadId,omitempty"`
	DisplayName string         `json:"displayName,omitempty"`
	Locale      string         `json:"locale,omitempty"`
	Metadata    map[string]any `json:"metadata,omitempty"`
}

type orderServiceOrderItem struct {
	ItemID             string                    `json:"itemId"`
	Quantity           int                       `json:"quantity"`
	ModifierSelections []webAppModifierSelection `json:"modifierSelections,omitempty"`
}

type telegramInitContext struct {
	UserID      string
	DisplayName string
	ReceiverID  string
	StartParam  string
	Locale      string
}

func handleWebAppSessionStart(w http.ResponseWriter, r *http.Request, cfg *serviceConfig, firestoreClient *cloudfirestore.Client) {
	var payload webAppSessionStartRequest
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
		return
	}
	payload.InitData = strings.TrimSpace(payload.InitData)
	payload.StoreID = strings.TrimSpace(payload.StoreID)
	payload.Locale = strings.TrimSpace(payload.Locale)

	initCtx, err := parseTelegramInitData(payload.InitData, cfg)
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid_init_data"})
		return
	}
	if initCtx.UserID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_user"})
		return
	}

	accountID := strings.TrimSpace(initCtx.ReceiverID)
	if accountID == "" {
		accountID = "telegram_webapp"
	}

	startStoreID, startGroup := parseTelegramStartParam(initCtx.StartParam)
	storeID := payload.StoreID
	if storeID == "" {
		storeID = startStoreID
	}

	ctx, cancel := context.WithTimeout(r.Context(), 8*time.Second)
	defer cancel()

	storeMeta := storeMetadata{}
	if storeID != "" {
		meta, err := fetchStoreMetadata(ctx, firestoreClient, storeID)
		if err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "store_lookup_failed"})
			return
		}
		storeMeta = meta
		if storeMeta.StoreID != "" {
			storeID = storeMeta.StoreID
		}
	}

	session := channelSession{
		Channel:                  "telegram_webapp",
		AccountID:                accountID,
		UserID:                   initCtx.UserID,
		DisplayName:              initCtx.DisplayName,
		TenantID:                 storeMeta.TenantID,
		StoreID:                  storeID,
		BusinessType:             storeMeta.BusinessType,
		AuthProvider:             webAppAuthProvider("telegram_webapp"),
		ClientPlatform:           "web",
		ClientApp:                "consumer-web",
		ElevenLabsConversationID: "",
		LastSeenAt:               time.Now().UTC(),
		CreatedAt:                time.Now().UTC(),
	}
	if customerID, err := resolveCustomerID(ctx, cfg, session.Channel, session.UserID, session.DisplayName, session.TenantID, customerResolveContext{
		StoreID:  storeID,
		Platform: "web",
	}); err != nil {
		log.Printf("customer-profile resolve failed: %v", err)
	} else {
		session.CustomerID = customerID
	}

	if err := upsertSession(ctx, firestoreClient, session); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "session_write_failed"})
		return
	}

	botUsername := strings.TrimSpace(resolveTelegramBotUsername(ctx, cfg))
	writeJSON(w, http.StatusOK, webAppSessionStartResponse{
		SessionID:    sessionDocID(session.Channel, session.AccountID, session.UserID),
		AccountID:    session.AccountID,
		UserID:       session.UserID,
		DisplayName:  session.DisplayName,
		StoreID:      session.StoreID,
		StoreName:    storeMeta.StoreName,
		TenantID:     session.TenantID,
		CustomerID:   session.CustomerID,
		BusinessType: session.BusinessType,
		StartGroup:   startGroup && session.StoreID != "",
		BotUsername:  botUsername,
	})
}

func handleWebAppStoreSearch(w http.ResponseWriter, r *http.Request, cfg *serviceConfig, firestoreClient *cloudfirestore.Client) {
	query := strings.TrimSpace(r.URL.Query().Get("q"))
	if query == "" {
		writeJSON(w, http.StatusOK, webAppStoreSearchResponse{Results: []storeChoice{}})
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 6*time.Second)
	defer cancel()
	choices, err := searchStoreChoices(ctx, cfg, firestoreClient, query)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "search_failed"})
		return
	}
	writeJSON(w, http.StatusOK, webAppStoreSearchResponse{Results: choices})
}

func handleWebAppStoreSelect(
	w http.ResponseWriter,
	r *http.Request,
	cfg *serviceConfig,
	firestoreClient *cloudfirestore.Client,
) {
	var payload webAppStoreSelectRequest
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
		return
	}
	payload.SessionID = strings.TrimSpace(payload.SessionID)
	payload.StoreID = strings.TrimSpace(payload.StoreID)
	if payload.SessionID == "" || payload.StoreID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_session_or_store"})
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 8*time.Second)
	defer cancel()

	meta, err := fetchStoreMetadata(ctx, firestoreClient, payload.StoreID)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "store_lookup_failed"})
		return
	}

	session, err := loadSessionByID(ctx, firestoreClient, payload.SessionID)
	if err != nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "session_not_found"})
		return
	}
	customerID := strings.TrimSpace(session.CustomerID)
	if customerID == "" {
		platform := strings.TrimSpace(session.ClientPlatform)
		if platform == "" {
			platform = "web"
		}
		if resolved, err := resolveCustomerID(ctx, cfg, session.Channel, session.UserID, session.DisplayName, meta.TenantID, customerResolveContext{
			StoreID:  meta.StoreID,
			Platform: platform,
			Provider: strings.TrimSpace(session.AuthProvider),
		}); err == nil {
			customerID = resolved
		}
	}

	updates := map[string]any{
		"store_id":     payload.StoreID,
		"last_seen_at": time.Now().UTC(),
	}
	if meta.TenantID != "" {
		updates["tenant_id"] = meta.TenantID
	}
	if meta.BusinessType != "" {
		updates["business_type"] = meta.BusinessType
	}
	if customerID != "" {
		updates["customer_id"] = customerID
	}
	_, err = firestoreClient.Collection(channelSessionsCollection).Doc(payload.SessionID).Set(ctx, updates, cloudfirestore.MergeAll)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "session_update_failed"})
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func handleWebAppMenu(w http.ResponseWriter, r *http.Request, cfg *serviceConfig, orderHTTPClient *http.Client) {
	storeID := strings.TrimSpace(chi.URLParam(r, "storeID"))
	if storeID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_store_id"})
		return
	}
	if strings.TrimSpace(cfg.OrderServiceURL) == "" {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "order_service_not_configured"})
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 12*time.Second)
	defer cancel()
	endpoint := fmt.Sprintf("%s/stores/%s/menu/snapshot", strings.TrimRight(cfg.OrderServiceURL, "/"), url.PathEscape(storeID))
	req, _ := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	resp, err := orderHTTPClient.Do(req)
	if err != nil {
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "order_service_unavailable"})
		return
	}
	defer resp.Body.Close()
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(resp.StatusCode)
	_, _ = io.Copy(w, resp.Body)
}

func handleWebAppOrderCreate(
	w http.ResponseWriter,
	r *http.Request,
	cfg *serviceConfig,
	firestoreClient *cloudfirestore.Client,
	orderHTTPClient *http.Client,
	paymentsHTTPClient *http.Client,
) {
	var payload webAppOrderRequest
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
		return
	}
	payload.SessionID = strings.TrimSpace(payload.SessionID)
	payload.StoreID = strings.TrimSpace(payload.StoreID)
	payload.Locale = strings.TrimSpace(payload.Locale)
	payload.PaymentMethod = strings.ToLower(strings.TrimSpace(payload.PaymentMethod))
	payload.SuccessURL = strings.TrimSpace(payload.SuccessURL)
	payload.CancelURL = strings.TrimSpace(payload.CancelURL)
	if payload.SessionID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_session"})
		return
	}
	if len(payload.Items) == 0 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_items"})
		return
	}
	if payload.PaymentMethod == "" {
		payload.PaymentMethod = "cash"
	}
	if strings.TrimSpace(cfg.OrderServiceURL) == "" {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "order_service_not_configured"})
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 18*time.Second)
	defer cancel()

	session, err := loadSessionWithCustomer(ctx, cfg, firestoreClient, payload.SessionID)
	if err != nil {
		if status.Code(err) == codes.NotFound {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "session_not_found"})
			return
		}
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "session_read_failed"})
		return
	}
	isMobile := strings.EqualFold(session.Channel, "mobile")

	storeID := strings.TrimSpace(payload.StoreID)
	if storeID == "" {
		storeID = strings.TrimSpace(session.StoreID)
	}
	if storeID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_store"})
		return
	}

	orderItems := make([]orderServiceOrderItem, 0, len(payload.Items))
	for _, item := range payload.Items {
		orderItems = append(orderItems, orderServiceOrderItem{
			ItemID:             strings.TrimSpace(item.ItemID),
			Quantity:           item.Quantity,
			ModifierSelections: item.ModifierSelections,
		})
	}
	var fuelPayload *orderServiceFuelOrder
	if payload.Fuel != nil {
		fuelPayload = &orderServiceFuelOrder{
			FuelGradeID:          strings.TrimSpace(payload.Fuel.FuelGradeID),
			FuelGradeName:        strings.TrimSpace(payload.Fuel.FuelGradeName),
			Unit:                 strings.TrimSpace(payload.Fuel.Unit),
			UnitPriceCents:       payload.Fuel.UnitPriceCents,
			RequestedLiters:      payload.Fuel.RequestedLiters,
			RequestedAmountCents: payload.Fuel.RequestedAmountCents,
			PreauthAmountCents:   payload.Fuel.PreauthAmountCents,
			PaymentFlow:          strings.TrimSpace(payload.Fuel.PaymentFlow),
			PumpNumber:           strings.TrimSpace(payload.Fuel.PumpNumber),
		}
	}
	deliveryPayload := buildOrderServiceDelivery(payload.Delivery)

	orderChannel := webAppOrderChannel(session)
	customerName := strings.TrimSpace(session.DisplayName)
	if customerName == "" {
		customerName = webAppDefaultCustomerName(orderChannel)
	}

	orderPayload := orderServiceOrderRequest{
		StoreID:      storeID,
		Channel:      orderChannel,
		CustomerName: customerName,
		TenantID:     strings.TrimSpace(session.TenantID),
		CustomerID:   strings.TrimSpace(session.CustomerID),
		CallerID:     webAppCallerID(orderChannel, session.UserID),
		ChannelContact: &channelContact{
			Channel:     webAppContactChannel(orderChannel),
			AccountID:   session.AccountID,
			UserID:      session.UserID,
			DisplayName: session.DisplayName,
			Locale:      strings.TrimSpace(payload.Locale),
		},
		Origin:          buildWebAppOrderOrigin(session, payload.SessionID),
		Notes:           strings.TrimSpace(payload.Notes),
		BusinessType:    strings.TrimSpace(session.BusinessType),
		PaymentMethod:   payload.PaymentMethod,
		Items:           orderItems,
		Fuel:            fuelPayload,
		Delivery:        deliveryPayload,
		IdempotencyKey:  strings.TrimSpace(payload.IdempotencyKey),
		FulfillmentType: strings.TrimSpace(payload.FulfillmentType),
	}

	if orderPayload.FulfillmentType == "" {
		orderPayload.FulfillmentType = "pickup"
	}

	body, _ := json.Marshal(orderPayload)
	endpoint := fmt.Sprintf("%s/orders", strings.TrimRight(cfg.OrderServiceURL, "/"))
	req, _ := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err := orderHTTPClient.Do(req)
	if err != nil {
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "order_service_unavailable"})
		return
	}
	defer resp.Body.Close()
	respBody, _ := io.ReadAll(resp.Body)
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		log.Printf("webapp order create failed status=%d body=%s", resp.StatusCode, truncateForLog(respBody, 1200))
		writeJSON(w, resp.StatusCode, map[string]any{
			"error":   "order_create_failed",
			"details": string(respBody),
		})
		return
	}
	var orderResponse map[string]any
	if err := json.Unmarshal(respBody, &orderResponse); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "order_parse_failed"})
		return
	}
	if payload.PaymentMethod == "card" && !isMobile {
		if payload.SuccessURL == "" || payload.CancelURL == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_redirect_urls"})
			return
		}
		if strings.TrimSpace(cfg.PaymentsServiceURL) == "" {
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "payments_service_not_configured"})
			return
		}
		paymentFlow := ""
		if fuelPayload != nil {
			paymentFlow = strings.ToLower(strings.TrimSpace(fuelPayload.PaymentFlow))
		}
		orderID := strings.TrimSpace(anyToString(orderResponse["id"]))
		var checkout orderCheckoutResponse
		var err error
		currency := "usd"
		if fuelPayload != nil {
			currency = "eur"
		}
		if paymentFlow == "preauth" {
			checkout, err = createOrderPreauthCheckout(
				ctx,
				cfg,
				paymentsHTTPClient,
				orderID,
				payload.SuccessURL,
				payload.CancelURL,
				currency,
				fuelPayload.PreauthAmountCents,
			)
		} else {
			checkout, err = createOrderCheckout(
				ctx,
				cfg,
				paymentsHTTPClient,
				orderID,
				payload.SuccessURL,
				payload.CancelURL,
				currency,
			)
		}
		if err != nil {
			writeJSON(w, http.StatusBadGateway, map[string]string{"error": "payments_service_unavailable"})
			return
		}
		orderResponse["checkoutUrl"] = checkout.CheckoutURL
		orderResponse["paymentId"] = checkout.PaymentID
		orderResponse["sessionId"] = checkout.SessionID
	}
	writeJSON(w, resp.StatusCode, orderResponse)
}

type storeMetadata struct {
	StoreID                string
	StoreName              string
	TenantID               string
	BusinessType           string
	LogoURL                string
	Currency               string
	FuelDefaultPrepayCents int64
	DeliveryEnabled        bool
	DeliveryFleetMode      string
}

func fetchStoreMetadata(ctx context.Context, client *cloudfirestore.Client, storeID string) (storeMetadata, error) {
	if storeID == "" {
		return storeMetadata{}, nil
	}
	doc, err := client.Collection(storesCollection).Doc(storeID).Get(ctx)
	if err != nil {
		if status.Code(err) != codes.NotFound {
			return storeMetadata{}, err
		}
		iter := client.Collection(storesCollection).Where("store_id", "==", storeID).Limit(1).Documents(ctx)
		alt, err := iter.Next()
		if err != nil {
			if err == iterator.Done {
				return storeMetadata{StoreID: storeID}, nil
			}
			return storeMetadata{}, err
		}
		doc = alt
	}
	data := doc.Data()
	tenantID := strings.TrimSpace(firstNonEmpty(anyToString(data["tenant_id"]), anyToString(data["tenantId"])))
	businessType := strings.TrimSpace(firstNonEmpty(anyToString(data["business_type"]), anyToString(data["businessType"])))
	name := strings.TrimSpace(firstNonEmpty(anyToString(data["name"]), anyToString(data["store_name"]), anyToString(data["display_name"])))
	if name == "" {
		name = strings.TrimSpace(firstNonEmpty(anyToString(data["store_id"]), doc.Ref.ID))
	}
	logoURL := strings.TrimSpace(firstNonEmpty(
		anyToString(data["logo_url"]),
		anyToString(data["logoUrl"]),
		anyToString(data["logo"]),
		anyToString(data["image_url"]),
		anyToString(data["imageUrl"]),
	))
	currency := strings.TrimSpace(firstNonEmpty(
		anyToString(data["currency"]),
		anyToString(data["currency_type"]),
		anyToString(data["currencyType"]),
	))
	fuelDefaultPrepay := int64(intOrDefault(
		firstNonEmptyIntCandidate(
			data["fuel_default_prepay_cents"],
			data["fuel_prepay_default_cents"],
			data["fuelDefaultPrepayCents"],
		),
		0,
	))
	deliverySettings, _ := data["delivery_settings"].(map[string]any)
	if deliverySettings == nil {
		if alt, ok := data["deliverySettings"].(map[string]any); ok {
			deliverySettings = alt
		}
	}
	deliveryEnabled := false
	deliveryFleetMode := ""
	if deliverySettings != nil {
		if enabled, ok := deliverySettings["enabled"].(bool); ok {
			deliveryEnabled = enabled
		} else if enabledStr := strings.TrimSpace(anyToString(deliverySettings["enabled"])); enabledStr != "" {
			deliveryEnabled = strings.ToLower(enabledStr) == "true"
		}
		deliveryFleetMode = strings.TrimSpace(anyToString(deliverySettings["fleet_mode"]))
	}
	return storeMetadata{
		StoreID:                strings.TrimSpace(firstNonEmpty(anyToString(data["store_id"]), doc.Ref.ID)),
		StoreName:              name,
		TenantID:               tenantID,
		BusinessType:           businessType,
		LogoURL:                logoURL,
		Currency:               strings.ToLower(currency),
		FuelDefaultPrepayCents: fuelDefaultPrepay,
		DeliveryEnabled:        deliveryEnabled,
		DeliveryFleetMode:      deliveryFleetMode,
	}, nil
}

func parseTelegramInitData(initData string, cfg *serviceConfig) (telegramInitContext, error) {
	initData = strings.TrimSpace(initData)
	if initData == "" {
		if cfg != nil && strings.ToLower(cfg.Environment) != "production" {
			return telegramInitContext{
				UserID:      "dev-user",
				DisplayName: "Dev User",
				ReceiverID:  "telegram_webapp",
			}, nil
		}
		return telegramInitContext{}, errors.New("missing init data")
	}

	values, err := url.ParseQuery(initData)
	if err != nil {
		return telegramInitContext{}, err
	}

	if cfg != nil && strings.TrimSpace(cfg.TelegramBotToken) != "" {
		if err := verifyTelegramInitData(values, cfg.TelegramBotToken); err != nil {
			return telegramInitContext{}, err
		}
	}

	var user telegramUser
	if raw := strings.TrimSpace(values.Get("user")); raw != "" {
		if err := json.Unmarshal([]byte(raw), &user); err != nil {
			return telegramInitContext{}, err
		}
	}
	var receiver telegramUser
	if raw := strings.TrimSpace(values.Get("receiver")); raw != "" {
		_ = json.Unmarshal([]byte(raw), &receiver)
	}

	displayName := buildDisplayName(&user)
	userID := ""
	if user.ID != 0 {
		userID = strconv.FormatInt(user.ID, 10)
	}
	receiverID := ""
	if receiver.ID != 0 {
		receiverID = strconv.FormatInt(receiver.ID, 10)
	}

	return telegramInitContext{
		UserID:      userID,
		DisplayName: displayName,
		ReceiverID:  receiverID,
		StartParam:  strings.TrimSpace(values.Get("start_param")),
		Locale:      strings.TrimSpace(values.Get("lang")),
	}, nil
}

func verifyTelegramInitData(values url.Values, botToken string) error {
	if botToken == "" {
		return nil
	}
	hash := values.Get("hash")
	if hash == "" {
		return errors.New("missing hash")
	}

	pairs := make([]string, 0, len(values))
	for key := range values {
		if key == "hash" {
			continue
		}
		val := values.Get(key)
		pairs = append(pairs, fmt.Sprintf("%s=%s", key, val))
	}
	sort.Strings(pairs)
	dataCheckString := strings.Join(pairs, "\n")

	secretMac := hmac.New(sha256.New, []byte("WebAppData"))
	_, _ = secretMac.Write([]byte(botToken))
	secret := secretMac.Sum(nil)
	h := hmac.New(sha256.New, secret)
	_, _ = h.Write([]byte(dataCheckString))
	expected := hex.EncodeToString(h.Sum(nil))

	if !hmac.Equal([]byte(expected), []byte(hash)) {
		return errors.New("invalid hash")
	}
	return nil
}

type lensSessionStartRequest struct {
	AccountID   string `json:"accountId"`
	UserID      string `json:"userId"`
	StoreID     string `json:"storeId"`
	DisplayName string `json:"displayName"`
	Locale      string `json:"locale"`
}

type lensSessionResponse struct {
	SessionID    string `json:"sessionId"`
	AccountID    string `json:"accountId"`
	UserID       string `json:"userId"`
	StoreID      string `json:"storeId"`
	TenantID     string `json:"tenantId"`
	BusinessType string `json:"businessType"`
	AgentID      string `json:"agentId"`
}

func handleLensSessionStart(w http.ResponseWriter, r *http.Request, cfg *serviceConfig, firestoreClient *cloudfirestore.Client) {
	var payload lensSessionStartRequest
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
		return
	}
	payload.AccountID = strings.TrimSpace(payload.AccountID)
	payload.UserID = strings.TrimSpace(payload.UserID)
	if payload.AccountID == "" || payload.UserID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_account_or_user"})
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	route, err := agentcontext.ResolveRoute(ctx, firestoreClient, agentcontext.RouteLookup{
		Channel:          "snap_lens",
		ChannelAccountID: payload.AccountID,
	})
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "route_lookup_failed"})
		return
	}
	if route == nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "route_not_found"})
		return
	}

	agentID := resolveAgentID(route.Data, cfg.DefaultAgentID)
	if agentID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_agent"})
		return
	}

	dyn := agentcontext.BuildDynamicVariables(
		ctx,
		*route,
		agentcontext.DynamicVarsInput{
			CallerID:             fmt.Sprintf("snap_lens:%s", payload.UserID),
			AgentID:              agentID,
			Channel:              "snap_lens",
			ChannelAccountID:     payload.AccountID,
			ChannelUserID:        payload.UserID,
			ChannelDisplayName:   payload.DisplayName,
			FallbackCustomerName: payload.DisplayName,
		},
		agentcontext.ServicesConfig{
			CustomerProfileServiceURL: stringOrDefaultEnv("CUSTOMER_PROFILE_SERVICE_URL"),
			RecommendationServiceURL:  stringOrDefaultEnv("RECOMMENDATION_SERVICE_URL"),
			WaitTimeServiceURL:        stringOrDefaultEnv("WAIT_TIME_SERVICE_URL"),
		},
		agentcontext.DynamicVarsOptions{IncludeChannelVars: true},
	)

	storeID := strings.TrimSpace(payload.StoreID)
	if storeID == "" {
		storeID = strings.TrimSpace(anyToString(dyn["storeId"]))
	}

	session := channelSession{
		Channel:                  "snap_lens",
		AccountID:                payload.AccountID,
		UserID:                   payload.UserID,
		DisplayName:              payload.DisplayName,
		TenantID:                 strings.TrimSpace(anyToString(dyn["tenantId"])),
		StoreID:                  storeID,
		BusinessType:             strings.TrimSpace(anyToString(dyn["businessType"])),
		ElevenLabsConversationID: "",
		LastSeenAt:               time.Now().UTC(),
		CreatedAt:                time.Now().UTC(),
	}

	if err := upsertSession(ctx, firestoreClient, session); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "session_write_failed"})
		return
	}

	writeJSON(w, http.StatusOK, lensSessionResponse{
		SessionID:    sessionDocID("snap_lens", payload.AccountID, payload.UserID),
		AccountID:    payload.AccountID,
		UserID:       payload.UserID,
		StoreID:      session.StoreID,
		TenantID:     session.TenantID,
		BusinessType: session.BusinessType,
		AgentID:      agentID,
	})
}

type lensStoreSelectRequest struct {
	SessionID string `json:"sessionId"`
	StoreID   string `json:"storeId"`
}

func handleLensStoreSelect(w http.ResponseWriter, r *http.Request, firestoreClient *cloudfirestore.Client) {
	var payload lensStoreSelectRequest
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
		return
	}
	payload.SessionID = strings.TrimSpace(payload.SessionID)
	payload.StoreID = strings.TrimSpace(payload.StoreID)
	if payload.SessionID == "" || payload.StoreID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_session_or_store"})
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 6*time.Second)
	defer cancel()

	_, err := firestoreClient.Collection(channelSessionsCollection).Doc(payload.SessionID).Set(ctx, map[string]any{
		"store_id":     payload.StoreID,
		"last_seen_at": time.Now().UTC(),
	}, cloudfirestore.MergeAll)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "session_update_failed"})
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

type lensCartUpdateRequest struct {
	SessionID string         `json:"sessionId"`
	Cart      map[string]any `json:"cart"`
}

func handleLensCartUpdate(w http.ResponseWriter, r *http.Request, firestoreClient *cloudfirestore.Client) {
	var payload lensCartUpdateRequest
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
		return
	}
	payload.SessionID = strings.TrimSpace(payload.SessionID)
	if payload.SessionID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_session"})
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 6*time.Second)
	defer cancel()

	_, err := firestoreClient.Collection(channelSessionsCollection).Doc(payload.SessionID).Set(ctx, map[string]any{
		"last_cart":    payload.Cart,
		"last_seen_at": time.Now().UTC(),
	}, cloudfirestore.MergeAll)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "cart_update_failed"})
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

type lensVoiceTurnRequest struct {
	SessionID string `json:"sessionId"`
	Text      string `json:"text"`
}

type lensVoiceTurnResponse struct {
	Text           string `json:"text"`
	ConversationID string `json:"conversationId,omitempty"`
}

func handleLensVoiceTurn(
	w http.ResponseWriter,
	r *http.Request,
	cfg *serviceConfig,
	firestoreClient *cloudfirestore.Client,
	manager *sessionManager,
) {
	var payload lensVoiceTurnRequest
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
		return
	}
	payload.SessionID = strings.TrimSpace(payload.SessionID)
	payload.Text = strings.TrimSpace(payload.Text)
	if payload.SessionID == "" || payload.Text == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_session_or_text"})
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 20*time.Second)
	defer cancel()

	snap, err := firestoreClient.Collection(channelSessionsCollection).Doc(payload.SessionID).Get(ctx)
	if err != nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "session_not_found"})
		return
	}
	var session channelSession
	if err := snap.DataTo(&session); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "session_read_failed"})
		return
	}

	route, err := agentcontext.ResolveRoute(ctx, firestoreClient, agentcontext.RouteLookup{
		Channel:          "snap_lens",
		ChannelAccountID: session.AccountID,
	})
	if err != nil || route == nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "route_not_found"})
		return
	}

	agentID := resolveAgentID(route.Data, cfg.DefaultAgentID)
	if agentID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_agent"})
		return
	}

	dyn := agentcontext.BuildDynamicVariables(
		ctx,
		*route,
		agentcontext.DynamicVarsInput{
			CallerID:             fmt.Sprintf("snap_lens:%s", session.UserID),
			AgentID:              agentID,
			Channel:              session.Channel,
			ChannelAccountID:     session.AccountID,
			ChannelUserID:        session.UserID,
			ChannelDisplayName:   session.DisplayName,
			FallbackCustomerName: session.DisplayName,
		},
		agentcontext.ServicesConfig{
			CustomerProfileServiceURL: stringOrDefaultEnv("CUSTOMER_PROFILE_SERVICE_URL"),
			RecommendationServiceURL:  stringOrDefaultEnv("RECOMMENDATION_SERVICE_URL"),
			WaitTimeServiceURL:        stringOrDefaultEnv("WAIT_TIME_SERVICE_URL"),
		},
		agentcontext.DynamicVarsOptions{IncludeChannelVars: true},
	)

	responseText, conversationID, err := manager.SendMessage(ctx, agentID, dyn, payload.Text, cfg)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "agent_error"})
		return
	}

	if err := upsertSession(ctx, firestoreClient, channelSession{
		Channel:                  session.Channel,
		AccountID:                session.AccountID,
		UserID:                   session.UserID,
		ThreadID:                 session.ThreadID,
		DisplayName:              session.DisplayName,
		TenantID:                 session.TenantID,
		StoreID:                  session.StoreID,
		BusinessType:             session.BusinessType,
		ElevenLabsConversationID: conversationID,
		LastSeenAt:               time.Now().UTC(),
		CreatedAt:                session.CreatedAt,
	}); err != nil {
		log.Printf("lens session update failed: %v", err)
	}

	writeJSON(w, http.StatusOK, lensVoiceTurnResponse{Text: responseText, ConversationID: conversationID})
}

func (m *sessionManager) SendMessage(ctx context.Context, agentID string, dyn map[string]any, text string, cfg *serviceConfig) (string, string, error) {
	key := fmt.Sprintf("%s:%s", agentID, sessionKeyFromDyn(dyn))
	sess, err := m.getOrCreateSession(ctx, key, agentID, dyn, cfg)
	if err != nil {
		return "", "", err
	}

	sess.mu.Lock()
	defer sess.mu.Unlock()

	if err := sess.conn.WriteJSON(map[string]any{
		"type": "user_message",
		"text": text,
	}); err != nil {
		m.dropSession(key)
		return "", sess.conversationID, err
	}

	reply, conversationID, err := readAgentReply(ctx, sess.conn, false)
	if conversationID != "" {
		sess.conversationID = conversationID
	}
	sess.lastUsed = time.Now().UTC()
	return reply.Text, sess.conversationID, err
}

func (m *sessionManager) SendMessageWithTools(ctx context.Context, agentID string, dyn map[string]any, text string, cfg *serviceConfig) (agentReply, string, error) {
	key := fmt.Sprintf("%s:%s", agentID, sessionKeyFromDyn(dyn))
	sess, err := m.getOrCreateSession(ctx, key, agentID, dyn, cfg)
	if err != nil {
		return agentReply{}, "", err
	}

	sess.mu.Lock()
	defer sess.mu.Unlock()

	if err := sess.conn.WriteJSON(map[string]any{
		"type": "user_message",
		"text": text,
	}); err != nil {
		m.dropSession(key)
		return agentReply{}, sess.conversationID, err
	}

	reply, conversationID, err := readAgentReply(ctx, sess.conn, true)
	if conversationID != "" {
		sess.conversationID = conversationID
	}
	sess.lastUsed = time.Now().UTC()
	return reply, sess.conversationID, err
}

func (m *sessionManager) SendToolResult(ctx context.Context, agentID string, dyn map[string]any, result webappChatToolResult, cfg *serviceConfig) (agentReply, string, error) {
	key := fmt.Sprintf("%s:%s", agentID, sessionKeyFromDyn(dyn))
	sess, err := m.getOrCreateSession(ctx, key, agentID, dyn, cfg)
	if err != nil {
		return agentReply{}, "", err
	}

	sess.mu.Lock()
	defer sess.mu.Unlock()

	payload := map[string]any{
		"type":         "client_tool_result",
		"tool_call_id": result.ToolCallID,
		"result":       result.Result,
		"is_error":     result.IsError,
	}
	if err := sess.conn.WriteJSON(payload); err != nil {
		m.dropSession(key)
		return agentReply{}, sess.conversationID, err
	}

	reply, conversationID, err := readAgentReply(ctx, sess.conn, true)
	if conversationID != "" {
		sess.conversationID = conversationID
	}
	sess.lastUsed = time.Now().UTC()
	return reply, sess.conversationID, err
}

func (m *sessionManager) PrewarmSession(ctx context.Context, agentID string, dyn map[string]any, cfg *serviceConfig) (string, error) {
	key := fmt.Sprintf("%s:%s", agentID, sessionKeyFromDyn(dyn))
	sess, err := m.getOrCreateSession(ctx, key, agentID, dyn, cfg)
	if err != nil {
		return "", err
	}
	sess.mu.Lock()
	defer sess.mu.Unlock()
	sess.lastUsed = time.Now().UTC()
	return sess.conversationID, nil
}

func (m *sessionManager) ReadNextResponse(ctx context.Context, agentID string, dyn map[string]any) (string, string, error) {
	key := fmt.Sprintf("%s:%s", agentID, sessionKeyFromDyn(dyn))
	m.mu.Lock()
	sess := m.sessions[key]
	m.mu.Unlock()
	if sess == nil {
		return "", "", errors.New("session_not_found")
	}
	sess.mu.Lock()
	defer sess.mu.Unlock()
	response, conversationID, err := readAgentResponse(ctx, sess.conn)
	if conversationID != "" {
		sess.conversationID = conversationID
	}
	sess.lastUsed = time.Now().UTC()
	return response, sess.conversationID, err
}

func (m *sessionManager) getOrCreateSession(ctx context.Context, key, agentID string, dyn map[string]any, cfg *serviceConfig) (*wsSession, error) {
	m.mu.Lock()
	if sess, ok := m.sessions[key]; ok {
		if sess.agentID == agentID && time.Since(sess.lastUsed) <= m.idleWindow {
			m.mu.Unlock()
			return sess, nil
		}
		sess.conn.Close()
		delete(m.sessions, key)
	}
	m.mu.Unlock()

	conn, conversationID, err := openElevenLabsConnection(ctx, cfg, agentID, dyn)
	if err != nil {
		return nil, err
	}

	sess := &wsSession{
		conn:           conn,
		agentID:        agentID,
		conversationID: conversationID,
		lastUsed:       time.Now().UTC(),
	}

	m.mu.Lock()
	m.sessions[key] = sess
	m.mu.Unlock()

	return sess, nil
}

func (m *sessionManager) dropSession(key string) {
	m.mu.Lock()
	if sess, ok := m.sessions[key]; ok {
		sess.conn.Close()
		delete(m.sessions, key)
	}
	m.mu.Unlock()
}

func (m *sessionManager) startCleanupLoop() {
	if m.idleWindow == 0 {
		m.idleWindow = 20 * time.Minute
	}
	go func() {
		ticker := time.NewTicker(2 * time.Minute)
		defer ticker.Stop()
		for range ticker.C {
			m.cleanupIdle()
		}
	}()
}

func (m *sessionManager) cleanupIdle() {
	m.mu.Lock()
	defer m.mu.Unlock()
	for key, sess := range m.sessions {
		if time.Since(sess.lastUsed) > m.idleWindow {
			sess.conn.Close()
			delete(m.sessions, key)
		}
	}
}

func openElevenLabsConnection(ctx context.Context, cfg *serviceConfig, agentID string, dyn map[string]any) (*websocket.Conn, string, error) {
	if cfg.ElevenLabsAPIKey == "" {
		return nil, "", errors.New("missing ElevenLabs API key")
	}
	base := strings.TrimRight(cfg.ElevenLabsAPIBase, "/")
	if base == "" {
		base = "https://api.elevenlabs.io"
	}

	signedURL, conversationID, err := fetchSignedURL(ctx, base, cfg.ElevenLabsAPIKey, agentID)
	if err != nil {
		return nil, "", err
	}

	dialer := websocket.DefaultDialer
	conn, _, err := dialer.DialContext(ctx, signedURL, nil)
	if err != nil {
		return nil, "", err
	}

	initPayload := map[string]any{
		"type":              "conversation_initiation_client_data",
		"dynamic_variables": normalizeDynamicVariables(dyn),
	}
	if err := conn.WriteJSON(initPayload); err != nil {
		conn.Close()
		return nil, "", err
	}

	return conn, conversationID, nil
}

func normalizeDynamicVariables(input map[string]any) map[string]any {
	if input == nil {
		return map[string]any{}
	}
	out := make(map[string]any, len(input))
	for key, value := range input {
		switch v := value.(type) {
		case string:
			out[key] = v
		case []string:
			out[key] = strings.Join(v, ", ")
		case []any:
			if len(v) == 0 {
				out[key] = ""
				continue
			}
			parts := make([]string, 0, len(v))
			for _, item := range v {
				if item == nil {
					continue
				}
				switch itemVal := item.(type) {
				case string:
					if strings.TrimSpace(itemVal) != "" {
						parts = append(parts, itemVal)
					}
				default:
					parts = append(parts, fmt.Sprintf("%v", itemVal))
				}
			}
			out[key] = strings.Join(parts, ", ")
		case nil:
			out[key] = ""
		default:
			out[key] = fmt.Sprintf("%v", v)
		}
	}
	return out
}

func fetchSignedURL(ctx context.Context, baseURL, apiKey, agentID string) (string, string, error) {
	url := fmt.Sprintf("%s/v1/convai/conversation/get-signed-url?agent_id=%s&include_conversation_id=true", baseURL, urlQueryEscape(agentID))
	req, _ := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	req.Header.Set("xi-api-key", apiKey)

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return "", "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		body, _ := io.ReadAll(resp.Body)
		return "", "", fmt.Errorf("signed-url failed status=%d body=%s", resp.StatusCode, string(body))
	}

	var payload struct {
		SignedURL      string `json:"signed_url"`
		URL            string `json:"url"`
		ConversationID string `json:"conversation_id"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&payload); err != nil {
		return "", "", err
	}
	if payload.SignedURL == "" {
		payload.SignedURL = payload.URL
	}
	if payload.SignedURL == "" {
		return "", "", errors.New("signed_url missing")
	}
	return payload.SignedURL, payload.ConversationID, nil
}

func readAgentResponse(ctx context.Context, conn *websocket.Conn) (string, string, error) {
	reply, conversationID, err := readAgentReply(ctx, conn, false)
	return reply.Text, conversationID, err
}

func sendTelegramMessage(ctx context.Context, token string, chatID int64, threadID string, text string) error {
	if token == "" {
		return errors.New("missing telegram token")
	}
	payload := map[string]any{
		"chat_id": chatID,
		"text":    text,
	}
	if threadID != "" {
		if id, err := strconv.ParseInt(threadID, 10, 64); err == nil {
			payload["message_thread_id"] = id
		}
	}
	body, _ := json.Marshal(payload)

	url := fmt.Sprintf("https://api.telegram.org/bot%s/sendMessage", token)
	req, _ := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		out, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("telegram send failed status=%d body=%s", resp.StatusCode, string(out))
	}
	return nil
}

func fetchSession(ctx context.Context, client *cloudfirestore.Client, channel, accountID, userID string) (*channelSession, error) {
	docID := sessionDocID(channel, accountID, userID)
	if docID == "" {
		return nil, nil
	}
	snap, err := client.Collection(channelSessionsCollection).Doc(docID).Get(ctx)
	if err != nil {
		if status.Code(err) == codes.NotFound {
			return nil, nil
		}
		return nil, err
	}
	var session channelSession
	if err := snap.DataTo(&session); err != nil {
		return nil, err
	}
	return &session, nil
}

func sessionCreatedAt(existing *channelSession) time.Time {
	if existing != nil && !existing.CreatedAt.IsZero() {
		return existing.CreatedAt
	}
	return time.Now().UTC()
}

func isStoreSwitchCommand(text string) bool {
	clean := strings.TrimSpace(strings.ToLower(text))
	if clean == "" {
		return false
	}
	switch clean {
	case "/store", "/switch", "/change_store", "/change-store", "switch store", "change store":
		return true
	default:
		return false
	}
}

func parseChoiceIndex(text string) int {
	parts := strings.Fields(strings.TrimSpace(text))
	if len(parts) == 0 {
		return 0
	}
	n, err := strconv.Atoi(parts[0])
	if err != nil {
		return 0
	}
	return n
}

func formatStoreChoicesMessage(choices []storeChoice) string {
	if len(choices) == 0 {
		return "Please type the restaurant name."
	}
	var b strings.Builder
	b.WriteString("I found multiple restaurants. Reply with the number:\n")
	for i, choice := range choices {
		b.WriteString(fmt.Sprintf("%d) %s\n", i+1, choice.Name))
	}
	return strings.TrimSpace(b.String())
}

type tenantCandidate struct {
	ID   string
	Name string
}

func searchStoreChoices(ctx context.Context, cfg *serviceConfig, client *cloudfirestore.Client, query string) ([]storeChoice, error) {
	if cfg != nil && cfg.TypesenseHost != "" && cfg.TypesenseAPIKey != "" {
		if choices, err := searchStoreChoicesTypesense(ctx, cfg, query, 5); err == nil && len(choices) > 0 {
			return choices, nil
		}
	}
	candidates, err := searchTenantsByName(ctx, client, query, 5)
	if err != nil {
		return nil, err
	}
	choices := make([]storeChoice, 0, len(candidates))
	for _, candidate := range candidates {
		storeID, businessType, err := fetchStoreForTenant(ctx, client, candidate.ID)
		if err != nil || storeID == "" {
			continue
		}
		choices = append(choices, storeChoice{
			Name:         candidate.Name,
			TenantID:     candidate.ID,
			StoreID:      storeID,
			BusinessType: businessType,
		})
	}
	return choices, nil
}

func searchTenantsByName(ctx context.Context, client *cloudfirestore.Client, query string, limit int) ([]tenantCandidate, error) {
	query = strings.TrimSpace(query)
	if query == "" {
		return nil, nil
	}
	if limit <= 0 {
		limit = 5
	}

	results := make([]tenantCandidate, 0, limit)
	seen := make(map[string]bool)
	variants := tenantQueryVariants(query)
	for _, variant := range variants {
		if len(results) >= limit {
			break
		}
		iter := client.Collection(tenantsCollection).
			OrderBy("name", cloudfirestore.Asc).
			StartAt(variant).
			EndAt(variant + "\uf8ff").
			Limit(limit).
			Documents(ctx)
		for {
			doc, err := iter.Next()
			if err != nil {
				if err == iterator.Done {
					break
				}
				return results, err
			}
			if seen[doc.Ref.ID] {
				continue
			}
			name := strings.TrimSpace(anyToString(doc.Data()["name"]))
			if name == "" {
				continue
			}
			results = append(results, tenantCandidate{ID: doc.Ref.ID, Name: name})
			seen[doc.Ref.ID] = true
			if len(results) >= limit {
				break
			}
		}
	}

	if len(results) > 0 {
		return results, nil
	}

	// Fallback: limited scan with case-insensitive contains (best-effort).
	iter := client.Collection(tenantsCollection).OrderBy("name", cloudfirestore.Asc).Limit(200).Documents(ctx)
	lower := strings.ToLower(query)
	for {
		doc, err := iter.Next()
		if err != nil {
			if err == iterator.Done {
				break
			}
			return results, err
		}
		if seen[doc.Ref.ID] {
			continue
		}
		name := strings.TrimSpace(anyToString(doc.Data()["name"]))
		if name == "" {
			continue
		}
		if strings.Contains(strings.ToLower(name), lower) {
			results = append(results, tenantCandidate{ID: doc.Ref.ID, Name: name})
			seen[doc.Ref.ID] = true
			if len(results) >= limit {
				break
			}
		}
	}
	return results, nil
}

type typesenseSearchResponse struct {
	Hits []struct {
		Document map[string]any `json:"document"`
	} `json:"hits"`
}

func searchStoreChoicesTypesense(ctx context.Context, cfg *serviceConfig, query string, limit int) ([]storeChoice, error) {
	if cfg == nil || cfg.TypesenseHost == "" || cfg.TypesenseAPIKey == "" {
		return nil, nil
	}
	host := strings.TrimSpace(cfg.TypesenseHost)
	if host == "" {
		return nil, nil
	}
	if !strings.HasPrefix(host, "http://") && !strings.HasPrefix(host, "https://") {
		host = "https://" + host
	}
	collection := strings.TrimSpace(cfg.TypesenseCollection)
	if collection == "" {
		collection = "stores"
	}
	if limit <= 0 {
		limit = 5
	}
	query = strings.TrimSpace(query)
	if query == "" {
		return nil, nil
	}

	searchURL := fmt.Sprintf("%s/collections/%s/documents/search?q=%s&query_by=%s&per_page=%d",
		strings.TrimRight(host, "/"),
		urlQueryEscape(collection),
		urlQueryEscape(query),
		urlQueryEscape("name,tenant_name,store_name,store_id"),
		limit,
	)
	req, _ := http.NewRequestWithContext(ctx, http.MethodGet, searchURL, nil)
	req.Header.Set("X-TYPESENSE-API-KEY", cfg.TypesenseAPIKey)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("typesense search failed status=%d body=%s", resp.StatusCode, string(body))
	}

	var payload typesenseSearchResponse
	if err := json.NewDecoder(resp.Body).Decode(&payload); err != nil {
		return nil, err
	}
	choices := make([]storeChoice, 0, len(payload.Hits))
	for _, hit := range payload.Hits {
		doc := hit.Document
		name := strings.TrimSpace(firstNonEmpty(anyToString(doc["name"]), anyToString(doc["tenant_name"]), anyToString(doc["store_name"])))
		tenantID := strings.TrimSpace(anyToString(doc["tenant_id"]))
		storeID := strings.TrimSpace(anyToString(doc["store_id"]))
		businessType := strings.TrimSpace(anyToString(doc["business_type"]))
		if tenantID == "" || storeID == "" {
			continue
		}
		if name == "" {
			name = storeID
		}
		choices = append(choices, storeChoice{
			Name:         name,
			TenantID:     tenantID,
			StoreID:      storeID,
			BusinessType: businessType,
		})
	}
	return choices, nil
}

func tenantQueryVariants(query string) []string {
	query = strings.TrimSpace(query)
	if query == "" {
		return nil
	}
	variants := []string{query}
	lower := strings.ToLower(query)
	if lower != query {
		variants = append(variants, lower)
	}
	title := strings.ToUpper(lower[:1]) + lower[1:]
	if title != query && title != lower {
		variants = append(variants, title)
	}
	upper := strings.ToUpper(query)
	if upper != query && upper != lower {
		variants = append(variants, upper)
	}
	return uniqueStrings(variants)
}

func fetchStoreForTenant(ctx context.Context, client *cloudfirestore.Client, tenantID string) (string, string, error) {
	if tenantID == "" {
		return "", "", nil
	}
	iter := client.Collection(storesCollection).
		Where("tenant_id", "==", tenantID).
		Limit(1).
		Documents(ctx)
	doc, err := iter.Next()
	if err != nil {
		if err == iterator.Done {
			iter = client.Collection(storesCollection).
				Where("tenantId", "==", tenantID).
				Limit(1).
				Documents(ctx)
			doc, err = iter.Next()
			if err != nil {
				if err == iterator.Done {
					return "", "", nil
				}
				return "", "", err
			}
		} else {
			return "", "", err
		}
	}
	data := doc.Data()
	storeID := strings.TrimSpace(anyToString(data["store_id"]))
	if storeID == "" {
		storeID = strings.TrimSpace(doc.Ref.ID)
	}
	businessType := strings.TrimSpace(firstNonEmpty(anyToString(data["business_type"]), anyToString(data["businessType"])))
	return storeID, businessType, nil
}

func mergeRouteData(route map[string]any, tenantID, storeID, businessType string) map[string]any {
	merged := make(map[string]any, len(route)+3)
	for k, v := range route {
		merged[k] = v
	}
	if tenantID != "" {
		merged["tenant_id"] = tenantID
		merged["tenantId"] = tenantID
	}
	if storeID != "" {
		merged["store_id"] = storeID
		merged["storeId"] = storeID
	}
	if businessType != "" {
		merged["business_type"] = businessType
		merged["businessType"] = businessType
	}
	return merged
}

func uniqueStrings(values []string) []string {
	seen := make(map[string]bool)
	out := make([]string, 0, len(values))
	for _, v := range values {
		v = strings.TrimSpace(v)
		if v == "" || seen[v] {
			continue
		}
		seen[v] = true
		out = append(out, v)
	}
	return out
}

func allowedOrigins() []string {
	defaults := []string{
		"http://localhost:3000",
		"http://localhost:4000",
		"http://localhost:5173",
		"http://localhost:8080",
		"http://localhost:*",
		"http://127.0.0.1:*",
	}
	if v := os.Getenv("CORS_ORIGINS"); v != "" {
		parts := strings.Split(v, ",")
		seen := map[string]struct{}{}
		out := make([]string, 0, len(parts)+len(defaults))
		for _, part := range parts {
			origin := strings.TrimSpace(part)
			if origin == "" {
				continue
			}
			if origin == "*" {
				return []string{"*"}
			}
			if _, ok := seen[origin]; ok {
				continue
			}
			seen[origin] = struct{}{}
			out = append(out, origin)
		}
		for _, origin := range defaults {
			if _, ok := seen[origin]; ok {
				continue
			}
			seen[origin] = struct{}{}
			out = append(out, origin)
		}
		if len(out) > 0 {
			return out
		}
	}
	return defaults
}

func startTelegramTyping(ctx context.Context, token string, chatID int64, threadID string) {
	ticker := time.NewTicker(4 * time.Second)
	defer ticker.Stop()

	_ = sendTelegramChatAction(ctx, token, chatID, threadID, "typing")
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			_ = sendTelegramChatAction(ctx, token, chatID, threadID, "typing")
		}
	}
}

func sendTelegramChatAction(ctx context.Context, token string, chatID int64, threadID string, action string) error {
	if token == "" {
		return errors.New("missing telegram token")
	}
	payload := map[string]any{
		"chat_id": chatID,
		"action":  action,
	}
	if threadID != "" {
		if id, err := strconv.ParseInt(threadID, 10, 64); err == nil {
			payload["message_thread_id"] = id
		}
	}
	body, _ := json.Marshal(payload)

	url := fmt.Sprintf("https://api.telegram.org/bot%s/sendChatAction", token)
	req, _ := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("telegram chat action failed status=%d body=%s", resp.StatusCode, string(body))
	}
	return nil
}

func upsertSession(ctx context.Context, client *cloudfirestore.Client, session channelSession) error {
	if client == nil {
		return errors.New("firestore client missing")
	}
	docID := sessionDocID(session.Channel, session.AccountID, session.UserID)
	if docID == "" {
		return errors.New("invalid session id")
	}
	payload := map[string]any{
		"channel":                    session.Channel,
		"account_id":                 session.AccountID,
		"user_id":                    session.UserID,
		"thread_id":                  session.ThreadID,
		"display_name":               session.DisplayName,
		"tenant_id":                  session.TenantID,
		"customer_id":                session.CustomerID,
		"store_id":                   session.StoreID,
		"business_type":              session.BusinessType,
		"auth_provider":              session.AuthProvider,
		"client_platform":            session.ClientPlatform,
		"client_app":                 session.ClientApp,
		"client_version":             session.ClientVersion,
		"elevenlabs_conversation_id": session.ElevenLabsConversationID,
		"seeded_intro":               session.SeededIntro,
		"seeded_source":              session.SeededSource,
		"seeded_context_sent":        session.SeededContextSent,
		"last_seen_at":               session.LastSeenAt,
	}
	if session.SeededCategories != nil {
		payload["seeded_categories"] = session.SeededCategories
	} else {
		payload["seeded_categories"] = []string{}
	}
	if !session.SeededAt.IsZero() {
		payload["seeded_at"] = session.SeededAt
	}
	if len(session.PendingStoreChoices) > 0 {
		payload["pending_store_choices"] = session.PendingStoreChoices
	} else {
		payload["pending_store_choices"] = []any{}
	}
	if session.CreatedAt.IsZero() {
		payload["created_at"] = time.Now().UTC()
	} else {
		payload["created_at"] = session.CreatedAt
	}
	_, err := client.Collection(channelSessionsCollection).Doc(docID).Set(ctx, payload, cloudfirestore.MergeAll)
	return err
}

func sessionDocID(channel, accountID, userID string) string {
	channel = strings.TrimSpace(strings.ToLower(channel))
	accountID = strings.TrimSpace(accountID)
	userID = strings.TrimSpace(userID)
	if channel == "" || accountID == "" || userID == "" {
		return ""
	}
	return fmt.Sprintf("%s_%s_%s", channel, accountID, userID)
}

func sessionKeyFromDyn(dyn map[string]any) string {
	channel := strings.TrimSpace(anyToString(dyn["channel"]))
	accountID := strings.TrimSpace(anyToString(dyn["channelAccountId"]))
	userID := strings.TrimSpace(anyToString(dyn["channelUserId"]))
	if channel != "" && accountID != "" && userID != "" {
		return fmt.Sprintf("%s_%s_%s", channel, accountID, userID)
	}
	storeID := strings.TrimSpace(anyToString(dyn["storeId"]))
	callerID := strings.TrimSpace(anyToString(dyn["callerId"]))
	return fmt.Sprintf("%s_%s", storeID, callerID)
}

func resolveAgentID(route map[string]any, fallback string) string {
	return strings.TrimSpace(firstNonEmpty(
		anyToString(route["elevenlabs_agent_id"]),
		anyToString(route["agent_id"]),
		anyToString(route["elevenlabs_agent_template_id"]),
		anyToString(route["agentId"]),
		fallback,
	))
}

func buildDisplayName(user *telegramUser) string {
	if user == nil {
		return ""
	}
	name := strings.TrimSpace(strings.Join([]string{strings.TrimSpace(user.FirstName), strings.TrimSpace(user.LastName)}, " "))
	if name == "" {
		name = strings.TrimSpace(user.Username)
	}
	return name
}

func getNestedString(m map[string]any, parentKey, childKey string) string {
	if m == nil {
		return ""
	}
	child, ok := m[parentKey].(map[string]any)
	if !ok {
		return ""
	}
	val, _ := child[childKey].(string)
	return strings.TrimSpace(val)
}

func writeJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(payload); err != nil {
		log.Printf("failed writing response: %v", err)
	}
}

func anyToString(v any) string {
	switch t := v.(type) {
	case string:
		return t
	default:
		return ""
	}
}

func firstNonEmpty(values ...string) string {
	for _, v := range values {
		v = strings.TrimSpace(v)
		if v != "" {
			return v
		}
	}
	return ""
}

func firstNonEmptyIntCandidate(values ...any) any {
	for _, v := range values {
		if intOrDefault(v, 0) != 0 {
			return v
		}
	}
	return nil
}

func stringOrDefault(value interface{}, fallback string) string {
	switch v := value.(type) {
	case string:
		if v == "" {
			return fallback
		}
		return v
	case int64:
		return fmt.Sprintf("%d", v)
	default:
		return fallback
	}
}

func splitCSV(value string) []string {
	parts := strings.Split(value, ",")
	out := make([]string, 0, len(parts))
	for _, part := range parts {
		part = strings.TrimSpace(part)
		if part == "" {
			continue
		}
		out = append(out, part)
	}
	return out
}

func intOrDefault(value interface{}, fallback int) int {
	switch v := value.(type) {
	case int64:
		return int(v)
	case float64:
		return int(v)
	case string:
		if v == "" {
			return fallback
		}
		if parsed, err := strconv.Atoi(v); err == nil {
			return parsed
		}
	}
	return fallback
}

func truncateForLog(data []byte, limit int) string {
	if len(data) == 0 {
		return ""
	}
	if limit <= 0 || len(data) <= limit {
		return string(data)
	}
	return string(data[:limit]) + "..."
}

func stringOrDefaultEnv(key string) string {
	return strings.TrimSpace(os.Getenv(key))
}

func urlQueryEscape(s string) string {
	return strings.ReplaceAll(strings.ReplaceAll(strings.TrimSpace(s), " ", "%20"), "+", "%2B")
}
