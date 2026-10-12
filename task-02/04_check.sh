#!/usr/bin/env bash
# Проверка
source "$(dirname "$0")/common.sh"

fail=0
check_url() {   # $1 — название, $2 — url
  local code
  code=$(curl -s -o /dev/null -w '%{http_code}' -L --max-time 10 "$2" || true)
  if [[ "$code" == "200" ]]; then
    log "$1: $2 → HTTP $code"
  else
    warn "$1: $2 → HTTP $code"; fail=1
  fi
}

log "Веб-интерфейсы через nginx (с edge-ноды):"
[[ "$PUBLISH_NAMENODE" == "true" ]] && check_url "NameNode" "http://127.0.0.1:$NN_PUBLIC_PORT/"
check_url "ResourceManager" "http://127.0.0.1:$RM_PUBLIC_PORT/cluster"
check_url "JobHistory"      "http://127.0.0.1:$JHS_PUBLIC_PORT/jobhistory"
port=$NM_PUBLIC_PORT_BASE
for h in $NM_HOSTS; do
  check_url "NodeManager $h" "http://127.0.0.1:$port/node"
  port=$((port + 1))
done

if [[ "${SKIP_JOB:-false}" != "true" ]]; then
  log "Запускаю тестовую задачу pi на YARN"
  hssh "$NN_HOST" "bash -lc '$HADOOP_HOME/bin/yarn jar $HADOOP_HOME/share/hadoop/mapreduce/hadoop-mapreduce-examples-*.jar pi 2 10'" \
    || { warn "Тестовая задача упала"; fail=1; }
fi

if [[ $fail -eq 0 ]]; then
  log "Всё работает. Откройте в браузере http://<внешний IP edge-ноды>:$RM_PUBLIC_PORT"
else
  die "Есть проблемы — см. предупреждения выше"
fi
