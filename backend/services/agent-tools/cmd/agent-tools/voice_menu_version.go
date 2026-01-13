package main

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"hash"
	"sort"
	"strings"
)

const voiceMenuPromptVersion = "v1"

func menuVersionForSnapshot(snap orderMenuSnapshot) string {
	if strings.TrimSpace(snap.Updated) != "" {
		return strings.TrimSpace(snap.Updated)
	}
	// Fall back to a stable content hash when no updated timestamp exists.
	return "hash:" + stableMenuHash(snap.Items)
}

func stableMenuHash(items []menuItem) string {
	// Sort to make hashing stable regardless of upstream ordering.
	cp := make([]menuItem, 0, len(items))
	cp = append(cp, items...)
	sort.Slice(cp, func(i, j int) bool {
		return strings.TrimSpace(cp[i].ID) < strings.TrimSpace(cp[j].ID)
	})

	h := sha256.New()
	for _, it := range cp {
		// Only include fields that should invalidate the voice-menu script.
		// Keep it minimal to avoid churn.
		writeHashField(h, it.ID)
		writeHashField(h, it.Name)
		writeHashField(h, it.Category)
		writeHashField(h, it.Description)
		writeHashField(h, it.Available)
		writeHashField(h, it.PriceCents)
	}
	return hex.EncodeToString(h.Sum(nil))
}

func writeHashField(h hash.Hash, v any) {
	// Normalize and delimit so fields don't collide.
	_, _ = h.Write([]byte(fmt.Sprintf("%v", v)))
	_, _ = h.Write([]byte{0})
}
