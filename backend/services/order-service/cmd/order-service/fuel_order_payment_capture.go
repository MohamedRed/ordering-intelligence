package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
)

func captureFuelPayment(
	ctx context.Context,
	paymentsServiceURL string,
	orderID string,
	amountCents int64,
) error {
	payload := map[string]any{"amountCents": amountCents}
	body, _ := json.Marshal(payload)
	endpoint := fmt.Sprintf("%s/orders/%s/capture", strings.TrimRight(paymentsServiceURL, "/"), orderID)
	req, _ := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		respBody, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("capture_failed: %s", string(respBody))
	}
	return nil
}
