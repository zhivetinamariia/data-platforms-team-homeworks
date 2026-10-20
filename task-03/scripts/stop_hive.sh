#!/usr/bin/env bash
# Остановка HiveServer2 и Hive Metastore (HDFS, YARN и PostgreSQL не трогаем)
source "$(dirname "$0")/common.sh"
require_edge

stop_service() {   # $1 — класс, $2 — название
  local pid
  pid=$(hive_pid "$1")
  if [[ -z "$pid" ]]; then
    skip "$2 не запущен"
    return
  fi
  log "Останавливаю $2 (pid $pid)"
  sudo -n -u "$HADOOP_USER" kill "$pid"
  for _ in $(seq 1 30); do
    [[ -z "$(hive_pid "$1")" ]] && { log "$2 остановлен"; return; }
    sleep 1
  done
  warn "$2 не завершился за 30 с, отправляю SIGKILL"
  sudo -n -u "$HADOOP_USER" kill -9 "$pid" || true
}

# Сначала HiveServer2, потом Metastore
stop_service "$HS2_CLASS"       "HiveServer2"
stop_service "$METASTORE_CLASS" "Hive Metastore"
