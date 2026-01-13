FROM golang:1.24-alpine AS builder
WORKDIR /app/backend/services/typesense-indexer

COPY backend/services/typesense-indexer/go.mod backend/services/typesense-indexer/go.sum* ./
RUN go mod download

COPY backend/services/typesense-indexer/cmd ./cmd

RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o typesense-indexer ./cmd/typesense-indexer

FROM gcr.io/distroless/base-debian12
WORKDIR /
COPY --from=builder /app/backend/services/typesense-indexer/typesense-indexer /typesense-indexer
EXPOSE 8080
ENTRYPOINT ["/typesense-indexer"]
