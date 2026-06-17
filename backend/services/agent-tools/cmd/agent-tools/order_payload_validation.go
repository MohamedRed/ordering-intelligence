package main

import (
	"encoding/json"
	"log"
	"strings"
)

type orderCreatePayloadSummary struct {
	StoreID      string `json:"storeId"`
	TenantID     string `json:"tenantId"`
	CallerID     string `json:"callerId"`
	CallSid      string `json:"callSid"`
	CustomerName string `json:"customerName"`
	Items        []struct {
		ItemID   string `json:"itemId"`
		Name     string `json:"name"`
		Quantity int    `json:"quantity"`
	} `json:"items"`
}

func logCreateOrderPayload(body []byte) {
	var payload orderCreatePayloadSummary
	if err := json.Unmarshal(body, &payload); err != nil {
		log.Printf("create-order payload parse failed: %v", err)
		return
	}
	itemIDs := make([]string, 0, len(payload.Items))
	for _, it := range payload.Items {
		id := strings.TrimSpace(it.ItemID)
		if id == "" {
			id = strings.TrimSpace(it.Name)
		}
		if id != "" {
			itemIDs = append(itemIDs, id)
		}
	}
	log.Printf(
		"create-order payload summary store=%s tenant=%s items=%d ids=%v caller_set=%t callSid_set=%t customer_set=%t",
		strings.TrimSpace(payload.StoreID),
		strings.TrimSpace(payload.TenantID),
		len(payload.Items),
		itemIDs,
		strings.TrimSpace(payload.CallerID) != "",
		strings.TrimSpace(payload.CallSid) != "",
		strings.TrimSpace(payload.CustomerName) != "",
	)
	if len(payload.Items) == 0 {
		log.Printf("create-order payload raw=%s", truncateForLog(body, 2000))
	}
}

func truncateForLog(body []byte, max int) string {
	if len(body) <= max {
		return string(body)
	}
	return string(body[:max]) + "...(truncated)"
}

type createOrderError struct {
	Error         string            `json:"error"`
	Message       string            `json:"message"`
	ExpectedShape map[string]any    `json:"expected_shape,omitempty"`
	Hint          string            `json:"hint,omitempty"`
	MissingFields []string          `json:"missing_fields,omitempty"`
	ItemIndex     int               `json:"item_index,omitempty"`
	ItemMissing   []string          `json:"item_missing_fields,omitempty"`
	Details       map[string]string `json:"details,omitempty"`
}

func validateCreateOrderPayload(body []byte) *createOrderError {
	var payload map[string]any
	if err := json.Unmarshal(body, &payload); err != nil {
		return &createOrderError{
			Error:   "invalid_json",
			Message: "Request body must be valid JSON.",
			Hint:    "Ensure the tool call sends a JSON object with storeId and items.",
		}
	}

	missing := []string{}
	storeID, _ := payload["storeId"].(string)
	if strings.TrimSpace(storeID) == "" {
		missing = append(missing, "storeId")
	}

	itemsRaw, ok := payload["items"]
	if !ok {
		missing = append(missing, "items")
	}
	if len(missing) > 0 {
		return &createOrderError{
			Error:         "missing_fields",
			Message:       "Missing required fields for create-order.",
			MissingFields: missing,
			ExpectedShape: map[string]any{
				"items": []map[string]string{
					{"itemId": "string", "name": "string", "quantity": "number", "priceCents": "number"},
				},
			},
			Hint: "Use normalizedItems returned by validate-draft.",
		}
	}

	items, ok := itemsRaw.([]any)
	if !ok {
		return &createOrderError{
			Error:   "invalid_items",
			Message: "items must be an array.",
			Hint:    "Pass the normalizedItems array from validate-draft.",
		}
	}
	if len(items) == 0 {
		return &createOrderError{
			Error:   "invalid_items",
			Message: "items must contain at least 1 item.",
			Hint:    "Pass the normalizedItems array from validate-draft.",
		}
	}

	for idx, item := range items {
		itemMap, ok := item.(map[string]any)
		if !ok {
			return &createOrderError{
				Error:     "invalid_item",
				Message:   "Each item must be an object.",
				ItemIndex: idx,
				Hint:      "Use normalizedItems from validate-draft.",
			}
		}
		itemMissing := []string{}
		if strings.TrimSpace(asString(itemMap["itemId"])) == "" {
			itemMissing = append(itemMissing, "itemId")
		}
		if strings.TrimSpace(asString(itemMap["name"])) == "" {
			itemMissing = append(itemMissing, "name")
		}
		if _, ok := itemMap["quantity"]; !ok {
			itemMissing = append(itemMissing, "quantity")
		}
		if _, ok := itemMap["priceCents"]; !ok {
			itemMissing = append(itemMissing, "priceCents")
		}
		if len(itemMissing) > 0 {
			return &createOrderError{
				Error:       "invalid_item_fields",
				Message:     "Item missing required fields.",
				ItemIndex:   idx,
				ItemMissing: itemMissing,
				Hint:        "Use normalizedItems from validate-draft.",
			}
		}
	}

	return nil
}

func asString(v any) string {
	switch t := v.(type) {
	case string:
		return t
	default:
		return ""
	}
}
