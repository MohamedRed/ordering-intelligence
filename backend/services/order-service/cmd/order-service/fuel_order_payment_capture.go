package main

import (
	"context"
	"fmt"
	"io"
	"net/http"
)

func captureFuelPayment(
	ctx context.Context,
	cfg *serviceConfig,
	orderID string,
	amountCents int64,
) error {
	payload := map[string]any{"amountCents": amountCents}
	resp, err := doPaymentsJSONRequest(ctx, cfg, http.MethodPost, fmt.Sprintf("/orders/%s/capture", orderID), payload)
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
