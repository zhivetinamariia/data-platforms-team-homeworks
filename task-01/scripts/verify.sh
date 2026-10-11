#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/configs/cluster.env"
export JAVA_HOME
export LC_ALL=C

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ "$(id -un)" == hadoop ]] ||
  fail "Run this script as the hadoop user"

[[ -x "$HADOOP_HOME/bin/hdfs" ]] ||
  fail "HDFS executable not found"

SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=10)

echo "===== VERIFICATION TIME ====="
date -Is

echo "===== HADOOP VERSION ====="
"$HADOOP_HOME/bin/hadoop" version

echo "===== HDFS REPORT ====="
report="$("$HADOOP_HOME/bin/hdfs" dfsadmin -report)"
printf '%s\n' "$report"

live="$(awk '/^Live datanodes \(/ {
  gsub(/[^0-9]/, "", $0); print $0
}' <<< "$report")"

[[ "$live" == 3 ]] ||
  fail "Expected 3 live DataNodes, found: ${live:-unknown}"

if grep -Eq '^Dead datanodes \([1-9][0-9]*\)' <<< "$report"; then
  fail "Dead DataNodes found"
fi

normal="$(grep -Ec '^Decommission Status[[:space:]]*:[[:space:]]*Normal[[:space:]]*$' <<< "$report" || true)"
[[ "$normal" == 3 ]] ||
  fail "Expected 3 DataNodes with Normal status, found: $normal"

for metric in \
  "Under replicated blocks" \
  "Blocks with corrupt replicas" \
  "Missing blocks"
do
  value="$(awk -F ':' -v key="$metric" '{name=$1; value=$2; gsub(/^[[:space:]]+|[[:space:]]+$/, "", name); gsub(/^[[:space:]]+|[[:space:]]+$/, "", value); if (name == key) print value}' <<< "$report")"
  [[ "$value" == 0 ]] ||
    fail "$metric: ${value:-unknown}"
done

echo "===== SAFE MODE ====="
safe_mode="$("$HADOOP_HOME/bin/hdfs" dfsadmin -safemode get)"
printf '%s\n' "$safe_mode"
grep -Fq "Safe mode is OFF" <<< "$safe_mode" ||
  fail "NameNode is in safe mode"

echo "===== JAVA PROCESSES ====="
for node in "${DATANODE_HOSTS[@]}"; do
  echo "--- $node ---"
  processes="$(ssh "${SSH_OPTS[@]}" "hadoop@$node" \
    "$JAVA_HOME/bin/jps")"
  printf '%s\n' "$processes"

  grep -Eq '^[0-9]+[[:space:]]+DataNode$' <<< "$processes" ||
    fail "DataNode process missing on $node"

  if [[ "$node" == "$NAMENODE_HOST" ]]; then
    grep -Eq '^[0-9]+[[:space:]]+NameNode$' <<< "$processes" ||
      fail "NameNode process missing on $node"
  fi
done

echo "===== SECONDARY NAMENODE ====="
secondary_processes="$(ssh "${SSH_OPTS[@]}" "hadoop@$SECONDARY_HOST" \
  "$JAVA_HOME/bin/jps")"
printf '%s\n' "$secondary_processes"
grep -Eq '^[0-9]+[[:space:]]+SecondaryNameNode$' <<< "$secondary_processes" ||
  fail "SecondaryNameNode process missing on $SECONDARY_HOST"

echo "PASS: 3 live Normal DataNodes, required processes present,"
echo "safe mode OFF, no missing, corrupt or under-replicated blocks."
echo "Note: this check does not test file write/read or inspect logs."
