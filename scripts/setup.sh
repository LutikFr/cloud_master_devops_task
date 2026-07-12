#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANSIBLE_DIR="$ROOT_DIR/ansible"

log(){ printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }

if [[ ${EUID} -eq 0 ]]; then
  echo "Do not run this script as root. Run it as a sudo-capable user: ./scripts/setup.sh" >&2
  echo "Minikube with Docker driver must be started as a regular user." >&2
  exit 1
fi

log "Validate sudo access"
sudo -v

if ! command -v ansible-playbook >/dev/null 2>&1; then
  log "Install Ansible"
  sudo apt-get update
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ansible
fi

log "Install Ansible collections"
if command -v ansible-galaxy >/dev/null 2>&1; then
  ansible-galaxy collection install -r "$ANSIBLE_DIR/requirements.yml" || true
fi

log "Run Ansible playbook"
cd "$ANSIBLE_DIR"
ansible-playbook -i inventory.local.ini site.yml "$@"

log "Installation finished"
