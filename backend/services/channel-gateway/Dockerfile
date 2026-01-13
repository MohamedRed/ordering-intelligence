FROM golang:1.24-alpine AS builder
WORKDIR /app/backend/services/channel-gateway

# Keep repository-relative paths so go.mod replace directives resolve.
COPY backend/services/channel-gateway/go.mod backend/services/channel-gateway/go.sum* ./
COPY backend/libs/shared/config/go.mod backend/libs/shared/config/go.sum* ../../libs/shared/config/
COPY backend/libs/agent-context/go.mod backend/libs/agent-context/go.sum* ../../libs/agent-context/
RUN go mod download

COPY backend/services/channel-gateway/cmd ./cmd
COPY backend/libs/shared/config ../../libs/shared/config
COPY backend/libs/agent-context ../../libs/agent-context

RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o channel-gateway ./cmd/channel-gateway

FROM gcr.io/distroless/base-debian12
WORKDIR /
COPY --from=builder /app/backend/services/channel-gateway/channel-gateway /channel-gateway
ENV PORT=8090
EXPOSE 8090
ENTRYPOINT ["/channel-gateway"]
