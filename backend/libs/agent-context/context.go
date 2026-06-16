package agentcontext

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"strconv"
	"strings"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
	"google.golang.org/api/idtoken"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

const (
	PhoneNumberRoutesCollection = "phone_number_routes"
	AgentRoutesCollection       = "agent_routes"
	ChannelRoutesCollection     = "channel_routes"
)

type RouteLookup struct {
	PhoneNumberID    string
	AgentNumber      string
	AgentID          string
	Channel          string
	ChannelAccountID string
}

type RouteResolution struct {
	Source string
	DocID  string
	Data   map[string]any
}

type ServicesConfig struct {
	CustomerProfileServiceURL string
	RecommendationServiceURL  string
	WaitTimeServiceURL        string
}

type DynamicVarsInput struct {
	CallerID             string
	CallSid              string
	AgentID              string
	AgentNumber          string
	PhoneNumberID        string
	CalledNumber         string
	Channel              string
	ChannelAccountID     string
	ChannelUserID        string
	ChannelThreadID      string
	ChannelDisplayName   string
	FallbackCustomerName string
}

type DynamicVarsOptions struct {
	IncludeChannelVars bool
}

func ResolveRoute(ctx context.Context, client *cloudfirestore.Client, lookup RouteLookup) (*RouteResolution, error) {
	if client == nil {
		return nil, fmt.Errorf("firestore client is nil")
	}

	if id := strings.TrimSpace(lookup.PhoneNumberID); id != "" {
		docID := DocIDFromElevenLabsPhoneNumberID(id)
		route := fetchRouteDoc(ctx, client, PhoneNumberRoutesCollection, docID)
		if route != nil {
			return &RouteResolution{Source: PhoneNumberRoutesCollection, DocID: docID, Data: route}, nil
		}
	}

	if num := strings.TrimSpace(lookup.AgentNumber); num != "" {
		docID := DocIDFromToNumber(num)
		route := fetchRouteDoc(ctx, client, PhoneNumberRoutesCollection, docID)
		if route != nil {
			return &RouteResolution{Source: PhoneNumberRoutesCollection, DocID: docID, Data: route}, nil
		}
	}

	if id := strings.TrimSpace(lookup.AgentID); id != "" {
		docID := DocIDFromAgentID(id)
		route := fetchRouteDoc(ctx, client, AgentRoutesCollection, docID)
		if route != nil {
			return &RouteResolution{Source: AgentRoutesCollection, DocID: docID, Data: route}, nil
		}
	}

	if strings.TrimSpace(lookup.Channel) != "" && strings.TrimSpace(lookup.ChannelAccountID) != "" {
		docID := DocIDFromChannelAccount(lookup.Channel, lookup.ChannelAccountID)
		route := fetchRouteDoc(ctx, client, ChannelRoutesCollection, docID)
		if route != nil {
			return &RouteResolution{Source: ChannelRoutesCollection, DocID: docID, Data: route}, nil
		}
	}

	return nil, nil
}

