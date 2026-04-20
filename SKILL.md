# Kafka Proxy Container — AI Skill Reference

## Overview
This container runs a Kafka proxy and an nginx-based Schema Registry reverse proxy.
It connects to Confluent Cloud and exposes plaintext endpoints locally, removing the need
for clients to handle TLS/SASL authentication directly.

## Services

| Service               | Internal Port | Protocol  | Description                                      |
|-----------------------|---------------|-----------|--------------------------------------------------|
| Kafka Proxy           | 9092          | Kafka TCP | Proxies to Confluent Cloud Kafka brokers          |
| Schema Registry Proxy | 8081          | HTTP      | Reverse-proxies Confluent Schema Registry (nginx) |
| Health / Metrics      | 8000          | HTTP      | Health check and Prometheus metrics               |

## Endpoints

- **Kafka bootstrap**: `localhost:9092` (plaintext, no auth needed)
- **Schema Registry**: `http://localhost:8081` (no auth needed, nginx injects credentials)
- **Health check**: `http://localhost:8000/health` → returns `OK`
- **Metrics**: `http://localhost:8000/metrics` → Prometheus format

## Installed CLI Tools

| Tool              | Path / Command        | Description                          |
|-------------------|-----------------------|--------------------------------------|
| kcat              | `kcat`                | Kafka CLI producer/consumer/metadata |
| kafka-topics.sh   | `kafka-topics.sh`     | Apache Kafka topic management        |
| kafka-console-producer.sh | `kafka-console-producer.sh` | Produce messages        |
| kafka-console-consumer.sh | `kafka-console-consumer.sh` | Consume messages        |
| kafka-consumer-groups.sh  | `kafka-consumer-groups.sh`  | Consumer group management |
| curl              | `curl`                | HTTP client                          |
| wget              | `wget`                | HTTP client                          |
| java              | `java`                | OpenJDK 17 JRE                       |

## Common Commands

### List topics
```bash
kcat -b localhost:9092 -L
# or
kafka-topics.sh --bootstrap-server localhost:9092 --list
```

### Produce a message
```bash
echo "hello" | kcat -b localhost:9092 -P -t my-topic
# or
echo "hello" | kafka-console-producer.sh --bootstrap-server localhost:9092 --topic my-topic
```

### Consume messages
```bash
kcat -b localhost:9092 -C -t my-topic -e
# or
kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic my-topic --from-beginning
```

### List consumer groups
```bash
kafka-consumer-groups.sh --bootstrap-server localhost:9092 --list
```

### Schema Registry — list subjects
```bash
curl -s http://localhost:8081/subjects
```

### Schema Registry — get schema by subject
```bash
curl -s http://localhost:8081/subjects/{subject}/versions/latest
```

### Health check
```bash
curl -s http://localhost:8000/health
```

## Environment Variables

| Variable                          | Required | Default       | Description                                |
|-----------------------------------|----------|---------------|--------------------------------------------|
| KAFKA_PROXY_BOOTSTRAP_SERVERS     | yes      |               | Upstream Kafka broker address              |
| KAFKA_PROXY_SASL_USERNAME         | yes      |               | SASL username for upstream Kafka           |
| KAFKA_PROXY_SASL_PASSWORD         | yes      |               | SASL password for upstream Kafka           |
| KAFKA_PROXY_DEFAULT_LISTENER_IP   | no       | 0.0.0.0       | IP to bind the proxy listener              |
| KAFKA_PROXY_TLS_ENABLE            | no       | true          | Enable TLS to upstream broker              |
| KAFKA_PROXY_SASL_ENABLE           | no       | true          | Enable SASL auth to upstream broker        |
| KAFKA_PROXY_SASL_METHOD           | no       | PLAIN         | SASL method (PLAIN, SCRAM-SHA-256, etc.)   |
| KAFKA_PROXY_LOG_LEVEL             | no       | info          | Log level (debug, info, warn, error)       |
| SCHEMA_REGISTRY_UPSTREAM          | no       |               | Schema Registry URL (enables nginx proxy)  |
| SCHEMA_REGISTRY_API_KEY           | no       |               | Schema Registry API key                    |
| SCHEMA_REGISTRY_API_SECRET        | no       |               | Schema Registry API secret                 |

## Docker Run

```bash
# With host networking (recommended — dynamic broker ports are accessible):
docker run -d --name kafka-proxy --network host --env-file .env kafka-proxy

# With port mapping (bootstrap only, dynamic broker ports won't work for some clients):
docker run -d --name kafka-proxy -p 9092:9092 -p 8000:8000 -p 8081:8081 --env-file .env kafka-proxy
```

## Retrieve This File
```bash
docker exec kafka-proxy-test cat /opt/kafka-proxy/CONTAINER_SKILL.md
```
