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


### Docker images

Docker images are available on [Docker Hub](https://hub.docker.com/r/grepplabs/kafka-proxy/tags).

#### Running with an `.env` file

The Docker image is designed to be configured entirely via environment variables.
The entrypoint script (`docker-entrypoint.sh`) reads environment variables and translates them
into the appropriate `kafka-proxy server` CLI flags. If Schema Registry variables are set,
an nginx reverse proxy is started automatically on port 8081.
If Blob Storage variables are set, an nginx reverse proxy is also started on port 8082
(or `BLOB_STORAGE_LISTEN_PORT` when overridden).

When Schema Registry uses OIDC client credentials, the container also refreshes the bearer token
automatically and reloads nginx in place. Refresh is scheduled at roughly half of the token
`expires_in` value (minimum 30 seconds between refresh attempts).

**1. Create a `.env` file** with the required Kafka connection settings.

For Confluent Cloud API key/secret (SASL/PLAIN):

```bash
# Required
KAFKA_PROXY_BOOTSTRAP_SERVERS=pkc-xxxxx.eu-central-1.aws.confluent.cloud:9092
KAFKA_PROXY_SASL_USERNAME=<api-key>
KAFKA_PROXY_SASL_PASSWORD=<api-secret>
```

For OIDC/OAUTHBEARER (for example Entra ID, no credentials file required):

```bash
KAFKA_PROXY_BOOTSTRAP_SERVERS=pkc-xxxxx.eu-central-1.aws.confluent.cloud:9092
KAFKA_PROXY_SASL_ENABLE=true
KAFKA_PROXY_SASL_PLUGIN_ENABLE=true
KAFKA_PROXY_SASL_PLUGIN_COMMAND=/opt/kafka-proxy/bin/oidc-provider
KAFKA_PROXY_SASL_PLUGIN_MECHANISM=OAUTHBEARER
KAFKA_PROXY_SASL_OIDC_GRANT_TYPE=client_credentials
KAFKA_PROXY_SASL_OIDC_CLIENT_ID=<client-id>
KAFKA_PROXY_SASL_OIDC_CLIENT_SECRET=<client-secret>
KAFKA_PROXY_SASL_OIDC_TOKEN_URL=https://login.microsoftonline.com/<tenant-id>/oauth2/v2.0/token
KAFKA_PROXY_SASL_OIDC_SCOPES=api://<resource-app-id>/.default
KAFKA_PROXY_SASL_OAUTH_LOGICAL_CLUSTER=<lkc-...>
KAFKA_PROXY_SASL_OAUTH_IDENTITY_POOL_ID=<pool-...>
```

**2. Start the container** using `--env-file`:

```bash
# Host networking (recommended — simplest setup):
docker run -d --name kafka-proxy --network host --env-file .env ghcr.io/michaelkoch/kproxy:master

# Or with explicit port mapping:
docker run -d --name kafka-proxy -p 9092:9092 -p 8000:8000 -p 8081:8081 -p 8082:8082 --env-file .env ghcr.io/michaelkoch/kproxy:master
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
| `KAFKA_PROXY_SASL_USERNAME` | no | — | SASL username (API key) for `SASL/PLAIN` |
| `KAFKA_PROXY_SASL_PASSWORD` | no | — | SASL password (API secret) for `SASL/PLAIN` |
| `KAFKA_PROXY_SASL_ENABLE` | no | `true` | Set to `false` to disable SASL authentication |
| `KAFKA_PROXY_SASL_METHOD` | no | `PLAIN` | SASL method (`PLAIN`, `SCRAM-SHA-256`, `SCRAM-SHA-512`, etc.) |
| `KAFKA_PROXY_SASL_PLUGIN_ENABLE` | no | `false` | Enable plugin-based SASL authentication |
| `KAFKA_PROXY_SASL_PLUGIN_COMMAND` | no | — | Plugin binary path (for OIDC: `/opt/kafka-proxy/bin/oidc-provider`) |
| `KAFKA_PROXY_SASL_PLUGIN_MECHANISM` | no | `OAUTHBEARER` | SASL plugin mechanism |
| `KAFKA_PROXY_SASL_OIDC_GRANT_TYPE` | no | `client_credentials` | OIDC grant type for `oidc-provider` (`client_credentials` or `password`) |
| `KAFKA_PROXY_SASL_OIDC_CLIENT_ID` | no | — | OIDC client ID (when not using credentials file) |
| `KAFKA_PROXY_SASL_OIDC_CLIENT_SECRET` | no | — | OIDC client secret (when not using credentials file) |
| `KAFKA_PROXY_SASL_OIDC_TOKEN_URL` | no | — | OIDC token endpoint URL |
| `KAFKA_PROXY_SASL_OIDC_SCOPES` | no | — | Comma-separated OIDC scopes |
| `KAFKA_PROXY_SASL_OAUTH_LOGICAL_CLUSTER` | no | — | Kafka logical cluster extension (`logicalCluster`, usually `lkc-...`) |
| `KAFKA_PROXY_SASL_OAUTH_IDENTITY_POOL_ID` | no | — | Kafka identity pool extension (`identityPoolId`, usually `pool-...`) |
| `KAFKA_PROXY_TLS_ENABLE` | no | — | Set to `true` to enable TLS to upstream broker |
| `KAFKA_PROXY_TLS_INSECURE_SKIP_VERIFY` | no | — | Set to `true` to skip TLS certificate verification |
| `KAFKA_PROXY_LISTENER_TLS_ENABLE` | no | — | Set to `true` to enable TLS on the proxy listener |
| `KAFKA_PROXY_LOG_LEVEL` | no | `info` | Log level (`trace`, `debug`, `info`, `warning`, `error`) |
| `KAFKA_PROXY_LOG_FORMAT` | no | `text` | Log format (`text` or `json`) |
| `KAFKA_PROXY_HTTP_LISTEN_ADDRESS` | no | `0.0.0.0:9080` | Health/metrics listen address |
| `KAFKA_PROXY_HTTP_HEALTH_PATH` | no | `/health` | Health endpoint path |
| `KAFKA_PROXY_HTTP_METRICS_PATH` | no | `/metrics` | Prometheus metrics endpoint path |
| `SCHEMA_REGISTRY_UPSTREAM` | no | — | Schema Registry URL (enables nginx proxy on :8081) |
| `SCHEMA_REGISTRY_OIDC_GRANT_TYPE` | no | falls back to `KAFKA_PROXY_SASL_OIDC_GRANT_TYPE` (or `client_credentials`) | OIDC grant type for Schema Registry token acquisition (`client_credentials` or `password`) |
| `SCHEMA_REGISTRY_OIDC_CLIENT_ID` | no | falls back to `KAFKA_PROXY_SASL_OIDC_CLIENT_ID` | OIDC client ID used for Schema Registry token acquisition |
| `SCHEMA_REGISTRY_OIDC_CLIENT_SECRET` | no | falls back to `KAFKA_PROXY_SASL_OIDC_CLIENT_SECRET` | OIDC client secret for Schema Registry (required for `client_credentials`) |
| `SCHEMA_REGISTRY_OIDC_TOKEN_URL` | no | falls back to `KAFKA_PROXY_SASL_OIDC_TOKEN_URL` | OIDC token endpoint URL for Schema Registry |
| `SCHEMA_REGISTRY_OIDC_SCOPES` | no | falls back to `KAFKA_PROXY_SASL_OIDC_SCOPES` | OIDC scopes used for Schema Registry token acquisition |
| `SCHEMA_REGISTRY_OIDC_USERNAME` | no | falls back to `KAFKA_PROXY_SASL_OIDC_USERNAME` | OIDC username for Schema Registry when `SCHEMA_REGISTRY_OIDC_GRANT_TYPE=password` |
| `SCHEMA_REGISTRY_OIDC_PASSWORD` | no | falls back to `KAFKA_PROXY_SASL_OIDC_PASSWORD` | OIDC password for Schema Registry when `SCHEMA_REGISTRY_OIDC_GRANT_TYPE=password` |
| `SCHEMA_REGISTRY_LOGICAL_CLUSTER` | no | falls back to `KAFKA_PROXY_SASL_OAUTH_LOGICAL_CLUSTER` | Schema Registry logical cluster header (`target-sr-cluster`, should be `lsrc-...` or `lscc-...`) |
| `SCHEMA_REGISTRY_IDENTITY_POOL_ID` | no | falls back to `KAFKA_PROXY_SASL_OAUTH_IDENTITY_POOL_ID` | Schema Registry identity pool header (`Confluent-Identity-Pool-Id`) |
| Schema Registry OIDC refresh | n/a | automatic | Token refresh is automatic when OIDC env vars are configured; nginx is reloaded after refresh |
| `SCHEMA_REGISTRY_API_KEY` | no | — | Schema Registry API key |
| `SCHEMA_REGISTRY_API_SECRET` | no | — | Schema Registry API secret |
| `BLOB_STORAGE_LISTEN_PORT` | no | `8082` | Local listen port for Blob Storage nginx proxy |
| `BLOB_STORAGE_ACCOUNT` | no | — | Azure Storage account name (without domain) |
| `BLOB_STORAGE_SAS_TOKEN` | no | — | SAS token used when forwarding blob requests (with or without leading `?`) |

#### `.env` file example (full)

```bash
# Kafka connection (required)
KAFKA_PROXY_BOOTSTRAP_SERVERS=pkc-xxxxx.eu-central-1.aws.confluent.cloud:9092

# Kafka auth via OIDC plugin (no credentials file)
KAFKA_PROXY_SASL_ENABLE=true
KAFKA_PROXY_SASL_PLUGIN_ENABLE=true
KAFKA_PROXY_SASL_PLUGIN_COMMAND=/opt/kafka-proxy/bin/oidc-provider
KAFKA_PROXY_SASL_PLUGIN_MECHANISM=OAUTHBEARER
KAFKA_PROXY_SASL_OIDC_GRANT_TYPE=client_credentials
KAFKA_PROXY_SASL_OIDC_CLIENT_ID=<client-id>
KAFKA_PROXY_SASL_OIDC_CLIENT_SECRET=<client-secret>
KAFKA_PROXY_SASL_OIDC_TOKEN_URL=https://login.microsoftonline.com/<tenant-id>/oauth2/v2.0/token
KAFKA_PROXY_SASL_OIDC_SCOPES=api://<resource-app-id>/.default
KAFKA_PROXY_SASL_OAUTH_LOGICAL_CLUSTER=<lkc-...>
KAFKA_PROXY_SASL_OAUTH_IDENTITY_POOL_ID=<pool-...>

# Schema Registry (optional — enables nginx reverse proxy on :8081)
SCHEMA_REGISTRY_UPSTREAM=https://psrc-xxxxx.eu-central-1.aws.confluent.cloud
SCHEMA_REGISTRY_LOGICAL_CLUSTER=<lsrc-...>
# Optional: use dedicated Schema Registry OIDC config
# SCHEMA_REGISTRY_OIDC_GRANT_TYPE=client_credentials
# SCHEMA_REGISTRY_OIDC_CLIENT_ID=<sr-client-id>
# SCHEMA_REGISTRY_OIDC_CLIENT_SECRET=<sr-client-secret>
# SCHEMA_REGISTRY_OIDC_TOKEN_URL=https://login.microsoftonline.com/<tenant-id>/oauth2/v2.0/token
# Optional override, defaults to KAFKA_PROXY_SASL_OIDC_SCOPES
SCHEMA_REGISTRY_OIDC_SCOPES=api://<resource-app-id>/.default

# Alternative Schema Registry auth mode (Basic)
# SCHEMA_REGISTRY_API_KEY=...
# SCHEMA_REGISTRY_API_SECRET=...

# Azure Blob Storage proxy (optional - enables nginx reverse proxy on :8082)
BLOB_STORAGE_LISTEN_PORT=8082
BLOB_STORAGE_ACCOUNT=<storage-account-name>
# Can be set with or without leading '?'
BLOB_STORAGE_SAS_TOKEN=sv=2025-01-05&ss=b&srt=sco&sp=rl&se=2026-12-31T23:59:59Z&st=2026-01-01T00:00:00Z&spr=https&sig=<signature>

# Optional tuning
KAFKA_PROXY_LOG_LEVEL=info
```

#### Exposed services

| Service | Port | Protocol | Description |
|---|---|---|---|
| Kafka Proxy | 9092 | Kafka TCP | Plaintext Kafka — TLS/SASL handled by proxy |
| Schema Registry Proxy | 8081 | HTTP | Reverse-proxies Confluent Schema Registry (nginx) |
| Blob Storage Proxy | 8082 | HTTP | Reverse-proxies Azure Blob Storage and appends SAS token |
| Health / Metrics | 8000 | HTTP | `/health` and `/metrics` endpoints |

Clients connect via plaintext — no SASL credentials or TLS configuration needed on the client side.

#### Blob Storage proxy behavior

When `BLOB_STORAGE_ACCOUNT` and `BLOB_STORAGE_SAS_TOKEN` are configured, requests to
`http://localhost:${BLOB_STORAGE_LISTEN_PORT}` are proxied to:

- `https://<account>.blob.core.windows.net/<path>`

Query parameter merge behavior:

- `/container/blob.txt` -> `?<sas-token>`
- `/container/blob.txt?foo=bar` -> `?foo=bar&<sas-token>`

Example calls:

```bash
# List blobs in a container (if SAS has list permissions)
curl -s "http://localhost:8082/my-container?restype=container&comp=list"

# Download a blob
curl -fL "http://localhost:8082/my-container/path/to/blob.txt" -o blob.txt

# Range read
curl -H "Range: bytes=0-1023" -i "http://localhost:8082/my-container/path/to/blob.txt"
```

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
