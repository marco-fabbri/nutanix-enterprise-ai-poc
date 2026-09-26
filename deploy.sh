#!/usr/bin/env bash
# Run the Nutanix Enterprise AI PoC installer against an existing Ubuntu VM.
#
#   ./deploy.sh install [ansible-playbook options]   full installation (default)
#   ./deploy.sh check                                preflight checks only
#   ./deploy.sh ping                                 SSH + sudo connectivity test
#
# Extra arguments go straight to ansible-playbook, e.g.:
#   ./deploy.sh install --tags nai,ingress
#   ./deploy.sh install -e tls_mode=letsencrypt
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INVENTORY="$REPO_ROOT/inventory.ini"
PLAYBOOK="$REPO_ROOT/ansible/site.yml"
export ANSIBLE_CONFIG="$REPO_ROOT/ansible/ansible.cfg"

usage() { sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; }

command_arg="${1:-install}"
if [ "$#" -gt 0 ]; then shift; fi

case "$command_arg" in
  -h|--help|help) usage; exit 0 ;;
  install|check|ping) ;;
  *) echo "Unknown command: $command_arg" >&2; usage >&2; exit 2 ;;
esac

# --- Controller preflight -------------------------------------------------------
if [ ! -f "$INVENTORY" ]; then
  echo "inventory.ini not found. Copy inventory.example.ini to inventory.ini and fill it in." >&2
  exit 1
fi

perms=$(stat -c '%a' "$INVENTORY" 2>/dev/null || stat -f '%Lp' "$INVENTORY")
if [ "$perms" != "600" ]; then
  echo "note: inventory.ini holds credentials; consider: chmod 600 inventory.ini"
fi

for bin in ansible-playbook ansible ansible-galaxy; do
  command -v "$bin" >/dev/null 2>&1 || { echo "$bin not found. Install Ansible on this computer (see README)." >&2; exit 127; }
done

installed=$(ansible-galaxy collection list 2>/dev/null || true)
for c in ansible.posix community.general; do
  if ! grep -q "^$c " <<<"$installed"; then
    echo "==> Installing required Ansible collections"
    ansible-galaxy collection install -r "$REPO_ROOT/requirements.yml"
    break
  fi
done

# --- Run ----------------------------------------------------------------------------
cd "$REPO_ROOT/ansible"
case "$command_arg" in
  ping)
    exec ansible -i "$INVENTORY" nai_nodes -m ping -b "$@"
    ;;
  check)
    exec ansible-playbook -i "$INVENTORY" "$PLAYBOOK" --tags preflight "$@"
    ;;
  install)
    exec ansible-playbook -i "$INVENTORY" "$PLAYBOOK" "$@"
    ;;
esac
