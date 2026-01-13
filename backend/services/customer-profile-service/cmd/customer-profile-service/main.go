package main

import (
	"context"
	"log"
	"net/http"
	"time"

	"github.com/joho/godotenv"
)

func main() {
	_ = godotenv.Load()

	cfg, err := loadConfig()
	if err != nil {
		log.Fatalf("failed to load config: %v", err)
	}

	ctx := context.Background()
	fs, err := newFirestoreClient(ctx, cfg)
	if err != nil {
		log.Fatalf("failed to create firestore client: %v", err)
	}
	defer fs.Close()

	server := &http.Server{
		Addr:              ":" + cfg.Port,
		Handler:           buildRouter(cfg, fs),
		ReadHeaderTimeout: 5 * time.Second,
	}

	log.Printf("customer-profile-service listening on :%s", cfg.Port)
	log.Fatal(server.ListenAndServe())
}
