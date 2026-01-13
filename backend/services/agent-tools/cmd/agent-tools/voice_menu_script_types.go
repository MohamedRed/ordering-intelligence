package main

// voiceMenuScriptArtifact is the cached LLM-derived artifact.
// We intentionally do NOT cache the full structured menu items to avoid Firestore doc-size limits
// and to always keep canonical prices/availability from order-service.
type voiceMenuScriptArtifact struct {
	SpokenMenuFr     string   `json:"spokenMenuFr"`
	SuggestedFlowFr  []string `json:"suggestedFlowFr"`
	MentionedItemIDs []string `json:"mentionedItemIds,omitempty"`
}
