#!/usr/bin/env bash
# Общие функции для скриптов

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_DIR/config.env"

log()  { echo "[+] $*"; }
warn() { echo "[!] $*"; }
die()  { echo "[x] $*" >&2; exit 1; }

as_hadoop() {
  if [[ "$(id -un)" == "$HADOOP_USER" ]]; then
    "$@"
  else
    sudo -u "$HADOOP_USER" -H "$@"
  fi
}

hssh() {
  local host="$1"; shift
  as_hadoop ssh -o StrictHostKeyChecking=no "${HADOOP_USER}@${host}" "$@"
}

hscp() {
  as_hadoop scp -q -o StrictHostKeyChecking=no "$@"
}

all_hadoop_hosts() {
  echo "$NN_HOST $NM_HOSTS $DN_HOSTS" | tr ' ' '\n' | sort -u
}
