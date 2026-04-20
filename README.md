## kafka-proxy

[![Build Status](https://github.com/grepplabs/kafka-proxy/actions/workflows/build.yaml/badge.svg)](https://github.com/grepplabs/kafka-proxy/actions/workflows/build.yaml)
[![Docker Hub](https://img.shields.io/badge/docker-latest-blue.svg)](https://hub.docker.com/r/grepplabs/kafka-proxy)
[![Docker Pulls](https://img.shields.io/docker/pulls/grepplabs/kafka-proxy)](https://hub.docker.com/r/grepplabs/kafka-proxy)

The Kafka Proxy is based on idea of [Cloud SQL Proxy](https://github.com/GoogleCloudPlatform/cloudsql-proxy). 
It allows a service to connect to Kafka brokers without having to deal with SASL/PLAIN authentication and SSL certificates.  

It works by opening tcp sockets on the local machine and proxying connections to the associated Kafka brokers
when the sockets are used. The host and port in [Metadata](http://kafka.apache.org/protocol.html#The_Messages_Metadata)
and [FindCoordinator](http://kafka.apache.org/protocol.html#The_Messages_FindCoordinator)
responses received from the brokers are replaced by local counterparts.
For discovered brokers (not configured as the boostrap servers), local listeners are started on random ports.
The dynamic local listeners feature can be disabled and an additional list of external server mappings can be provided.

The Proxy can terminate TLS traffic and authenticate users using SASL/PLAIN. The credentials verification method
is configurable and uses golang plugin system over RPC.

The proxies can also authenticate each other using a pluggable method which is transparent to other Kafka servers and clients.
Currently, the Google ID Token for service accounts is implemented i.e. proxy client requests and sends service account JWT and proxy server receives and validates it against Google JWKS.

Kafka API calls can be restricted to prevent some operations e.g. topic deletion or produce requests.


See:
* [Kafka Proxy with Amazon MSK](https://gist.github.com/everesio/262e11c6e5cebf56f1d5111c8cd7da3f)
* [A Guide To The Kafka Protocol](https://cwiki.apache.org/confluence/display/KAFKA/A+Guide+To+The+Kafka+Protocol)
* [Kafka protocol guide](http://kafka.apache.org/protocol.html)


### Supported Kafka versions
Following table provides overview of supported Kafka versions (specified one and all previous Kafka versions).
As not every Kafka release adds new messages/versions which are relevant to the Kafka proxy, newer Kafka versions can also work.


| Kafka proxy version | Kafka version |
|---------------------|---------------|
|                     | from 0.11.0   |
| 0.2.9               | to 2.8.0      |
| 0.3.1               | to 3.4.0      |
| 0.3.11              | to 3.7.0      |
| 0.3.12              | to 3.9.0      |
| 0.4.2               | to 4.0.0      |

### Install binary release

1. Download the latest release

   Linux

        curl -Ls https://github.com/grepplabs/kafka-proxy/releases/download/v0.4.3/kafka-proxy-v0.4.3-linux-amd64.tar.gz | tar xz

   macOS

        curl -Ls https://github.com/grepplabs/kafka-proxy/releases/download/v0.4.3/kafka-proxy-v0.4.3-darwin-amd64.tar.gz | tar xz

2. Move the binary in to your PATH.

    ```
    sudo mv ./kafka-proxy /usr/local/bin/kafka-proxy
    ```

### Building

    make clean build

### Docker images

Docker images are available on [Docker Hub](https://hub.docker.com/r/grepplabs/kafka-proxy/tags).

#### Running with an `.env` file

The Docker image is designed to be configured entirely via environment variables.
The entrypoint script (`docker-entrypoint.sh`) reads environment variables and translates them
into the appropriate `kafka-proxy server` CLI flags. If Schema Registry variables are set,
an nginx reverse proxy is started automatically on port 8081.

**1. Create a `.env` file** with the required Kafka connection settings:

```bash
# Required
KAFKA_PROXY_BOOTSTRAP_SERVERS=pkc-xxxxx.eu-central-1.aws.confluent.cloud:9092
KAFKA_PROXY_SASL_USERNAME=<api-key>
KAFKA_PROXY_SASL_PASSWORD=<api-secret>
```

**2. Start the container** using `--env-file`:

```bash
# Host networking (recommended — simplest setup):
docker run -d --name kafka-proxy --network host --env-file .env ghcr.io/michaelkoch/kproxy:master

# Or with explicit port mapping:
docker run -d --name kafka-proxy -p 9092:9092 -p 8000:8000 -p 8081:8081 --env-file .env ghcr.io/michaelkoch/kproxy:master
```

**3. Verify** the proxy is running:

```bash
curl -s http://localhost:8000/health    # → OK
kcat -b localhost:9092 -L               # list topics
```

#### Environment variables reference

| Variable | Required | Default | Description |
|---|---|---|---|
| `KAFKA_PROXY_BOOTSTRAP_SERVERS` | **yes** | — | Upstream Kafka broker address (`host:port`) |
| `KAFKA_PROXY_SASL_USERNAME` | **yes** | — | SASL username (API key) for upstream Kafka |
| `KAFKA_PROXY_SASL_PASSWORD` | **yes** | — | SASL password (API secret) for upstream Kafka |
| `KAFKA_PROXY_SASL_ENABLE` | no | `true` | Set to `false` to disable SASL authentication |
| `KAFKA_PROXY_SASL_METHOD` | no | `PLAIN` | SASL method (`PLAIN`, `SCRAM-SHA-256`, `SCRAM-SHA-512`, etc.) |
| `KAFKA_PROXY_TLS_ENABLE` | no | — | Set to `true` to enable TLS to upstream broker |
| `KAFKA_PROXY_TLS_INSECURE_SKIP_VERIFY` | no | — | Set to `true` to skip TLS certificate verification |
| `KAFKA_PROXY_LISTENER_TLS_ENABLE` | no | — | Set to `true` to enable TLS on the proxy listener |
| `KAFKA_PROXY_LOG_LEVEL` | no | `info` | Log level (`trace`, `debug`, `info`, `warning`, `error`) |
| `KAFKA_PROXY_LOG_FORMAT` | no | `text` | Log format (`text` or `json`) |
| `KAFKA_PROXY_HTTP_LISTEN_ADDRESS` | no | `0.0.0.0:9080` | Health/metrics listen address |
| `KAFKA_PROXY_HTTP_HEALTH_PATH` | no | `/health` | Health endpoint path |
| `KAFKA_PROXY_HTTP_METRICS_PATH` | no | `/metrics` | Prometheus metrics endpoint path |
| `SCHEMA_REGISTRY_UPSTREAM` | no | — | Schema Registry URL (enables nginx proxy on :8081) |
| `SCHEMA_REGISTRY_API_KEY` | no | — | Schema Registry API key |
| `SCHEMA_REGISTRY_API_SECRET` | no | — | Schema Registry API secret |

#### `.env` file example (full)

```bash
# Kafka connection (required)
KAFKA_PROXY_BOOTSTRAP_SERVERS=pkc-xxxxx.eu-central-1.aws.confluent.cloud:9092
KAFKA_PROXY_SASL_USERNAME=ABCDEFGHIJKLMNOP
KAFKA_PROXY_SASL_PASSWORD=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

# Schema Registry (optional — enables nginx reverse proxy on :8081)
SCHEMA_REGISTRY_UPSTREAM=https://psrc-xxxxx.eu-central-1.aws.confluent.cloud
SCHEMA_REGISTRY_API_KEY=QRSTUVWXYZ123456
SCHEMA_REGISTRY_API_SECRET=yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy

# Optional tuning
KAFKA_PROXY_LOG_LEVEL=info
```

#### Exposed services

| Service | Port | Protocol | Description |
|---|---|---|---|
| Kafka Proxy | 9092 | Kafka TCP | Plaintext Kafka — TLS/SASL handled by proxy |
| Schema Registry Proxy | 8081 | HTTP | Reverse-proxies Confluent Schema Registry (nginx) |
| Health / Metrics | 8000 | HTTP | `/health` and `/metrics` endpoints |

Clients connect via plaintext — no SASL credentials or TLS configuration needed on the client side.

#### Building a local Docker image

```bash
docker build --build-arg VERSION=$(git describe --tags --always --dirty) -t local/kafka-proxy .
docker run --rm --name kafka-proxy --network host --env-file .env local/kafka-proxy
```

#### Container skill file (capabilities)

The container ships with `/opt/kafka-proxy/SKILL.md`, which documents exposed endpoints, environment variables and common commands.

Fetch capabilities from a running container:

```bash
docker exec kafka-proxy cat /opt/kafka-proxy/SKILL.md
```

#### Included tools in the Docker image

The image includes the following tools:
- `kcat`
- `kafka-topics.sh`
- `kafka-console-producer.sh`
- `kafka-console-consumer.sh`
- `kafka-consumer-groups.sh`
- `curl`
- `wget`
- `java` (OpenJDK 17 runtime)

### Embedded third-party source code 

* [Cloud SQL Proxy](https://github.com/GoogleCloudPlatform/cloudsql-proxy)
* [Sarama](https://github.com/Shopify/sarama)