func BuildDynamicVariables(ctx context.Context, route RouteResolution, input DynamicVarsInput, services ServicesConfig, opts DynamicVarsOptions) map[string]any {
	data := route.Data
	if data == nil {
		data = map[string]any{}
	}

	storeID := strings.TrimSpace(firstNonEmpty(anyToString(data["store_id"]), anyToString(data["storeId"])))
	tenantID := strings.TrimSpace(firstNonEmpty(anyToString(data["tenant_id"]), anyToString(data["tenantId"])))
	businessType := strings.TrimSpace(firstNonEmpty(anyToString(data["business_type"]), anyToString(data["businessType"])))
	onboardingSessionID := strings.TrimSpace(firstNonEmpty(anyToString(data["onboarding_session_id"]), anyToString(data["onboardingSessionId"])))

	demoCallerID := strings.TrimSpace(firstNonEmpty(anyToString(data["demo_caller_id"]), anyToString(data["demoCallerId"])))
	demoCallSid := strings.TrimSpace(firstNonEmpty(anyToString(data["demo_call_sid"]), anyToString(data["demoCallSid"])))
	demoCustomerName := strings.TrimSpace(firstNonEmpty(anyToString(data["demo_customer_name"]), anyToString(data["demoCustomerName"])))
	demoIsReturning := anyToBool(firstNonEmpty(anyToString(data["demo_is_returning_customer"]), anyToString(data["demoIsReturningCustomer"])))
	demoTopReorders := anyToStringSlice(data["demo_top_reorders"])
	if len(demoTopReorders) == 0 {
		demoTopReorders = anyToStringSlice(data["demoTopReorders"])
	}
	demoEtaMinutes := anyToInt(firstNonEmpty(anyToString(data["demo_eta_minutes"]), anyToString(data["demoEtaMinutes"])))

	agentPhoneNumberID := strings.TrimSpace(firstNonEmpty(input.PhoneNumberID, anyToString(data["elevenlabs_phone_number_id"])))
	agentNumberClean := NormalizePhoneNumber(input.AgentNumber)
	if agentNumberClean == "" {
		agentNumberClean = NormalizePhoneNumber(anyToString(data["to_number"]))
	}
	if agentNumberClean == "" && strings.TrimSpace(input.CalledNumber) != "" {
		agentNumberClean = NormalizePhoneNumber(input.CalledNumber)
	}

	callerID := strings.TrimSpace(input.CallerID)
	if callerID == "" && demoCallerID != "" {
		callerID = demoCallerID
	}
	callSid := strings.TrimSpace(input.CallSid)
	if callSid == "" && demoCallSid != "" {
		callSid = demoCallSid
	}

	dyn := map[string]any{
		"storeId":             storeID,
		"tenantId":            tenantID,
		"businessType":        businessType,
		"agentPhoneNumberId":  agentPhoneNumberID,
		"agentNumber":         agentNumberClean,
		"callerId":            "",
		"callSid":             "",
		"customerName":        "",
		"isReturningCustomer": false,
		"topReorders":         []any{},
		"eta_minutes":         0,
	}

	if callerID != "" {
		normalized := NormalizePhoneNumber(callerID)
		if normalized != "" && looksLikePhone(callerID, normalized) {
			dyn["callerId"] = normalized
		} else {
			dyn["callerId"] = callerID
		}
	}
	if callSid != "" {
		dyn["callSid"] = callSid
	}
	if onboardingSessionID != "" {
		dyn["onboardingSessionId"] = onboardingSessionID
	}

	if opts.IncludeChannelVars {
		dyn["channel"] = strings.TrimSpace(input.Channel)
		dyn["channelAccountId"] = strings.TrimSpace(input.ChannelAccountID)
		dyn["channelUserId"] = strings.TrimSpace(input.ChannelUserID)
		dyn["channelThreadId"] = strings.TrimSpace(input.ChannelThreadID)
		dyn["channelDisplayName"] = strings.TrimSpace(input.ChannelDisplayName)
	}

	if demoEtaMinutes > 0 {
		dyn["eta_minutes"] = demoEtaMinutes
	} else if storeID != "" {
		eta := fetchWaitTimeEstimate(ctx, services.WaitTimeServiceURL, storeID)
		if eta <= 0 {
			eta = 15
		}
		dyn["eta_minutes"] = eta
	}

	callerClean := ""
	if strings.TrimSpace(callerID) != "" {
		callerClean = NormalizePhoneNumber(callerID)
		if callerClean != "" && looksLikePhone(callerID, callerClean) {
			customerName, isReturning := fetchCustomerIdentity(ctx, services.CustomerProfileServiceURL, tenantID, callerClean)
			if isReturning && strings.TrimSpace(customerName) != "" {
				dyn["customerName"] = customerName
			}
			dyn["isReturningCustomer"] = isReturning
		}
	}
	identityChannel := strings.TrimSpace(input.Channel)
	identityUserID := strings.TrimSpace(input.ChannelUserID)
	identityName := strings.TrimSpace(input.ChannelDisplayName)
	if identityUserID == "" && callerClean != "" {
		identityUserID = callerClean
		if identityChannel == "" {
			identityChannel = "phone"
		}
	}
	if identityChannel != "" && identityUserID != "" {
		customerID := resolveCustomerID(ctx, services.CustomerProfileServiceURL, tenantID, identityChannel, identityUserID, identityName)
		if customerID != "" {
			dyn["customerId"] = customerID
			reorders := fetchTopReorders(ctx, services.RecommendationServiceURL, tenantID, customerID, storeID)
			if reorders != nil {
				dyn["topReorders"] = reorders
			}
		}
	}

	if (dyn["customerName"] == "" || dyn["customerName"] == nil) && demoCustomerName != "" {
		dyn["customerName"] = demoCustomerName
	}
	if demoIsReturning != nil {
		dyn["isReturningCustomer"] = *demoIsReturning
	}
	if len(demoTopReorders) > 0 {
		dyn["topReorders"] = demoTopReorders
	}
	if (dyn["customerName"] == "" || dyn["customerName"] == nil) && strings.TrimSpace(input.FallbackCustomerName) != "" {
		dyn["customerName"] = strings.TrimSpace(input.FallbackCustomerName)
	}

	return dyn
}

func looksLikePhone(raw, normalized string) bool {
	raw = strings.TrimSpace(raw)
	if strings.HasPrefix(raw, "+") {
		return true
	}
	// Basic heuristic: phone numbers are typically >= 10 digits.
	return len(normalized) >= 10
}

