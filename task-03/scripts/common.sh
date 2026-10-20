#!/usr/bin/env bash
# Общие функции для скриптов ДЗ-3

set -Eeuo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_DIR/config.env"

SECRETS_FILE="$REPO_DIR/secrets.env"
WORK_DIR="${WORK_DIR:-/tmp/hw3-hive}"     # временные файлы, доступные и team, и hadoop
HIVE_LOG_DIR="$HIVE_HOME/logs"
HIVE_JAVA_HOME="${HIVE_JAVA_HOME:-$JAVA_HOME}"
JDBC_URL="jdbc:hive2://${EDGE_HOST}:${HS2_PORT}/default"

log()  { echo "[+] $*"; }
skip() { echo "[=] SKIP: $*"; }
warn() { echo "[!] $*"; }
die()  { echo "[x] $*" >&2; exit 1; }

# Скрипты запускаются на edge-ноде пользователем team
require_edge() {
  [[ "$(hostname -s)" == "$EDGE_HOST" ]] || die "Запускайте скрипт на $EDGE_HOST"
  [[ "$(id -un)" == "$ADMIN_USER" ]] || die "Запускайте скрипт от пользователя $ADMIN_USER"
  sudo -n true 2>/dev/null || die "Нужен sudo без пароля для $ADMIN_USER"
}

# Команда от имени hadoop на edge (с окружением Hadoop и Hive)
hrun() {
  sudo -n -u "$HADOOP_USER" -H env \
    JAVA_HOME="$HIVE_JAVA_HOME" HADOOP_HOME="$HADOOP_HOME" HIVE_HOME="$HIVE_HOME" \
    HIVE_CONF_DIR="$HIVE_HOME/conf" HADOOP_CONF_DIR="$HADOOP_HOME/etc/hadoop" \
    PATH="$HIVE_HOME/bin:$HADOOP_HOME/bin:$HIVE_JAVA_HOME/bin:/usr/local/bin:/usr/bin:/bin" \
    bash -c "cd ~ && $1"
}

# ssh от hadoop к узлам кластера (ключи настроены в ДЗ-1)
hssh() {
  local host="$1"; shift
  sudo -n -u "$HADOOP_USER" -H ssh -o BatchMode=yes -o ConnectTimeout=10 \
    -o StrictHostKeyChecking=accept-new "${HADOOP_USER}@${host}" "$@"
}

# ssh от team (с sudo) к внутренним узлам
admin_ssh() {
  local host="$1"; shift
  ssh -o BatchMode=yes -o ConnectTimeout=10 -o IdentitiesOnly=yes \
    -o StrictHostKeyChecking=accept-new -i "$ADMIN_SSH_KEY" "${ADMIN_USER}@${host}" "$@"
}

hdfs_cmd() { hrun "hdfs $*"; }

# Пароль пользователя БД метастора: создается один раз и хранится вне git
load_secrets() {
  if [[ ! -f "$SECRETS_FILE" ]]; then
    log "Генерирую пароль для пользователя БД $METASTORE_DB_USER в secrets.env"
    ( umask 077; echo "METASTORE_DB_PASSWORD=$(openssl rand -hex 16)" > "$SECRETS_FILE" )
  fi
  source "$SECRETS_FILE"
  [[ -n "${METASTORE_DB_PASSWORD:-}" ]] || die "METASTORE_DB_PASSWORD пуст в $SECRETS_FILE"
}

# /home/hadoop закрыт для других пользователей (права 750 в Ubuntu 24.04),
# поэтому файлы Hadoop и Hive проверяем от root
rtest() { sudo -n test "$@"; }
# Список файлов по маске внутри /home/hadoop (пусто, если ничего нет)
rglob() { sudo -n bash -c 'shopt -s nullglob; for f in $1; do echo "$f"; done' _ "$1"; }

# Слушает ли локальный порт (без внешних утилит: встроенный в bash /dev/tcp)
port_open() { (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null; }

wait_port() {   # $1 — порт, $2 — название, $3 — таймаут в секундах
  local port="$1" name="$2" timeout="${3:-120}" i
  for ((i = 0; i < timeout; i += 3)); do
    port_open "$port" && { log "$name слушает порт $port"; return 0; }
    sleep 3
  done
  return 1
}

# Процессы Hive ищем по главному классу (в jps оба видны как RunJar)
METASTORE_CLASS=org.apache.hadoop.hive.metastore.HiveMetaStore
HS2_CLASS=org.apache.hive.service.server.HiveServer2
hive_pid() { pgrep -u "$HADOOP_USER" -f "$1" | head -n1 || true; }

# Запуск beeline от hadoop; $1 — имя клиента (-n), остальное — параметры beeline
beeline_as() {
  local user="$1"; shift
  hrun "beeline -u '$JDBC_URL' -n '$user' --silent=true --showHeader=false --outputformat=tsv2 $*"
}
