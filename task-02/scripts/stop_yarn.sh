#!/usr/bin/env bash
# Остановка JobHistory Server, NodeManager-ов и ResourceManager (HDFS не трогаем)
source "$(dirname "$0")/common.sh"

remote() { local host="$1"; shift; hssh "$host" "bash -lc '$*'"; }

log "Останавливаю JobHistory Server"
remote "$NN_HOST" "$HADOOP_HOME/bin/mapred --daemon stop historyserver" || true
for host in $NM_HOSTS; do
  log "Останавливаю NodeManager на $host"
  remote "$host" "$HADOOP_HOME/bin/yarn --daemon stop nodemanager" || true
done
log "Останавливаю ResourceManager"
remote "$NN_HOST" "$HADOOP_HOME/bin/yarn --daemon stop resourcemanager" || true