func fetchRouteDoc(ctx context.Context, client *cloudfirestore.Client, collection, docID string) map[string]any {
	if docID == "" {
		return nil
	}
	doc, err := client.Collection(collection).Doc(docID).Get(ctx)
	if err != nil {
		if status.Code(err) == codes.NotFound {
			return nil
		}
		log.Printf("agent-context: firestore read failed collection=%s doc=%s err=%v", collection, docID, err)
		return nil
	}
	return doc.Data()
}

func DocIDFromAgentID(id string) string {
	return "agent_" + strings.TrimSpace(id)
}

func DocIDFromElevenLabsPhoneNumberID(id string) string {
	return "elpn_" + strings.TrimSpace(id)
}

func DocIDFromToNumber(to string) string {
	n := NormalizePhoneNumber(to)
	return "to_" + strings.TrimPrefix(n, "+")
}

func DocIDFromChannelAccount(channel, accountID string) string {
	return strings.ToLower(strings.TrimSpace(channel)) + "_" + strings.TrimSpace(accountID)
}

func NormalizePhoneNumber(p string) string {
	p = strings.TrimSpace(p)
	if p == "" {
		return ""
	}
	var b strings.Builder
	for i := 0; i < len(p); i++ {
		ch := p[i]
		if ch >= '0' && ch <= '9' {
			b.WriteByte(ch)
			continue
		}
		if ch == '+' && b.Len() == 0 {
			b.WriteByte(ch)
		}
	}
	return b.String()
}

func anyToString(v any) string {
	switch t := v.(type) {
	case string:
		return t
	default:
		return ""
	}
}

func anyToBool(v any) *bool {
	switch t := v.(type) {
	case bool:
		return &t
	case string:
		trimmed := strings.TrimSpace(strings.ToLower(t))
		if trimmed == "" {
			return nil
		}
		if trimmed == "true" || trimmed == "1" || trimmed == "yes" {
			b := true
			return &b
		}
		if trimmed == "false" || trimmed == "0" || trimmed == "no" {
			b := false
			return &b
		}
	}
	return nil
}

func anyToInt(v any) int {
	switch t := v.(type) {
	case int:
		return t
	case int64:
		return int(t)
	case float64:
		return int(t)
	case string:
		if i, err := strconv.Atoi(strings.TrimSpace(t)); err == nil {
			return i
		}
	}
	return 0
}

func anyToStringSlice(v any) []string {
	switch t := v.(type) {
	case []string:
		return t
	case []any:
		out := make([]string, 0, len(t))
		for _, item := range t {
			if s := strings.TrimSpace(anyToString(item)); s != "" {
				out = append(out, s)
			}
		}
		return out
	case string:
		if s := strings.TrimSpace(t); s != "" {
			return []string{s}
		}
	}
	return nil
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

func fetchWaitTimeEstimate(ctx context.Context, baseURL, storeID string) int {
	base := strings.TrimSpace(baseURL)
	if base == "" || strings.TrimSpace(storeID) == "" {
		return 0
	}
	cctx, cancel := context.WithTimeout(ctx, 850*time.Millisecond)
	defer cancel()
	client, err := idtoken.NewClient(cctx, base)
	if err != nil {
		return 0
	}
	url := fmt.Sprintf("%s/v1/stores/%s/wait-time/estimate", strings.TrimRight(base, "/"), urlQueryEscape(storeID))
	req, _ := http.NewRequestWithContext(cctx, http.MethodGet, url, nil)
	resp, err := client.Do(req)
	if err != nil {
		return 0
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return 0
	}
	var out struct {
		ETAMinutes int `json:"etaMinutes"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return 0
	}
	return out.ETAMinutes
}

func fetchCustomerIdentity(ctx context.Context, baseURL, tenantID, callerID string) (string, bool) {
	base := strings.TrimSpace(baseURL)
	if base == "" {
		return "", false
	}
	cctx, cancel := context.WithTimeout(ctx, 800*time.Millisecond)
	defer cancel()
	client, err := idtoken.NewClient(cctx, base)
	if err != nil {
		return "", false
	}
	url := fmt.Sprintf("%s/v1/customers/by-phone?tenantId=%s&callerId=%s", strings.TrimRight(base, "/"), urlQueryEscape(tenantID), urlQueryEscape(callerID))
	req, _ := http.NewRequestWithContext(cctx, http.MethodGet, url, nil)
	resp, err := client.Do(req)
	if err != nil {
		return "", false
	}
	defer resp.Body.Close()
	var out struct {
		IsReturning  bool   `json:"isReturning"`
		CustomerName string `json:"customerName"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return "", false
	}
	return strings.TrimSpace(out.CustomerName), out.IsReturning
}

func urlQueryEscape(s string) string {
	return strings.ReplaceAll(strings.ReplaceAll(strings.TrimSpace(s), " ", "%20"), "+", "%2B")
}
