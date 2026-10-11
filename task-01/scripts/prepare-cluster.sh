#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/configs/cluster.env"

MODE="${1:---check}"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ "$#" -le 1 && ( "$MODE" == --check || "$MODE" == --install ) ]] ||
  fail "Usage: $0 [--check|--install]"

[[ "$(id -un)" == "$ADMIN_USER" ]] ||
  fail "Run as $ADMIN_USER on the edge node"

[[ "$(hostname -s)" == "$EDGE_HOST" ]] ||
  fail "Run this script on $EDGE_HOST"

[[ -r "$ADMIN_SSH_KEY" ]] ||
  fail "Internal SSH key is not readable: $ADMIN_SSH_KEY"

sudo -n true || fail "Passwordless sudo is required"

SSH_OPTS=(
  -o BatchMode=yes
  -o ConnectTimeout=10
  -o IdentitiesOnly=yes
  -i "$ADMIN_SSH_KEY"
)

echo "===== LOCAL EDGE: $MODE ====="
sudo -n bash "$ROOT/scripts/prepare-node.sh" "$MODE"

for node in "${DATANODE_HOSTS[@]}"; do
  echo "===== REMOTE NODE: $node ($MODE) ====="

  ssh "${SSH_OPTS[@]}" "$ADMIN_USER@$node" \
    "sudo -n bash -s -- $MODE" \
    < "$ROOT/scripts/prepare-node.sh"
done

echo "PASS: All four nodes completed $MODE"
