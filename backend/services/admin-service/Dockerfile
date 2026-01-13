FROM golang:1.24-alpine AS builder

# Keep repository-relative paths so go.mod `replace ../../libs/shared/config`
# resolves correctly during container builds.
WORKDIR /app/backend/services/admin-service

COPY backend/services/admin-service/go.mod backend/services/admin-service/go.sum* ./
COPY backend/libs/shared/config/go.mod backend/libs/shared/config/go.sum* ../../libs/shared/config/
RUN go mod download

COPY backend/services/admin-service/cmd ./cmd
COPY backend/services/admin-service/internal ./internal
COPY backend/libs/shared/config ../../libs/shared/config

RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o admin-service ./cmd/admin-service

FROM gcr.io/distroless/base-debian12
WORKDIR /
COPY --from=builder /app/backend/services/admin-service/admin-service /admin-service
ENV PORT=8085
EXPOSE 8085
ENTRYPOINT ["/admin-service"]
