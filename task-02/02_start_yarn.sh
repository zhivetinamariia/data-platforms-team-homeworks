#!/usr/bin/env bash
# Запуск ResourceManager, NodeManager и JobHistory Server
# Запуск на edge-ноде; команды выполняются по ssh от имени hadoop
source "$(dirname "$0")/common.sh"

YARN="$HADOOP_HOME/bin/yarn"
MAPRED="$HADOOP_HOME/bin/mapred"
HDFS="$HADOOP_HOME/bin/hdfs"

# Окружение пользователя (JAVA_HOME и т.п.) подтягиваем из профиля
remote() {
  local host="$1"; shift
  hssh "$host" "bash -lc '$*'"
}

log "Проверяю, что HDFS из ДЗ-1 работает"
if ! remote "$NN_HOST" "$HDFS dfsadmin -report >/dev/null 2>&1"; then
  die "HDFS не отвечает. Сначала запустите его: $HADOOP_HOME/sbin/start-dfs.sh на $NN_HOST"
fi

log "Создаю служебные каталоги в HDFS"
remote "$NN_HOST" "$HDFS dfs -mkdir -p /tmp /tmp/logs /user/$HADOOP_USER && \
  $HDFS dfs -chmod 1777 /tmp /tmp/logs"

log "Запускаю ResourceManager на $NN_HOST"
remote "$NN_HOST" "$YARN --daemon start resourcemanager" || warn "ResourceManager, возможно, уже запущен"

for host in $NM_HOSTS; do
  log "Запускаю NodeManager на $host"
  remote "$host" "$YARN --daemon start nodemanager" || warn "NodeManager на $host, возможно, уже запущен"
done

log "Запускаю JobHistory Server на $NN_HOST"
remote "$NN_HOST" "$MAPRED --daemon start historyserver" || warn "JobHistory Server, возможно, уже запущен"

log "Жду регистрации NodeManager в ResourceManager..."
expected=$(echo "$NM_HOSTS" | wc -w)
for _ in $(seq 1 30); do
  running=$(remote "$NN_HOST" "$YARN node -list 2>/dev/null" | grep -c RUNNING || true)
  [[ "$running" -ge "$expected" ]] && break
  sleep 2
done
remote "$NN_HOST" "$YARN node -list"
[[ "${running:-0}" -ge "$expected" ]] || warn "Зарегистрировано $running из $expected NodeManager-ов — смотрите логи в $HADOOP_HOME/logs"

log "Процессы на узлах (jps):"
for host in $(all_hadoop_hosts); do
  echo "--- $host"
  remote "$host" "jps 2>/dev/null | grep -v Jps" || echo "(jps недоступен)"
done
