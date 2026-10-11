#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/configs/cluster.env"

[[ "$(id -un)" == hadoop ]] || {
  echo "FAIL: Run as hadoop on the edge node" >&2
  exit 1
}

[[ "$(hostname -s)" == "$EDGE_HOST" ]] || {
  echo "FAIL: Run on $EDGE_HOST" >&2
  exit 1
}

check_local_names() {
  while read -r expected host; do
    [[ -n "$expected" && -n "$host" ]] || continue

    resolved="$(getent ahostsv4 "$host")"
    addresses="$(awk '{print $1}' <<< "$resolved" | sort -u)"

    if ! grep -Fxq "$expected" <<< "$addresses"; then
      echo "FAIL: $host does not resolve to $expected" >&2
      return 1
    fi

    echo "OK: $host resolves to $expected"
  done < "$ROOT/configs/hosts.expected"
}

echo "===== EDGE NAME RESOLUTION ====="
check_local_names

for node in "${DATANODE_HOSTS[@]}"; do
  echo "===== HADOOP SSH AND NAME RESOLUTION: $node ====="

  # Send the expected address table as data, not executable code.
  ssh -o BatchMode=yes -o ConnectTimeout=10 "hadoop@$node" \
    'bash -c '"'"'
      set -Eeuo pipefail
      hostname
      [[ "$(id -un)" == hadoop ]]
      while read -r expected host; do
        [[ -n "$expected" && -n "$host" ]] || continue
        resolved="$(getent ahostsv4 "$host")"
        addresses="$(awk "{print \$1}" <<< "$resolved" | sort -u)"
        if ! grep -Fxq "$expected" <<< "$addresses"; then
          echo "FAIL: $host does not resolve to $expected" >&2
          exit 1
        fi
        echo "OK: $host resolves to $expected"
      done
    '"'"'' < "$ROOT/configs/hosts.expected"
done

echo "PASS: Name resolution checked on four nodes;"
echo "non-interactive hadoop SSH works from edge to all three server nodes."
