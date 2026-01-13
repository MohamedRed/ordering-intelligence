FROM golang:1.24-alpine AS builder
WORKDIR /app/backend/services/dispatch-service

# Keep repository-relative paths so go.mod `replace ../../libs/shared/config`
# resolves correctly during container builds.
COPY backend/services/dispatch-service/go.mod backend/services/dispatch-service/go.sum* ./
COPY backend/libs/shared/config/go.mod backend/libs/shared/config/go.sum* ../../libs/shared/config/
RUN go mod download

COPY backend/services/dispatch-service/cmd ./cmd
COPY backend/libs/shared/config ../../libs/shared/config

RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o dispatch-service ./cmd/dispatch-service

FROM gcr.io/distroless/base-debian12
WORKDIR /
COPY --from=builder /app/backend/services/dispatch-service/dispatch-service /dispatch-service
EXPOSE 8080
ENTRYPOINT ["/dispatch-service"]

