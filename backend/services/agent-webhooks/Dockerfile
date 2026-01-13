FROM golang:1.24-alpine AS builder

# Keep repository-relative paths so go.mod `replace ../../libs/shared/config`
# resolves correctly during container builds.
WORKDIR /app/backend/services/agent-webhooks

COPY backend/services/agent-webhooks/go.mod backend/services/agent-webhooks/go.sum* ./
COPY backend/libs/shared/config/go.mod backend/libs/shared/config/go.sum* ../../libs/shared/config/
COPY backend/libs/agent-context/go.mod backend/libs/agent-context/go.sum* ../../libs/agent-context/
RUN go mod download

COPY backend/services/agent-webhooks/cmd ./cmd
COPY backend/libs/shared/config ../../libs/shared/config
COPY backend/libs/agent-context ../../libs/agent-context

RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o agent-webhooks ./cmd/agent-webhooks

FROM gcr.io/distroless/base-debian12
WORKDIR /
COPY --from=builder /app/backend/services/agent-webhooks/agent-webhooks /agent-webhooks
ENV PORT=8086
EXPOSE 8086
ENTRYPOINT ["/agent-webhooks"]

