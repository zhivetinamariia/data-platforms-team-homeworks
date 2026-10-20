#!/usr/bin/env bash
# Проверка: Hive работает не в embedded-режиме, принимает несколько клиентов одновременно,
# данные загружены в партиционированную таблицу
source "$(dirname "$0")/common.sh"
require_edge
load_secrets

fail=0
mkdir -p "$WORK_DIR"
ok()  { echo "[OK]   $*"; }
bad() { echo "[FAIL] $*"; fail=1; }

echo "===== Сервисы ====="
for pair in "Hive Metastore:$METASTORE_CLASS" "HiveServer2:$HS2_CLASS"; do
  name="${pair%%:*}"; class="${pair#*:}"
  pid=$(hive_pid "$class")
  [[ -n "$pid" ]] && ok "$name работает отдельным процессом (pid $pid)" || bad "$name не запущен"
done
for pair in "Metastore Thrift:$METASTORE_PORT" "HiveServer2 JDBC:$HS2_PORT" "HiveServer2 Web UI:$HS2_WEBUI_PORT"; do
  port_open "${pair#*:}" && ok "${pair%%:*} слушает порт ${pair#*:}" || bad "${pair%%:*}: порт ${pair#*:} закрыт"
done

echo "===== Metastore во внешней БД (не embedded Derby) ====="
url=$(sudo -n grep -A1 'javax.jdo.option.ConnectionURL' "$HIVE_HOME/conf/hive-site.xml" | grep -o 'jdbc:[^<]*' || true)
[[ "$url" == jdbc:postgresql://* ]] && ok "ConnectionURL = $url" || bad "ConnectionURL не PostgreSQL: '$url'"
uris=$(sudo -n grep -A1 'hive.metastore.uris' "$HIVE_HOME/conf/hive-site.xml" | grep -o 'thrift://[^<]*' || true)
[[ -n "$uris" ]] && ok "hive.metastore.uris = $uris (удаленный Metastore)" || bad "hive.metastore.uris не задан"
if sudo -n find "/home/$HADOOP_USER" "$HIVE_HOME" -maxdepth 2 -type d -name metastore_db 2>/dev/null | grep . >/dev/null; then
  bad "найден каталог Derby metastore_db — где-то использовался embedded-режим"
else
  ok "каталога Derby metastore_db нет"
fi

pg() { PGPASSWORD="$METASTORE_DB_PASSWORD" psql -h "$PG_HOST" -p "$PG_PORT" -U "$METASTORE_DB_USER" -d "$METASTORE_DB" -qtAc "$1" 2>/dev/null; }
ver=$(pg 'SELECT "SCHEMA_VERSION" FROM "VERSION"' || true)
[[ -n "$ver" ]] && ok "схема метастора в PostgreSQL $PG_HOST, версия $ver" || bad "в PostgreSQL нет схемы метастора"
pg_parts=$(pg "SELECT count(*) FROM \"PARTITIONS\" p JOIN \"TBLS\" t ON p.\"TBL_ID\" = t.\"TBL_ID\"
               JOIN \"DBS\" d ON t.\"DB_ID\" = d.\"DB_ID\" WHERE d.\"NAME\" = '$HIVE_DB' AND t.\"TBL_NAME\" = 'orders'" || true)
[[ "${pg_parts:-0}" -gt 0 ]] && ok "в PostgreSQL записано партиций $HIVE_DB.orders: $pg_parts" || bad "в PostgreSQL нет партиций $HIVE_DB.orders"

echo "===== Несколько клиентов одновременно ====="
CLIENTS=3
tmp=$(mktemp -d "$WORK_DIR/clients.XXXX"); chmod 777 "$tmp"
for i in $(seq 1 "$CLIENTS"); do
  # каждый клиент — отдельный процесс beeline со своей сессией в HiveServer2;
  # статистика отключена, чтобы запрос реально читал данные (задача MapReduce в YARN) и сессии были видны одновременно
  ( set +e; beeline_as "client$i" "-e 'SET hive.compute.query.using.stats=false; SELECT \"client$i\", count(*) FROM $HIVE_DB.orders WHERE order_month = $i'" \
      > "$tmp/out$i" 2> "$tmp/err$i"; echo $? > "$tmp/rc$i" ) &
done

# Пока клиенты работают, смотрим в Web UI HiveServer2, сколько сессий открыто одновременно
max_sessions=0; seen_users=""
for _ in $(seq 1 90); do
  page=$(curl -s --max-time 3 "http://127.0.0.1:$HS2_WEBUI_PORT/hiveserver2.jsp" || true)
  n=$(grep -o 'Total number of sessions: [0-9]*' <<< "$page" | head -n1 | grep -o '[0-9]*$' || true)
  if [[ -n "$n" ]] && (( n > max_sessions )); then
    max_sessions=$n
    seen_users=$(grep -oE '<td>client[0-9]+</td>' <<< "$page" | sed -E 's/<\/?td>//g' | sort -u | xargs || true)
  fi
  ls "$tmp"/rc* >/dev/null 2>&1 && [[ $(ls "$tmp"/rc* | wc -l) -ge $CLIENTS ]] && break
  sleep 1
done
wait
echo "       Web UI HiveServer2: максимум одновременных сессий $max_sessions (${seen_users:-пользователи не определены})"
(( max_sessions >= CLIENTS )) && ok "HiveServer2 одновременно обслуживал $max_sessions сессии" \
  || warn "Web UI не показал $CLIENTS сессии одновременно (запросы могли завершиться слишком быстро)"
for i in $(seq 1 "$CLIENTS"); do
  if [[ "$(cat "$tmp/rc$i" 2>/dev/null)" == 0 ]]; then
    ok "клиент client$i: $(tr '\t' ' ' < "$tmp/out$i" | tail -n1)"
  else
    bad "клиент client$i завершился с ошибкой: $(grep -iE 'error' "$tmp/err$i" | tail -n1)"
  fi
done
rm -rf "$tmp"

echo "===== Партиционированная таблица ====="
parts=$(beeline_as hadoop "-e 'SHOW PARTITIONS $HIVE_DB.orders'" 2>/dev/null | grep -c '^order_year=' || true)
[[ "$parts" -gt 0 ]] && ok "партиций в $HIVE_DB.orders: $parts" || bad "у $HIVE_DB.orders нет партиций"
staging=$(beeline_as hadoop "-e 'SELECT count(*) FROM $HIVE_DB.orders_staging WHERE order_id IS NOT NULL AND order_date IS NOT NULL'" 2>/dev/null | tail -n1)
target=$(beeline_as hadoop "-e 'SET hive.compute.query.using.stats=false; SELECT count(*) FROM $HIVE_DB.orders'" 2>/dev/null | tail -n1)
if [[ -n "$staging" && "$staging" == "$target" ]]; then
  ok "строк в staging и в $HIVE_DB.orders совпадает: $target"
else
  # если в таблицу загружались разные файлы, итог может быть больше последней порции
  [[ -n "$target" && -n "$staging" && "$target" -gt "$staging" ]] \
    && ok "в $HIVE_DB.orders $target строк (последняя загрузка: $staging)" \
    || bad "строк в staging: '$staging', в $HIVE_DB.orders: '$target'"
fi
dirs=$(hdfs_cmd "dfs -ls '$DATA_ROOT/orders/*'" 2>/dev/null | grep -c 'order_month=' || true)
[[ "$dirs" -gt 0 ]] && ok "каталогов партиций в HDFS $DATA_ROOT/orders: $dirs" || bad "в HDFS нет каталогов партиций"

echo
if (( fail == 0 )); then
  echo "PASS: Hive развернут в многопользовательском режиме, данные загружены в партиционированную таблицу"
else
  echo "FAIL: есть ошибки, см. выше" >&2
  exit 1
fi
