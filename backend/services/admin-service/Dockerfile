FROM golang:1.22-alpine AS builder
WORKDIR /app
COPY go.mod go.sum* ./
RUN go mod download
COPY cmd ./cmd
COPY internal ./internal
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o admin-service ./cmd/admin-service

FROM gcr.io/distroless/base-debian12
WORKDIR /
COPY --from=builder /app/admin-service /admin-service
ENV PORT=8085
EXPOSE 8085
ENTRYPOINT ["/admin-service"]
