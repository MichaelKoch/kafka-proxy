#!/usr/bin/env bash
# Port-forward Kafka, Schema Registry, and Kafka UI from Kubernetes
# Namespace: kafka
#
# Forwarded ports:
#   localhost:19092 -> kafka:9092       (Kafka broker)
#   localhost:18081 -> schema-registry:8081 (Schema Registry)
#   localhost:18080 -> kafka-ui:8080    (Kafka UI)
#
# Usage: ./portforward.sh [start|stop]

set -euo pipefail

NAMESPACE="kafka"
PIDFILE="/tmp/kafka-portforward.pids"

start() {
    echo "Starting port-forwards in namespace '$NAMESPACE'..."

    # Kafka broker
    kubectl -n "$NAMESPACE" port-forward svc/kafka 19092:9092 &
    echo $! >> "$PIDFILE"
    echo "  Kafka broker:     localhost:19092 -> kafka:9092"

    # Schema Registry
    kubectl -n "$NAMESPACE" port-forward svc/schema-registry 18081:8081 &
    echo $! >> "$PIDFILE"
    echo "  Schema Registry:  localhost:18081 -> schema-registry:8081"

    # Kafka UI
    kubectl -n "$NAMESPACE" port-forward svc/kafka-ui 18080:8080 &
    echo $! >> "$PIDFILE"
    echo "  Kafka UI:         localhost:18080 -> kafka-ui:8080"

    echo ""
    echo "Port-forwards running. PIDs saved to $PIDFILE"
    echo "Stop with: $0 stop"
    echo ""
    echo "Quick test:"
    echo "  kcat -b localhost:19092 -L"
    echo "  curl http://localhost:18081/subjects"
    echo "  open http://localhost:18080"

    wait
}

stop() {
    if [[ -f "$PIDFILE" ]]; then
        echo "Stopping port-forwards..."
        while read -r pid; do
            kill "$pid" 2>/dev/null && echo "  Killed PID $pid" || true
        done < "$PIDFILE"
        rm -f "$PIDFILE"
        echo "Done."
    else
        echo "No active port-forwards found ($PIDFILE not present)."
        # Try to kill any stray kubectl port-forward processes for this namespace
        pkill -f "kubectl.*port-forward.*-n $NAMESPACE" 2>/dev/null && echo "Killed stray processes." || true
    fi
}

case "${1:-start}" in
    start) start ;;
    stop)  stop ;;
    *)     echo "Usage: $0 [start|stop]"; exit 1 ;;
esac
