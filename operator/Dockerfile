FROM golang:1.21-alpine AS builder

WORKDIR /app

# Copy go mod files
COPY go.mod ./

# Download dependencies (go.sum will be generated if missing)
RUN go mod tidy

# Copy source and build
COPY main.go .
RUN CGO_ENABLED=0 GOOS=linux go build -o operator .

# Minimal final image
FROM alpine:3.19

RUN apk --no-cache add ca-certificates

WORKDIR /app

COPY --from=builder /app/operator .

EXPOSE 8080

CMD ["./operator"]