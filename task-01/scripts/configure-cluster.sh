#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/configs/cluster.env"

MODE="${1:---check}"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ "$#" -le 1 && ( "$MODE" == --check || "$MODE" == --apply ) ]] ||
  fail "Usage: $0 [--check|--apply]"

[[ "$(id -un)" == "$ADMIN_USER" ]] ||
  fail "Run as $ADMIN_USER on the edge node"

[[ "$(hostname -s)" == "$EDGE_HOST" ]] ||
  fail "Run this script on $EDGE_HOST"

[[ -r "$ADMIN_SSH_KEY" ]] ||
  fail "Internal SSH key is not readable"

sudo -n true

SSH_OPTS=(
  -o BatchMode=yes
  -o ConnectTimeout=10
  -o IdentitiesOnly=yes
  -i "$ADMIN_SSH_KEY"
)

# Check all hosts before allowing configuration changes.
if [[ "$MODE" == --apply ]]; then
  processes="$(sudo -n -u hadoop "$JAVA_HOME/bin/jps")"
  if grep -Eq '^[0-9]+[[:space:]]+(NameNode|DataNode|SecondaryNameNode)$' \
    <<< "$processes"; then
    fail "HDFS processes are running on the edge"
  fi

  for node in "${DATANODE_HOSTS[@]}"; do
    processes="$(ssh "${SSH_OPTS[@]}" "$ADMIN_USER@$node" \
      "sudo -n -u hadoop '$JAVA_HOME/bin/jps'")"

    if grep -Eq '^[0-9]+[[:space:]]+(NameNode|DataNode|SecondaryNameNode)$' \
      <<< "$processes"; then
      fail "HDFS processes are running on $node; nothing was applied"
    fi
  done
fi

echo "===== LOCAL EDGE: $MODE ====="
sudo -n bash "$ROOT/scripts/configure-node.sh" "$MODE"

for node in "${DATANODE_HOSTS[@]}"; do
  echo "===== REMOTE NODE: $node ($MODE) ====="

  tar -C "$ROOT" -czf - \
    configs scripts/configure-node.sh |
    ssh "${SSH_OPTS[@]}" "$ADMIN_USER@$node" \
      "bash -c '
        set -Eeuo pipefail
        work=\$(mktemp -d)
        trap \"rm -rf \\\"\$work\\\"\" EXIT
        tar -xzf - -C \"\$work\"
        sudo -n bash \"\$work/scripts/configure-node.sh\" \"$MODE\"
      '"
done

echo "PASS: All four nodes completed configuration $MODE"
