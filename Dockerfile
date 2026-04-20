FROM golang:1.23-alpine3.21 AS builder

RUN apk add --no-cache alpine-sdk ca-certificates

ARG VERSION

ENV CGO_ENABLED=0 \
    GO111MODULE=on \
    LDFLAGS="-X github.com/grepplabs/kafka-proxy/config.Version=${VERSION} -w -s"

WORKDIR /go/src/github.com/grepplabs/kafka-proxy
COPY . .

RUN mkdir -p build && \
    go build -mod=vendor -o build/kafka-proxy -ldflags "${LDFLAGS}" .

FROM alpine:3.21

RUN apk add --no-cache ca-certificates libcap nginx gettext \
    curl wget openjdk17-jre-headless bash kcat

# Download Kafka CLI tools
ENV KAFKA_VERSION=4.0.2 \
    SCALA_VERSION=2.13
RUN wget -q "https://downloads.apache.org/kafka/${KAFKA_VERSION}/kafka_${SCALA_VERSION}-${KAFKA_VERSION}.tgz" -O /tmp/kafka.tgz && \
    tar -xzf /tmp/kafka.tgz -C /opt && \
    mv /opt/kafka_${SCALA_VERSION}-${KAFKA_VERSION} /opt/kafka && \
    rm /tmp/kafka.tgz
ENV PATH="/opt/kafka/bin:${PATH}"

COPY --from=builder /go/src/github.com/grepplabs/kafka-proxy/build /opt/kafka-proxy/bin
RUN setcap 'cap_net_bind_service=+ep' /opt/kafka-proxy/bin/kafka-proxy

# Nginx Schema Registry proxy template
COPY nginx-schema-registry.conf.template /etc/nginx/templates/schema-registry.conf.template
COPY docker-entrypoint.sh /opt/kafka-proxy/bin/docker-entrypoint.sh
COPY SKILL.md /opt/kafka-proxy/SKILL.md
RUN chmod +x /opt/kafka-proxy/bin/docker-entrypoint.sh && \
    mkdir -p /run/nginx && \
    rm -f /etc/nginx/http.d/default.conf

# Environment variable defaults (secrets are passed at runtime via --env-file)
ENV KAFKA_PROXY_BOOTSTRAP_SERVERS="" \
    KAFKA_PROXY_DEFAULT_LISTENER_IP="0.0.0.0" \
    KAFKA_PROXY_HTTP_LISTEN_ADDRESS="0.0.0.0:8000" \
    KAFKA_PROXY_HTTP_METRICS_PATH="/metrics" \
    KAFKA_PROXY_HTTP_HEALTH_PATH="/health" \
    KAFKA_PROXY_LOG_FORMAT="text" \
    KAFKA_PROXY_LOG_LEVEL="info" \
    KAFKA_PROXY_TLS_ENABLE="true" \
    KAFKA_PROXY_TLS_INSECURE_SKIP_VERIFY="true" \
    KAFKA_PROXY_SASL_ENABLE="true" \
    KAFKA_PROXY_SASL_METHOD="PLAIN" \
    KAFKA_PROXY_LISTENER_TLS_ENABLE="false" \
    SCHEMA_REGISTRY_UPSTREAM=""

EXPOSE 9092 8000 8081

ENTRYPOINT ["/opt/kafka-proxy/bin/docker-entrypoint.sh"]
