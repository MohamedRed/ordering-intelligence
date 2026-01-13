package main

import (
	"crypto/ed25519"
	"encoding/hex"
)

func verifyDiscordSignature(publicKeyHex, signatureHex, timestamp string, body []byte) bool {
	if publicKeyHex == "" || signatureHex == "" || timestamp == "" {
		return false
	}
	publicKey, err := hex.DecodeString(publicKeyHex)
	if err != nil || len(publicKey) == 0 {
		return false
	}
	signature, err := hex.DecodeString(signatureHex)
	if err != nil || len(signature) == 0 {
		return false
	}
	message := append([]byte(timestamp), body...)
	return ed25519.Verify(ed25519.PublicKey(publicKey), message, signature)
}
