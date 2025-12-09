FROM golang:1.22-alpine AS builder
ENV GOTOOLCHAIN=auto
WORKDIR /workspace
COPY backend/libs/shared/config backend/libs/shared/config
COPY backend/services/order-service/go.mod backend/services/order-service/go.sum* backend/services/order-service/
WORKDIR /workspace/backend/services/order-service
RUN go mod download
COPY backend/services/order-service/cmd ./cmd
COPY backend/services/order-service/internal ./internal
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /workspace/order-service ./cmd/order-service

FROM gcr.io/distroless/base-debian12
COPY --from=builder /workspace/order-service /order-service
ENV PORT=8082
EXPOSE 8082
ENTRYPOINT ["/order-service"]
