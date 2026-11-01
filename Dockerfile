# syntax=docker/dockerfile:1

############################
# Build stage
############################
FROM golang:1.25-alpine AS builder

RUN apk add --no-cache git

# The application source is cloned during the build so this repository stays
# self-contained. Override with --build-arg if needed.
ARG APP_REPO=https://github.com/Innocent9712/much-to-do.git
ARG APP_REF=feature/backend-only

WORKDIR /src
RUN git clone --depth 1 --branch "${APP_REF}" "${APP_REPO}" repo

# The Go module lives in Server/MuchToDo
WORKDIR /src/repo/Server/MuchToDo
RUN go mod download

# main.go blank-imports the generated swagger "docs" package. If docs/ is not
# committed to the repo, generate it here so the build does not fail.
RUN if [ ! -d docs ]; then \
      go install github.com/swaggo/swag/cmd/swag@latest && \
      /go/bin/swag init -g ./cmd/api/main.go -o ./docs && \
      go mod tidy; \
    fi

RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/muchtodo ./cmd/api

############################
# Runtime stage
############################
FROM alpine:3.20

# CA certificates for outbound TLS; wget (busybox) is used by the healthcheck
RUN apk add --no-cache ca-certificates \
 && addgroup -S app \
 && adduser -S -G app -H -s /sbin/nologin app

WORKDIR /app
COPY --from=builder --chown=app:app /out/muchtodo /app/muchtodo

# Run as non-root
USER app

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD wget -qO- http://127.0.0.1:8080/health || exit 1

ENTRYPOINT ["/app/muchtodo"]
