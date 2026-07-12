#!/usr/bin/env bash
set -euo pipefail
NAMESPACE="${MONITORING_NAMESPACE:-monitoring}"
case "${1:-}" in
  grafana)
    echo "Grafana: http://127.0.0.1:3000  user=admin password=${GRAFANA_ADMIN_PASSWORD:-admin}"
    kubectl -n "$NAMESPACE" port-forward svc/grafana 3000:80
    ;;
  prometheus)
    echo "Prometheus: http://127.0.0.1:9090"
    kubectl -n "$NAMESPACE" port-forward svc/prometheus-server 9090:80
    ;;
  *)
    cat <<USAGE
Usage: $0 <grafana|prometheus>
USAGE
    exit 1
    ;;
esac
