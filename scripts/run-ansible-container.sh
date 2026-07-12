#!/usr/bin/env bash
set -euo pipefail
IMAGE="${IMAGE:-cloud-master-devops-ansible:latest}"
INVENTORY="${INVENTORY:-ansible/inventory.remote.ini}"

if [[ ! -f "$INVENTORY" ]]; then
  echo "Inventory file not found: $INVENTORY" >&2
  echo "Create it from ansible/inventory.remote.example.ini or set INVENTORY=/path/to/inventory.ini" >&2
  exit 1
fi

docker build -t "$IMAGE" -f docker/Dockerfile .
docker run --rm -it \
  -v "$PWD:/workspace" \
  -v "$HOME/.ssh:/root/.ssh:ro" \
  -w /workspace/ansible \
  "$IMAGE" -i "/workspace/$INVENTORY" site.yml "$@"
