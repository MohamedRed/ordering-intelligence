package main

import (
	"crypto/rand"
	"encoding/hex"
)

func newRandomID(size int) (string, error) {
	buf := make([]byte, size)
	if _, err := rand.Read(buf); err != nil {
		return "", err
	}
	return hex.EncodeToString(buf), nil
}

func newCustomerID() (string, error) {
	return newRandomID(16)
}

func newLinkToken() (string, error) {
	return newRandomID(12)
}
