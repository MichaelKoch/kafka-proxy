#!/bin/sh
set -e

PROXY_BIN="/opt/kafka-proxy/bin/kafka-proxy"

# --- Schema Registry nginx proxy ---
if [ -n "$SCHEMA_REGISTRY_UPSTREAM" ] && [ -n "$SCHEMA_REGISTRY_API_KEY" ] && [ -n "$SCHEMA_REGISTRY_API_SECRET" ]; then
    # Compute base64 auth and extract host from URL
    export SCHEMA_REGISTRY_BASIC_AUTH=$(printf '%s:%s' "$SCHEMA_REGISTRY_API_KEY" "$SCHEMA_REGISTRY_API_SECRET" | base64 | tr -d '\n')
    export SCHEMA_REGISTRY_HOST=$(echo "$SCHEMA_REGISTRY_UPSTREAM" | sed 's|https\?://||')

    # Render nginx config from template (only substitute our vars, not nginx vars)
    envsubst '${SCHEMA_REGISTRY_UPSTREAM} ${SCHEMA_REGISTRY_HOST} ${SCHEMA_REGISTRY_BASIC_AUTH}' \
        < /etc/nginx/templates/schema-registry.conf.template \
        > /etc/nginx/http.d/schema-registry.conf

    echo "Starting nginx Schema Registry proxy -> $SCHEMA_REGISTRY_UPSTREAM on :8081"
    nginx
fi

# --- Kafka Proxy ---
if [ -z "$KAFKA_PROXY_BOOTSTRAP_SERVERS" ]; then
    echo "ERROR: KAFKA_PROXY_BOOTSTRAP_SERVERS is required"
    exit 1
fi

ARGS="server"
LISTENER_PORT="${KAFKA_PROXY_LISTENER_PORT:-9092}"
ARGS="$ARGS --bootstrap-server-mapping=${KAFKA_PROXY_BOOTSTRAP_SERVERS},${KAFKA_PROXY_DEFAULT_LISTENER_IP}:${LISTENER_PORT}"

# HTTP
[ -n "$KAFKA_PROXY_HTTP_LISTEN_ADDRESS" ] && ARGS="$ARGS --http-listen-address=${KAFKA_PROXY_HTTP_LISTEN_ADDRESS}"
[ -n "$KAFKA_PROXY_HTTP_METRICS_PATH" ]   && ARGS="$ARGS --http-metrics-path=${KAFKA_PROXY_HTTP_METRICS_PATH}"
[ -n "$KAFKA_PROXY_HTTP_HEALTH_PATH" ]    && ARGS="$ARGS --http-health-path=${KAFKA_PROXY_HTTP_HEALTH_PATH}"

# Logging
[ -n "$KAFKA_PROXY_LOG_FORMAT" ] && ARGS="$ARGS --log-format=${KAFKA_PROXY_LOG_FORMAT}"
[ -n "$KAFKA_PROXY_LOG_LEVEL" ]  && ARGS="$ARGS --log-level=${KAFKA_PROXY_LOG_LEVEL}"

# TLS to upstream broker
[ "$KAFKA_PROXY_TLS_ENABLE" = "true" ]                && ARGS="$ARGS --tls-enable"
[ "$KAFKA_PROXY_TLS_INSECURE_SKIP_VERIFY" = "true" ]  && ARGS="$ARGS --tls-insecure-skip-verify"

# Listener TLS
[ "$KAFKA_PROXY_LISTENER_TLS_ENABLE" = "true" ] && ARGS="$ARGS --proxy-listener-tls-enable"

# SASL
[ "$KAFKA_PROXY_SASL_ENABLE" = "true" ] && ARGS="$ARGS --sasl-enable"
[ -n "$KAFKA_PROXY_SASL_METHOD" ]       && ARGS="$ARGS --sasl-method=${KAFKA_PROXY_SASL_METHOD}"
[ -n "$KAFKA_PROXY_SASL_USERNAME" ]     && ARGS="$ARGS --sasl-username=${KAFKA_PROXY_SASL_USERNAME}"
[ -n "$KAFKA_PROXY_SASL_PASSWORD" ]     && ARGS="$ARGS --sasl-password=${KAFKA_PROXY_SASL_PASSWORD}"

# Dynamic listener ports
[ -n "$KAFKA_PROXY_DYNAMIC_SEQUENTIAL_MIN_PORT" ] && ARGS="$ARGS --dynamic-sequential-min-port=${KAFKA_PROXY_DYNAMIC_SEQUENTIAL_MIN_PORT}"
[ -n "$KAFKA_PROXY_DYNAMIC_SEQUENTIAL_MAX_PORTS" ] && ARGS="$ARGS --dynamic-sequential-max-ports=${KAFKA_PROXY_DYNAMIC_SEQUENTIAL_MAX_PORTS}"

# Dial address mapping (redirect broker addresses, e.g. for K8s)
if [ -n "$KAFKA_PROXY_DIAL_ADDRESS_MAPPING" ]; then
    for mapping in $KAFKA_PROXY_DIAL_ADDRESS_MAPPING; do
        ARGS="$ARGS --dial-address-mapping=${mapping}"
    done
fi

echo "Starting kafka-proxy -> ${KAFKA_PROXY_BOOTSTRAP_SERVERS}"
exec $PROXY_BIN $ARGS
