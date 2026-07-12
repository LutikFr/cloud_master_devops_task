#!/usr/bin/env bash
set -euo pipefail
kubectl delete virtualservice -n demo httpbin-delay-user httpbin-abort-component httpbin-db-delay 2>/dev/null || true
kubectl delete virtualservice -n harbor harbor-core-delay 2>/dev/null || true
echo "All chaos VirtualServices removed."
