package main

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
	"github.com/redis/go-redis/v9"
)

type voiceMenuCache struct {
	redis     *redis.Client
	firestore *cloudfirestore.Client
	ttl       time.Duration
}

func newVoiceMenuCache(ctx context.Context, cfg *serviceConfig) (*voiceMenuCache, error) {
	var rdb *redis.Client
	if cfg.RedisAddr != "" {
		rdb = redis.NewClient(&redis.Options{
			Addr:     cfg.RedisAddr,
			Password: cfg.RedisPassword,
			DB:       cfg.RedisDB,
		})
		// Best-effort connectivity check; don't fail startup if Redis is down.
		pctx, cancel := context.WithTimeout(ctx, 800*time.Millisecond)
		defer cancel()
		if err := rdb.Ping(pctx).Err(); err != nil {
			_ = rdb.Close()
			rdb = nil
		}
	}

	var fsc *cloudfirestore.Client
	if cfg.FirestoreProjectID != "" {
		c, err := cloudfirestore.NewClient(ctx, cfg.FirestoreProjectID)
		if err != nil {
			return nil, err
		}
		fsc = c
	}

	ttl := time.Duration(cfg.VoiceMenuCacheTTLSeconds) * time.Second
	return &voiceMenuCache{redis: rdb, firestore: fsc, ttl: ttl}, nil
}

func (c *voiceMenuCache) Close() error {
	var firstErr error
	if c.redis != nil {
		if err := c.redis.Close(); err != nil {
			firstErr = err
		}
	}
	if c.firestore != nil {
		if err := c.firestore.Close(); err != nil && firstErr == nil {
			firstErr = err
		}
	}
	return firstErr
}

func voiceMenuCacheKey(storeID, menuVersion, model, promptVersion string) string {
	return fmt.Sprintf("voice_menu:%s:%s:%s:%s", storeID, menuVersion, model, promptVersion)
}

func (c *voiceMenuCache) GetScript(ctx context.Context, key string) (*voiceMenuScriptArtifact, string, error) {
	if key == "" {
		return nil, "", errors.New("missing cache key")
	}

	// 1) Redis hot cache
	if c.redis != nil {
		val, err := c.redis.Get(ctx, key).Result()
		if err == nil && val != "" {
			var art voiceMenuScriptArtifact
			if err := json.Unmarshal([]byte(val), &art); err == nil && strings.TrimSpace(art.SpokenMenuFr) != "" {
				return &art, "redis", nil
			}
		}
	}

	// 2) Firestore durable store
	if c.firestore != nil {
		docID := cacheDocID(key)
		doc, err := c.firestore.Collection("voice_menus").Doc(docID).Get(ctx)
		if err == nil && doc.Exists() {
			raw, _ := doc.Data()["payload_json"].(string)
			if raw != "" {
				var art voiceMenuScriptArtifact
				if err := json.Unmarshal([]byte(raw), &art); err == nil && strings.TrimSpace(art.SpokenMenuFr) != "" {
					// Backfill Redis for speed (best-effort)
					if c.redis != nil {
						_ = c.redis.Set(ctx, key, raw, c.ttl).Err()
					}
					return &art, "firestore", nil
				}
			}
		}
	}

	return nil, "", nil
}

func (c *voiceMenuCache) PutScript(ctx context.Context, key string, meta map[string]any, art voiceMenuScriptArtifact) error {
	if key == "" {
		return errors.New("missing cache key")
	}
	raw, err := json.Marshal(art)
	if err != nil {
		return err
	}

	// Redis
	if c.redis != nil {
		_ = c.redis.Set(ctx, key, string(raw), c.ttl).Err()
	}

	// Firestore
	if c.firestore != nil {
		docID := cacheDocID(key)
		payload := map[string]any{
			"key":          key,
			"payload_json": string(raw),
			"generated_at": time.Now().UTC(),
		}
		for k, v := range meta {
			payload[k] = v
		}
		_, err := c.firestore.Collection("voice_menus").Doc(docID).Set(ctx, payload, cloudfirestore.MergeAll)
		return err
	}
	return nil
}

func cacheDocID(key string) string {
	sum := sha256.Sum256([]byte(key))
	return hex.EncodeToString(sum[:])
}
