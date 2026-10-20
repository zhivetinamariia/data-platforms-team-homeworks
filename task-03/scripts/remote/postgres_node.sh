# Выполняется на PG_HOST от root (передается по ssh через stdin).
# Перед этим кодом 02_setup_postgres.sh подставляет переменные:
# METASTORE_DB, METASTORE_DB_USER, METASTORE_DB_PASSWORD, HIVE_CLIENT_CIDR, PG_PORT
set -Eeuo pipefail

log()  { echo "[+] $(hostname -s): $*"; }
skip() { echo "[=] $(hostname -s): SKIP: $*"; }

PGPORT_NOW=5432
psql_su() { sudo -u postgres psql -p "$PGPORT_NOW" -v ON_ERROR_STOP=1 -qtA "$@"; }

if ! command -v pg_lsclusters >/dev/null; then
  log "Устанавливаю PostgreSQL"
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq postgresql >/dev/null
else
  skip "PostgreSQL уже установлен"
fi
systemctl enable --now postgresql >/dev/null

# Ждем, пока кластер начнет принимать подключения
for _ in $(seq 1 20); do
  sudo -u postgres pg_isready -q && break
  sleep 1
done

need_restart=0

# Слушать сетевой интерфейс, а не только localhost
current=$(psql_su -c "SHOW listen_addresses")
if [[ "$current" != "*" ]]; then
  log "listen_addresses: '$current' -> '*'"
  psql_su -c "ALTER SYSTEM SET listen_addresses = '*'"
  need_restart=1
else
  skip "listen_addresses уже '*'"
fi

current_port=$(psql_su -c "SHOW port")
if [[ "$current_port" != "$PG_PORT" ]]; then
  log "port: $current_port -> $PG_PORT"
  psql_su -c "ALTER SYSTEM SET port = $PG_PORT"
  need_restart=1
fi

# Доступ к БД метастора только пользователю hive и только с edge-ноды
HBA=$(psql_su -c "SHOW hba_file")
RULE="host    ${METASTORE_DB}    ${METASTORE_DB_USER}    ${HIVE_CLIENT_CIDR}    scram-sha-256"
if grep -Eq "^host[[:space:]]+${METASTORE_DB}[[:space:]]+${METASTORE_DB_USER}[[:space:]]+${HIVE_CLIENT_CIDR//./\\.}[[:space:]]" "$HBA"; then
  skip "правило в pg_hba.conf уже есть"
else
  log "Добавляю правило в $HBA"
  cp -a "$HBA" "$HBA.bak-$(date +%Y%m%d-%H%M%S)"
  echo "$RULE" >> "$HBA"
  need_restart=1
fi

if (( need_restart )); then
  log "Перезапускаю PostgreSQL"
  systemctl restart postgresql
  for _ in $(seq 1 20); do
    sudo -u postgres pg_isready -q -p "$PG_PORT" && break
    sleep 1
  done
fi

# Пользователь и база для метастора (повторный запуск только синхронизирует пароль)
PGPORT_NOW="$PG_PORT"
if [[ "$(psql_su -c "SELECT 1 FROM pg_roles WHERE rolname = '${METASTORE_DB_USER}'")" == 1 ]]; then
  skip "роль ${METASTORE_DB_USER} уже есть, обновляю пароль"
else
  log "Создаю роль ${METASTORE_DB_USER}"
  psql_su -c "CREATE ROLE ${METASTORE_DB_USER} LOGIN"
fi
# Пароль передаем через stdin, чтобы он не попал в список процессов
psql_su <<SQL
ALTER ROLE ${METASTORE_DB_USER} WITH LOGIN PASSWORD '${METASTORE_DB_PASSWORD}';
SQL

if [[ "$(psql_su -c "SELECT 1 FROM pg_database WHERE datname = '${METASTORE_DB}'")" == 1 ]]; then
  skip "база ${METASTORE_DB} уже есть"
else
  log "Создаю базу ${METASTORE_DB} (владелец ${METASTORE_DB_USER})"
  sudo -u postgres createdb -p "$PGPORT_NOW" -O "${METASTORE_DB_USER}" -E UTF8 "${METASTORE_DB}"
fi

log "PostgreSQL готов: $(psql_su -c 'SELECT version()' | cut -d, -f1)"
log "Слушает адреса: $(psql_su -c 'SHOW listen_addresses'), порт $PG_PORT"
