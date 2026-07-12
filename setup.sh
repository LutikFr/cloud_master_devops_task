#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

PLAYBOOK="ansible/site.yml"
INVENTORY="ansible/inventory.local.ini"

if [[ "${EUID}" -eq 0 ]]; then
  echo "Do not run this script with sudo. Run it as a regular user: ./setup.sh" >&2
  exit 1
fi

echo "==> Project dir: $PROJECT_DIR"
echo "==> Current user: ${USER}"

echo "==> Checking required commands"
for cmd in sudo ansible-playbook docker minikube; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Required command not found: $cmd" >&2
    exit 1
  fi
done

echo "==> Checking Docker via sudo only"
if ! sudo docker ps >/dev/null; then
  echo "Docker is not accessible through sudo. Check Docker installation/service." >&2
  exit 1
fi

echo "==> Preparing root-owned kube/minikube directories"
sudo mkdir -p /root/.kube /root/.minikube
sudo chmod 700 /root/.kube /root/.minikube

echo "==> Cleaning any partially-created root Minikube cluster"
sudo env HOME=/root MINIKUBE_HOME=/root KUBECONFIG=/root/.kube/config minikube delete || true

echo "==> Running Ansible playbook"
ansible-playbook -i "$INVENTORY" "$PLAYBOOK" --ask-become-pass

echo "==> Done"
echo "Use kubectl like this: sudo env KUBECONFIG=/root/.kube/config kubectl get nodes"
