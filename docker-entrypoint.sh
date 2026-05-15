#!/bin/sh
set -e

PROXY_BIN="/opt/kafka-proxy/bin/kafka-proxy"

render_schema_registry_nginx_config() {
    envsubst '${SCHEMA_REGISTRY_UPSTREAM} ${SCHEMA_REGISTRY_HOST} ${SCHEMA_REGISTRY_AUTH_HEADER} ${SCHEMA_REGISTRY_LOGICAL_CLUSTER} ${SCHEMA_REGISTRY_IDENTITY_POOL_ID}' \
        < /etc/nginx/templates/schema-registry.conf.template \
        > /etc/nginx/http.d/schema-registry.conf
}

refresh_schema_registry_oidc_token() {
    scope="${SCHEMA_REGISTRY_OIDC_SCOPES:-$KAFKA_PROXY_SASL_OIDC_SCOPES}"
    token_response=$(curl -sS -X POST "$KAFKA_PROXY_SASL_OIDC_TOKEN_URL" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        --data-urlencode "grant_type=client_credentials" \
        --data-urlencode "client_id=$KAFKA_PROXY_SASL_OIDC_CLIENT_ID" \
        --data-urlencode "client_secret=$KAFKA_PROXY_SASL_OIDC_CLIENT_SECRET" \
        --data-urlencode "scope=$scope")

    access_token=$(echo "$token_response" | sed -n 's/.*"access_token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    if [ -z "$access_token" ]; then
        echo "ERROR: failed to acquire OIDC access token for Schema Registry"
        echo "$token_response"
        return 1
    fi

    expires_in=$(echo "$token_response" | sed -n 's/.*"expires_in"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p')
    if [ -z "$expires_in" ]; then
        expires_in=3600
    fi

    SCHEMA_REGISTRY_OIDC_REFRESH_SECONDS=$((expires_in / 2))
    if [ "$SCHEMA_REGISTRY_OIDC_REFRESH_SECONDS" -lt 30 ]; then
        SCHEMA_REGISTRY_OIDC_REFRESH_SECONDS=30
    fi

    export SCHEMA_REGISTRY_AUTH_HEADER="Bearer $access_token"
    export SCHEMA_REGISTRY_OIDC_REFRESH_SECONDS
    return 0
}

start_schema_registry_oidc_refresh_loop() {
    while true; do
        sleep "$SCHEMA_REGISTRY_OIDC_REFRESH_SECONDS"

        if refresh_schema_registry_oidc_token; then
            render_schema_registry_nginx_config
            if nginx -s reload; then
                echo "Refreshed Schema Registry OIDC token and reloaded nginx"
            else
                echo "WARNING: failed to reload nginx after Schema Registry token refresh"
            fi
        else
            echo "WARNING: Schema Registry OIDC token refresh failed; retrying in 30s"
            SCHEMA_REGISTRY_OIDC_REFRESH_SECONDS=30
        fi
    done
}

# --- Schema Registry nginx proxy ---
if [ -n "$SCHEMA_REGISTRY_UPSTREAM" ]; then
    # Extract host from URL
    export SCHEMA_REGISTRY_HOST=$(echo "$SCHEMA_REGISTRY_UPSTREAM" | sed 's|https\?://||')
    export SCHEMA_REGISTRY_LOGICAL_CLUSTER="${SCHEMA_REGISTRY_LOGICAL_CLUSTER:-$KAFKA_PROXY_SASL_OAUTH_LOGICAL_CLUSTER}"
    export SCHEMA_REGISTRY_IDENTITY_POOL_ID="${SCHEMA_REGISTRY_IDENTITY_POOL_ID:-$KAFKA_PROXY_SASL_OAUTH_IDENTITY_POOL_ID}"

    if [ -n "$KAFKA_PROXY_SASL_OIDC_CLIENT_ID" ] && [ -n "$KAFKA_PROXY_SASL_OIDC_CLIENT_SECRET" ] && [ -n "$KAFKA_PROXY_SASL_OIDC_TOKEN_URL" ]; then
        if ! refresh_schema_registry_oidc_token; then
            exit 1
        fi
        echo "Using OIDC bearer token for Schema Registry proxy authentication"
    elif [ -n "$SCHEMA_REGISTRY_API_KEY" ] && [ -n "$SCHEMA_REGISTRY_API_SECRET" ]; then
        schema_registry_basic_auth=$(printf '%s:%s' "$SCHEMA_REGISTRY_API_KEY" "$SCHEMA_REGISTRY_API_SECRET" | base64 | tr -d '\n')
        export SCHEMA_REGISTRY_AUTH_HEADER="Basic $schema_registry_basic_auth"
        echo "Using Basic auth for Schema Registry proxy authentication"
    else
        echo "ERROR: Schema Registry auth not configured. Set OIDC env vars or SCHEMA_REGISTRY_API_KEY/SCHEMA_REGISTRY_API_SECRET"
        exit 1
    fi

    # Render nginx config from template (only substitute our vars, not nginx vars)
    render_schema_registry_nginx_config

    echo "Starting nginx Schema Registry proxy -> $SCHEMA_REGISTRY_UPSTREAM on :8081"
    nginx

    if [ -n "$KAFKA_PROXY_SASL_OIDC_CLIENT_ID" ] && [ -n "$KAFKA_PROXY_SASL_OIDC_CLIENT_SECRET" ] && [ -n "$KAFKA_PROXY_SASL_OIDC_TOKEN_URL" ]; then
        start_schema_registry_oidc_refresh_loop &
    fi
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
[ -n "$KAFKA_PROXY_SASL_OAUTH_LOGICAL_CLUSTER" ] && ARGS="$ARGS --sasl-oauth-logical-cluster=${KAFKA_PROXY_SASL_OAUTH_LOGICAL_CLUSTER}"
[ -n "$KAFKA_PROXY_SASL_OAUTH_IDENTITY_POOL_ID" ] && ARGS="$ARGS --sasl-oauth-identity-pool-id=${KAFKA_PROXY_SASL_OAUTH_IDENTITY_POOL_ID}"

# SASL plugin
[ "$KAFKA_PROXY_SASL_PLUGIN_ENABLE" = "true" ] && ARGS="$ARGS --sasl-plugin-enable"
[ -n "$KAFKA_PROXY_SASL_PLUGIN_COMMAND" ] && ARGS="$ARGS --sasl-plugin-command=${KAFKA_PROXY_SASL_PLUGIN_COMMAND}"
[ -n "$KAFKA_PROXY_SASL_PLUGIN_MECHANISM" ] && ARGS="$ARGS --sasl-plugin-mechanism=${KAFKA_PROXY_SASL_PLUGIN_MECHANISM}"
[ -n "$KAFKA_PROXY_SASL_PLUGIN_LOG_LEVEL" ] && ARGS="$ARGS --sasl-plugin-log-level=${KAFKA_PROXY_SASL_PLUGIN_LOG_LEVEL}"
[ -n "$KAFKA_PROXY_SASL_PLUGIN_TIMEOUT" ] && ARGS="$ARGS --sasl-plugin-timeout=${KAFKA_PROXY_SASL_PLUGIN_TIMEOUT}"

# OIDC token-provider plugin params (no credentials file required)
[ -n "$KAFKA_PROXY_SASL_OIDC_GRANT_TYPE" ] && ARGS="$ARGS --sasl-plugin-param=--grant-type=${KAFKA_PROXY_SASL_OIDC_GRANT_TYPE}"
[ -n "$KAFKA_PROXY_SASL_OIDC_CLIENT_ID" ] && ARGS="$ARGS --sasl-plugin-param=--client-id=${KAFKA_PROXY_SASL_OIDC_CLIENT_ID}"
[ -n "$KAFKA_PROXY_SASL_OIDC_CLIENT_SECRET" ] && ARGS="$ARGS --sasl-plugin-param=--client-secret=${KAFKA_PROXY_SASL_OIDC_CLIENT_SECRET}"
[ -n "$KAFKA_PROXY_SASL_OIDC_TOKEN_URL" ] && ARGS="$ARGS --sasl-plugin-param=--token-url=${KAFKA_PROXY_SASL_OIDC_TOKEN_URL}"
[ -n "$KAFKA_PROXY_SASL_OIDC_SCOPES" ] && ARGS="$ARGS --sasl-plugin-param=--scopes=${KAFKA_PROXY_SASL_OIDC_SCOPES}"
[ -n "$KAFKA_PROXY_SASL_OIDC_USERNAME" ] && ARGS="$ARGS --sasl-plugin-param=--username=${KAFKA_PROXY_SASL_OIDC_USERNAME}"
[ -n "$KAFKA_PROXY_SASL_OIDC_PASSWORD" ] && ARGS="$ARGS --sasl-plugin-param=--password=${KAFKA_PROXY_SASL_OIDC_PASSWORD}"

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
