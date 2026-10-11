#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/configs/cluster.env"

[[ "$(id -un)" == hadoop ]] || {
  echo "FAIL: Run this script as hadoop" >&2
  exit 1
}

mode="${1:---check}"
[[ "$#" -le 1 && ( "$mode" == --check || "$mode" == --initialize ) ]] || {
  echo "Usage: $0 [--check|--initialize]" >&2
  exit 1
}

ssh -o BatchMode=yes -o ConnectTimeout=10 "hadoop@$NAMENODE_HOST" \
  bash -s -- "$HADOOP_HOME" "$JAVA_HOME" "$mode" <<'REMOTE'
set -Eeuo pipefail

H="$1"
export JAVA_HOME="$2"
mode="$3"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

uri="$("$H/bin/hdfs" getconf -confKey dfs.namenode.name.dir)"

# This deployment supports one absolute local NameNode directory.
[[ "$uri" != *,* ]] ||
  fail "Multiple NameNode directories are not supported by this script"

case "$uri" in
  file:///*) dir="${uri#file://}" ;;
  /*) dir="$uri" ;;
  *) fail "Unsupported NameNode directory: $uri" ;;
esac

[[ "$dir" != / ]] || fail "Refusing to use the filesystem root"

echo "NameNode directory: $dir"

if [[ -f "$dir/current/VERSION" ]]; then
  echo "SKIP: Existing NameNode metadata found; formatting is forbidden"
  exit 0
fi

if [[ "$mode" == --check ]]; then
  echo "NOT_INITIALIZED: No VERSION file found"
  echo "No changes made. Fresh deployment requires --initialize."
  exit 0
fi

processes="$("$JAVA_HOME/bin/jps")"
if grep -Eq '^[0-9]+[[:space:]]+(NameNode|DataNode|SecondaryNameNode)$' \
  <<< "$processes"; then
  fail "Stop HDFS processes on this host before initial formatting"
fi

if [[ -e "$dir" ]]; then
  [[ -d "$dir" ]] || fail "NameNode path is not a directory"
  first_entry="$(find "$dir" -mindepth 1 -maxdepth 1 -print -quit)"
  [[ -z "$first_entry" ]] ||
    fail "NameNode directory is not empty; refusing to format"
fi

echo "Initializing a new NameNode"
"$H/bin/hdfs" namenode -format -nonInteractive

[[ -f "$dir/current/VERSION" ]] ||
  fail "Formatting finished without the expected VERSION file"

echo "PASS: New NameNode initialized"
REMOTE
