#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/configs/cluster.env"

[[ "$(id -un)" == hadoop ]] || {
  echo "FAIL: Run this script as hadoop" >&2
  exit 1
}

start_service() {
  local host="$1" daemon="$2" class="$3"

  echo "===== $host: $class ====="

  ssh -o BatchMode=yes -o ConnectTimeout=10 "hadoop@$host" \
    bash -s -- "$HADOOP_HOME" "$JAVA_HOME" "$daemon" "$class" <<'REMOTE'
set -Eeuo pipefail

HADOOP_HOME="$1"
export JAVA_HOME="$2"
daemon="$3"
class="$4"

[[ -x "$HADOOP_HOME/bin/hdfs" ]] || {
  echo "FAIL: Hadoop executable not found" >&2
  exit 1
}

has_process() {
  "$JAVA_HOME/bin/jps" |
    awk -v expected="$class" '$2 == expected {found=1} END {exit !found}'
}

if has_process; then
  echo "SKIP: $class is already running"
  exit 0
fi

"$HADOOP_HOME/bin/hdfs" --daemon start "$daemon"

for attempt in {1..10}; do
  if has_process; then
    echo "STARTED: $class"
    exit 0
  fi
  sleep 1
done

echo "FAIL: $class did not start; inspect Hadoop logs" >&2
exit 1
REMOTE
}

start_service "$NAMENODE_HOST" namenode NameNode

for host in "${DATANODE_HOSTS[@]}"; do
  start_service "$host" datanode DataNode
done

start_service "$SECONDARY_HOST" secondarynamenode SecondaryNameNode

echo "===== WAITING FOR CLUSTER HEALTH ====="
for attempt in {1..12}; do
  if "$ROOT/scripts/verify.sh"; then
    echo "PASS: HDFS startup and verification completed"
    exit 0
  fi
  echo "Cluster is not ready yet: attempt $attempt/12"
  sleep 5
done

echo "FAIL: Cluster did not pass verification" >&2
exit 1
