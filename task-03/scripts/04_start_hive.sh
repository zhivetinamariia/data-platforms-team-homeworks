#!/usr/bin/env bash
# Запуск Hive Metastore и HiveServer2 на edge-ноде как отдельных фоновых сервисов
source "$(dirname "$0")/common.sh"
require_edge

sudo -n test -f "$HIVE_HOME/conf/hive-site.xml" || die "Нет hive-site.xml, сначала 03_configure_hive.sh"

start_service() {   # $1 — сервис hive, $2 — класс, $3 — порт, $4 — название, $5 — таймаут
  local service="$1" class="$2" port="$3" name="$4" timeout="$5" pid
  pid=$(hive_pid "$class")
  if [[ -n "$pid" ]]; then
    skip "$name уже запущен (pid $pid)"
  else
    log "Запускаю $name"
    # в фон уходит только сам сервис (setsid отвязывает его от терминала), вывод — в лог
    hrun "mkdir -p '$HIVE_LOG_DIR'; setsid nohup hive --service $service >> '$HIVE_LOG_DIR/$service.out' 2>&1 < /dev/null &"
  fi
  if ! wait_port "$port" "$name" "$timeout"; then
    warn "Последние строки $HIVE_LOG_DIR/$service.out и /tmp/$HADOOP_USER/hive.log:"
    sudo -n tail -n 30 "$HIVE_LOG_DIR/$service.out" || true
    sudo -n tail -n 30 "/tmp/$HADOOP_USER/hive.log" 2>/dev/null || true
    die "$name не поднялся за $timeout с"
  fi
}

# Сначала Metastore: HiveServer2 при старте подключается к нему
start_service metastore   "$METASTORE_CLASS" "$METASTORE_PORT" "Hive Metastore" 120
start_service hiveserver2 "$HS2_CLASS"       "$HS2_PORT"       "HiveServer2"    300
wait_port "$HS2_WEBUI_PORT" "HiveServer2 Web UI" 60 || warn "Web UI HiveServer2 не отвечает на $HS2_WEBUI_PORT"

log "Пробный запрос через beeline"
for i in 1 2 3 4 5; do
  if beeline_as hadoop "-e 'SELECT 1'" 2>/dev/null | grep -x 1 >/dev/null; then
    log "HiveServer2 принимает подключения: $JDBC_URL"
    break
  fi
  (( i == 5 )) && die "beeline не смог выполнить запрос"
  sleep 10
done

log "Процессы Hive:"
ps -o pid=,user=,etime=,args= -p "$(hive_pid "$METASTORE_CLASS")" | cut -c1-80 | sed 's/^/    metastore:   /' || true
ps -o pid=,user=,etime=,args= -p "$(hive_pid "$HS2_CLASS")"       | cut -c1-80 | sed 's/^/    hiveserver2: /' || true
