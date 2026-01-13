FROM golang:1.24-alpine AS builder
WORKDIR /app/backend/services/agent-tools

# Keep repository-relative paths so go.mod `replace ../../libs/shared/config`
# resolves correctly during container builds.
COPY backend/services/agent-tools/go.mod backend/services/agent-tools/go.sum* ./
COPY backend/libs/shared/config/go.mod backend/libs/shared/config/go.sum* ../../libs/shared/config/
RUN go mod download

COPY backend/services/agent-tools/cmd ./cmd
COPY backend/libs/shared/config ../../libs/shared/config

RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o agent-tools ./cmd/agent-tools

FROM gcr.io/distroless/base-debian12
WORKDIR /
COPY --from=builder /app/backend/services/agent-tools/agent-tools /agent-tools
ENV PORT=8087
EXPOSE 8087
ENTRYPOINT ["/agent-tools"]


