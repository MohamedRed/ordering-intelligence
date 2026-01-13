package main

import (
	"crypto/sha256"
	"encoding/hex"
	"strings"
)

func hashCaller(callerID string) string {
	sum := sha256.Sum256([]byte(strings.TrimSpace(callerID)))
	return hex.EncodeToString(sum[:])
}
