package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
)

func answerTelegramInlineQuery(ctx context.Context, token string, answer telegramInlineQueryAnswer) error {
	if strings.TrimSpace(token) == "" {
		return errors.New("missing telegram token")
	}
	payload, err := json.Marshal(answer)
	if err != nil {
		return err
	}
	endpoint := fmt.Sprintf("https://api.telegram.org/bot%s/answerInlineQuery", token)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(payload))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 300 {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("telegram inline failed status=%d body=%s", resp.StatusCode, string(body))
	}
	return nil
}
