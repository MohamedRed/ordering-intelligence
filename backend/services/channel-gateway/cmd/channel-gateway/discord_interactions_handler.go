package main

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"strings"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
)

func handleDiscordInteractions(
	w http.ResponseWriter,
	r *http.Request,
	cfg *serviceConfig,
	firestoreClient *cloudfirestore.Client,
) {
	body, err := io.ReadAll(r.Body)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_body"})
		return
	}
	publicKey := strings.TrimSpace(cfg.DiscordPublicKey)
	signature := strings.TrimSpace(r.Header.Get("X-Signature-Ed25519"))
	timestamp := strings.TrimSpace(r.Header.Get("X-Signature-Timestamp"))
	if publicKey == "" || signature == "" || timestamp == "" {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "missing_signature"})
		return
	}
	if !verifyDiscordSignature(publicKey, signature, timestamp, body) {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid_signature"})
		return
	}

	var interaction discordInteraction
	if err := json.Unmarshal(body, &interaction); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 6*time.Second)
	defer cancel()

	switch interaction.Type {
	case discordInteractionPing:
		writeJSON(w, http.StatusOK, discordInteractionResponse{Type: discordResponsePong})
	case discordInteractionCommand:
		resp := buildDiscordCommandResponse(ctx, cfg, firestoreClient, interaction)
		writeJSON(w, http.StatusOK, resp)
	case discordInteractionMessageComponent:
		resp := handleDiscordComponentInteraction(ctx, cfg, firestoreClient, interaction)
		writeJSON(w, http.StatusOK, resp)
	default:
		writeJSON(w, http.StatusOK, discordTextResponse("Unsupported interaction."))
	}
}
