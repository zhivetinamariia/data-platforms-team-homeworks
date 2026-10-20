#!/usr/bin/env bash
# PostgreSQL как внешняя БД метастора Hive (вместо встроенной Derby) на NN_HOST
source "$(dirname "$0")/common.sh"
require_edge
load_secrets

[[ -r "$ADMIN_SSH_KEY" ]] || die "Не читается ключ $ADMIN_SSH_KEY"

# Задачи MapReduce падают с "Connection refused", если имя узла указывает на 127.0.1.1
# (строка Ubuntu по умолчанию в /etc/hosts): ApplicationMaster слушает только loopback
log "Проверяю, что имена узлов YARN указывают на сетевые адреса"
for host in $NM_HOSTS; do
  addr=$(admin_ssh "$host" 'getent hosts "$(hostname)" | awk "{print \$1; exit}"') || die "Нет ssh-доступа к $host"
  if [[ "$addr" == 127.* ]]; then
    die "На $host имя $host указывает на $addr. Закомментируйте строку 127.0.1.1 в /etc/hosts на $host (см. README, «Предварительные требования»)"
  fi
  log "$host -> $addr"
done

log "Настраиваю PostgreSQL на $PG_HOST"
{
  printf 'METASTORE_DB=%q\n'          "$METASTORE_DB"
  printf 'METASTORE_DB_USER=%q\n'     "$METASTORE_DB_USER"
  printf 'METASTORE_DB_PASSWORD=%q\n' "$METASTORE_DB_PASSWORD"
  printf 'HIVE_CLIENT_CIDR=%q\n'      "$HIVE_CLIENT_CIDR"
  printf 'PG_PORT=%q\n'               "$PG_PORT"
  cat "$REPO_DIR/scripts/remote/postgres_node.sh"
} | admin_ssh "$PG_HOST" "sudo -n bash -s"

log "Проверяю подключение к БД метастора с edge-ноды"
if PGPASSWORD="$METASTORE_DB_PASSWORD" psql -h "$PG_HOST" -p "$PG_PORT" \
     -U "$METASTORE_DB_USER" -d "$METASTORE_DB" -qtAc "SELECT current_user" >/dev/null; then
  log "Подключение $METASTORE_DB_USER@$PG_HOST:$PG_PORT/$METASTORE_DB работает"
else
  die "Не удалось подключиться к PostgreSQL с edge (проверьте HIVE_CLIENT_CIDR и firewall)"
fi
