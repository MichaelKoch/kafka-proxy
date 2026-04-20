# Kafka Proxy — Copilot Instructions

## Project

This is a Go-based Kafka proxy (fork of grepplabs/kafka-proxy) that connects to Confluent Cloud
and exposes plaintext Kafka and Schema Registry endpoints locally.

- **Language**: Go 1.23, built with `-mod=vendor`
- **Docker image**: `ghcr.io/michaelkoch/kproxy:master`
- **CI**: GitHub Actions (`.github/workflows/build.yaml`, `.github/workflows/release.yaml`)

## Container Skill

The Docker container runs a Kafka proxy and an nginx-based Schema Registry reverse proxy.
Clients connect via plaintext — TLS/SASL authentication is handled by the proxy.

### Services

| Service               | Port | Protocol  | Description                                      |
|-----------------------|------|-----------|--------------------------------------------------|
| Kafka Proxy           | 9092 | Kafka TCP | Proxies to Confluent Cloud Kafka brokers          |
| Schema Registry Proxy | 8081 | HTTP      | Reverse-proxies Confluent Schema Registry (nginx) |
| Health / Metrics      | 8000 | HTTP      | Health check and Prometheus metrics               |

### Endpoints

- **Kafka bootstrap**: `localhost:9092` (plaintext, no auth needed)
- **Schema Registry**: `http://localhost:8081` (no auth needed, nginx injects credentials)
- **Health check**: `http://localhost:8000/health` → returns `OK`
- **Metrics**: `http://localhost:8000/metrics` → Prometheus format

### Installed CLI Tools

| Tool              | Description                          |
|-------------------|--------------------------------------|
| `kcat`            | Kafka CLI producer/consumer/metadata |
| `kafka-topics.sh` | Apache Kafka topic management        |
| `kafka-console-producer.sh` | Produce messages          |
| `kafka-console-consumer.sh` | Consume messages          |
| `kafka-consumer-groups.sh`  | Consumer group management |
| `curl` / `wget`  | HTTP clients                         |
| `java`            | OpenJDK 17 JRE                       |

### Common Commands

```bash
# List topics
kcat -b localhost:9092 -L
kafka-topics.sh --bootstrap-server localhost:9092 --list

# Produce a message
echo "hello" | kcat -b localhost:9092 -P -t my-topic

# Consume messages
kcat -b localhost:9092 -C -t my-topic -e

# List consumer groups
kafka-consumer-groups.sh --bootstrap-server localhost:9092 --list

# Schema Registry
curl -s http://localhost:8081/subjects
curl -s http://localhost:8081/subjects/{subject}/versions/latest

# Health check
curl -s http://localhost:8000/health
```

### Docker Run

```bash
# Host networking (recommended):
docker run -d --name kafka-proxy --network host --env-file .env ghcr.io/michaelkoch/kproxy:master

# Port mapping:
docker run -d --name kafka-proxy -p 9092:9092 -p 8000:8000 -p 8081:8081 --env-file .env ghcr.io/michaelkoch/kproxy:master
```

### Environment Variables

| Variable                          | Required | Description                                |
|-----------------------------------|----------|--------------------------------------------|
| KAFKA_PROXY_BOOTSTRAP_SERVERS     | yes      | Upstream Kafka broker address              |
| KAFKA_PROXY_SASL_USERNAME         | yes      | SASL username for upstream Kafka           |
| KAFKA_PROXY_SASL_PASSWORD         | yes      | SASL password for upstream Kafka           |
| SCHEMA_REGISTRY_UPSTREAM          | no       | Schema Registry URL (enables nginx proxy)  |
| SCHEMA_REGISTRY_API_KEY           | no       | Schema Registry API key                    |
| SCHEMA_REGISTRY_API_SECRET        | no       | Schema Registry API secret                 |
