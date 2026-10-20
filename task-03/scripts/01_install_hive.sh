#!/usr/bin/env bash
# Установка Hive на edge-ноду: пакеты, дистрибутив, JDBC-драйвер PostgreSQL, клиентские конфиги YARN
source "$(dirname "$0")/common.sh"
require_edge

rtest -x "$HADOOP_HOME/bin/hdfs" || die "Hadoop не найден в $HADOOP_HOME (см. ДЗ-1)"
[[ -x "$HIVE_JAVA_HOME/bin/java" ]] || die "Java не найдена в $HIVE_JAVA_HOME"

log "Устанавливаю пакеты: клиент PostgreSQL и JDBC-драйвер"
sudo -n apt-get update -qq
sudo -n env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  postgresql-client libpostgresql-jdbc-java curl openssl >/dev/null

# ---- Дистрибутив Hive ----
if rtest -x "$HIVE_HOME/bin/hive"; then
  skip "Hive уже установлен в $HIVE_HOME"
else
  mkdir -p "$WORK_DIR"
  TARBALL="${HIVE_TARBALL:-$WORK_DIR/$(basename "$HIVE_URL")}"

  if [[ ! -s "$TARBALL" ]]; then
    log "Скачиваю $HIVE_URL"
    curl -fL --retry 3 -o "$TARBALL.part" "$HIVE_URL"
    mv "$TARBALL.part" "$TARBALL"
  fi

  # Контрольная сумма: HIVE_SHA256 (если задана вручную), иначе .sha256 или .sha512 с archive.apache.org
  if [[ -n "${HIVE_SHA256:-}" ]]; then
    algo=256; expected="$HIVE_SHA256"
  elif expected=$(curl -fsSL "$HIVE_URL.sha256" 2>/dev/null | grep -oiE '[0-9a-f]{64}' | head -n1) && [[ -n "$expected" ]]; then
    algo=256
  elif expected=$(curl -fsSL "$HIVE_URL.sha512" 2>/dev/null | tr -d ' \n' | grep -oiE '[0-9a-f]{128}' | head -n1) && [[ -n "$expected" ]]; then
    algo=512
  else
    die "Не удалось получить контрольную сумму ($HIVE_URL.sha256/.sha512). Задайте ее вручную: HIVE_SHA256=<сумма>"
  fi
  log "Проверяю контрольную сумму SHA-$algo"
  actual=$("sha${algo}sum" "$TARBALL" | awk '{print $1}')
  [[ "${expected,,}" == "${actual,,}" ]] || die "SHA-$algo не совпадает: ожидалось $expected, получено $actual"
  log "SHA-$algo совпадает"

  log "Распаковываю в $(dirname "$HIVE_HOME")"
  sudo -n -u "$HADOOP_USER" tar -xzf - -C "$(dirname "$HIVE_HOME")" < "$TARBALL"
  rtest -x "$HIVE_HOME/bin/hive" || die "После распаковки не найден $HIVE_HOME/bin/hive"
fi

# ---- JDBC-драйвер PostgreSQL ----
if [[ -n "$(rglob "$HIVE_HOME/lib/postgresql*.jar")" ]]; then
  skip "JDBC-драйвер PostgreSQL уже лежит в $HIVE_HOME/lib"
else
  log "Копирую JDBC-драйвер PostgreSQL в $HIVE_HOME/lib"
  sudo -n install -o "$HADOOP_USER" -g "$HADOOP_USER" -m 644 \
    "$(readlink -f /usr/share/java/postgresql.jar)" "$HIVE_HOME/lib/postgresql-jdbc.jar"
fi

# ---- Guava: Hive не должен нести версию старше, чем Hadoop ----
hive_guava=$(rglob "$HIVE_HOME/lib/guava-*.jar" | head -n1 || true)
hadoop_guava=$(rglob "$HADOOP_HOME/share/hadoop/common/lib/guava-*.jar" | head -n1 || true)
if [[ -n "$hive_guava" && -n "$hadoop_guava" ]]; then
  hive_major=$(basename "$hive_guava" | sed -E 's/guava-([0-9]+).*/\1/')
  if (( hive_major < 20 )); then
    log "Заменяю $(basename "$hive_guava") на $(basename "$hadoop_guava") (конфликт с Hadoop 3)"
    sudo -n -u "$HADOOP_USER" mkdir -p "$HIVE_HOME/lib-backup"
    sudo -n mv "$hive_guava" "$HIVE_HOME/lib-backup/"
    sudo -n install -o "$HADOOP_USER" -g "$HADOOP_USER" -m 644 "$hadoop_guava" "$HIVE_HOME/lib/"
  else
    skip "Guava в Hive: $(basename "$hive_guava"), замена не нужна"
  fi
fi

# ---- Клиентские конфиги YARN/MapReduce ----
# В ДЗ-2 yarn-site.xml и mapred-site.xml разложены только на узлы кластера.
# HiveServer2 на edge запускает задачи MapReduce в YARN, поэтому копируем их с NameNode.
CONF_DIR="$HADOOP_HOME/etc/hadoop"
for f in yarn-site.xml mapred-site.xml; do
  log "Копирую $f с $NN_HOST на edge"
  sudo -n -u "$HADOOP_USER" -H scp -q -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
    "${HADOOP_USER}@${NN_HOST}:${CONF_DIR}/$f" "$CONF_DIR/$f"
done

sudo -n -u "$HADOOP_USER" mkdir -p "$HIVE_LOG_DIR"
log "Версия Hive:"
hrun "hive --version 2>/dev/null | head -n1" || warn "hive --version завершился с ошибкой"
log "Установка Hive завершена"
