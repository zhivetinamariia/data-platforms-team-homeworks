#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/configs/cluster.env"

MODE="${1:---check}"
TARGET="$HADOOP_HOME/etc/hadoop"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ "$#" -le 1 && ( "$MODE" == --check || "$MODE" == --apply ) ]] ||
  fail "Usage: $0 [--check|--apply]"

[[ -d "$TARGET" ]] || fail "Hadoop configuration directory not found"
[[ -x "$JAVA_HOME/bin/jps" ]] || fail "Java tools not found"

for name in core-site.xml hdfs-site.xml workers hadoop-env.sh; do
  [[ -r "$ROOT/configs/$name" ]] ||
    fail "Source configuration missing: $name"
done

check_configs() {
  echo "===== $(hostname): configuration check ====="

  for name in core-site.xml hdfs-site.xml workers; do
    cmp -s "$ROOT/configs/$name" "$TARGET/$name" ||
      fail "Configuration differs: $name"
    echo "OK: $name"
  done

  grep -Fxq "export JAVA_HOME=$JAVA_HOME" "$TARGET/hadoop-env.sh" ||
    fail "Expected JAVA_HOME setting not found"

  echo "OK: JAVA_HOME"
  echo "PASS: Configuration matches repository"
}

if [[ "$MODE" == --check ]]; then
  check_configs
  exit 0
fi

[[ "$EUID" == 0 ]] ||
  fail "Apply mode requires root"

processes="$(sudo -n -u hadoop "$JAVA_HOME/bin/jps")"
if grep -Eq '^[0-9]+[[:space:]]+(NameNode|DataNode|SecondaryNameNode)$' \
  <<< "$processes"; then
  fail "HDFS processes are running; configuration was not changed"
fi

stamp="$(date +%Y%m%dT%H%M%S)-$$"
backup="$TARGET/backup-$stamp"
install -d -o hadoop -g hadoop -m 700 "$backup"

for name in core-site.xml hdfs-site.xml workers hadoop-env.sh; do
  if [[ -f "$TARGET/$name" ]]; then
    cp -a "$TARGET/$name" "$backup/"
  fi
done

for name in core-site.xml hdfs-site.xml workers; do
  install -o hadoop -g hadoop -m 644 \
    "$ROOT/configs/$name" "$TARGET/$name"
done

# Keep the original Hadoop environment template and replace only JAVA_HOME.
temp="$(mktemp)"
trap 'rm -f "$temp"' EXIT

if [[ -f "$TARGET/hadoop-env.sh" ]]; then
  sed '/^[[:space:]]*\(export[[:space:]]\+\)\?JAVA_HOME=/d' \
    "$TARGET/hadoop-env.sh" > "$temp"
fi

printf '\nexport JAVA_HOME=%s\n' "$JAVA_HOME" >> "$temp"

install -o hadoop -g hadoop -m 644 "$temp" "$TARGET/hadoop-env.sh"

check_configs
echo "Backup directory: $backup"
