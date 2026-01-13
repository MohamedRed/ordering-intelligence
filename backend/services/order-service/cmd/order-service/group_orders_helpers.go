package main

import (
	"strings"

	"github.com/google/uuid"
)

func newGroupOrderID() string {
	return "group_" + uuid.NewString()
}

func groupOrderJoinCode(groupID string) string {
	code := strings.ReplaceAll(groupID, "-", "")
	code = strings.ReplaceAll(code, "group_", "")
	if len(code) <= 8 {
		return code
	}
	return strings.ToUpper(code[len(code)-8:])
}

func newGroupOrderInviteID() string {
	return strings.ToUpper(uuid.NewString()[:8])
}

func participantIDFromContact(contact channelContact, fallback string) string {
	if strings.TrimSpace(fallback) != "" {
		return strings.TrimSpace(fallback)
	}
	if strings.TrimSpace(contact.UserID) != "" {
		return strings.TrimSpace(contact.UserID)
	}
	if strings.TrimSpace(contact.AccountID) != "" {
		return strings.TrimSpace(contact.AccountID)
	}
	return strings.TrimSpace(contact.DisplayName)
}

func normalizeGroupPaymentMode(mode string) string {
	mode = strings.TrimSpace(strings.ToLower(mode))
	if mode == groupOrderPaymentSingle || mode == groupOrderPaymentSplit {
		return mode
	}
	return groupOrderPaymentSingle
}

func normalizeGroupPaymentMethod(method string) string {
	method = strings.TrimSpace(strings.ToLower(method))
	if method == groupOrderPaymentMethodCash || method == groupOrderPaymentMethodCard {
		return method
	}
	return groupOrderPaymentMethodCash
}
