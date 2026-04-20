#!/bin/bash

set -e

# Load environment variables from .env file
if [ -f .env ]; then
    export $(cat .env | grep -v '#' | grep -v '^$' | xargs)
    echo "✓ Loaded configuration from .env"
else
    echo "✗ .env file not found. Please create it first."
    exit 1
fi

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BINARY="${SCRIPT_DIR}/build/kafka-proxy"

# Check if binary exists
if [ ! -f "$BINARY" ]; then
    echo "✗ Binary not found at $BINARY"
    echo "Please build the project first: make build"
    exit 1
fi

# Build command arguments from environment variables
ARGS=()

# Proxy configuration
[ -n "$KAFKA_PROXY_BOOTSTRAP_SERVERS" ] && ARGS+=("--bootstrap-server-mapping=${KAFKA_PROXY_BOOTSTRAP_SERVERS},127.0.0.1:8080")

# HTTP configuration
[ -n "$KAFKA_PROXY_HTTP_LISTEN_ADDRESS" ] && ARGS+=("--http-listen-address=${KAFKA_PROXY_HTTP_LISTEN_ADDRESS}")
[ -n "$KAFKA_PROXY_HTTP_METRICS_PATH" ] && ARGS+=("--http-metrics-path=${KAFKA_PROXY_HTTP_METRICS_PATH}")
[ -n "$KAFKA_PROXY_HTTP_HEALTH_PATH" ] && ARGS+=("--http-health-path=${KAFKA_PROXY_HTTP_HEALTH_PATH}")

# Logging configuration
[ -n "$KAFKA_PROXY_LOG_FORMAT" ] && ARGS+=("--log-format=${KAFKA_PROXY_LOG_FORMAT}")
[ -n "$KAFKA_PROXY_LOG_LEVEL" ] && ARGS+=("--log-level=${KAFKA_PROXY_LOG_LEVEL}")

# TLS configuration
[ "$KAFKA_PROXY_TLS_ENABLE" = "true" ] && ARGS+=("--tls-enable")
[ "$KAFKA_PROXY_TLS_INSECURE_SKIP_VERIFY" = "true" ] && ARGS+=("--tls-insecure-skip-verify")
[ "$KAFKA_PROXY_LISTENER_TLS_ENABLE" = "true" ] && ARGS+=("--proxy-listener-tls-enable")
[ -n "$KAFKA_PROXY_TLS_LISTENER_CERT_FILE" ] && ARGS+=("--proxy-listener-cert-file=${KAFKA_PROXY_TLS_LISTENER_CERT_FILE}")
[ -n "$KAFKA_PROXY_TLS_LISTENER_KEY_FILE" ] && ARGS+=("--proxy-listener-key-file=${KAFKA_PROXY_TLS_LISTENER_KEY_FILE}")

# SASL configuration
[ "$KAFKA_PROXY_SASL_ENABLE" != "false" ] && ARGS+=("--sasl-enable")
[ -n "$KAFKA_PROXY_SASL_METHOD" ] && ARGS+=("--sasl-method=${KAFKA_PROXY_SASL_METHOD}")
[ -n "$KAFKA_PROXY_SASL_USERNAME" ] && ARGS+=("--sasl-username=${KAFKA_PROXY_SASL_USERNAME}")
[ -n "$KAFKA_PROXY_SASL_PASSWORD" ] && ARGS+=("--sasl-password=${KAFKA_PROXY_SASL_PASSWORD}")

# Debug configuration
[ "$KAFKA_PROXY_DEBUG_ENABLED" = "true" ] && ARGS+=("--debug-enable")
[ -n "$KAFKA_PROXY_DEBUG_LISTEN_ADDRESS" ] && ARGS+=("--debug-listen-address=${KAFKA_PROXY_DEBUG_LISTEN_ADDRESS}")

# Print configuration
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Starting Kafka Proxy"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Binary: $BINARY"
echo "Bootstrap Servers: ${KAFKA_PROXY_BOOTSTRAP_SERVERS}"
echo "Listener Address: ${KAFKA_PROXY_LISTENER_ADDRESS}"
echo "HTTP Listen Address: ${KAFKA_PROXY_HTTP_LISTEN_ADDRESS}"
echo "Log Level: ${KAFKA_PROXY_LOG_LEVEL}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Start the proxy
exec "$BINARY" server "${ARGS[@]}"
