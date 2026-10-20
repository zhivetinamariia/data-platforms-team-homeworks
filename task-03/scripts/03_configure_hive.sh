#!/usr/bin/env bash
# Конфигурация Hive: удаленный Metastore на PostgreSQL + HiveServer2, каталоги в HDFS, схема метастора
source "$(dirname "$0")/common.sh"
require_edge
load_secrets

rtest -x "$HIVE_HOME/bin/hive" || die "Hive не установлен, сначала 01_install_hive.sh"

mkdir -p "$WORK_DIR"
OUT="$WORK_DIR/conf"
mkdir -p "$OUT"
chmod 700 "$OUT"   # временная копия hive-site.xml содержит пароль

log "Генерирую hive-site.xml"
cat > "$OUT/hive-site.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
  <!-- Metastore DB: PostgreSQL вместо встроенной Derby -->
  <property>
    <name>javax.jdo.option.ConnectionURL</name>
    <value>jdbc:postgresql://${PG_HOST}:${PG_PORT}/${METASTORE_DB}</value>
  </property>
  <property>
    <name>javax.jdo.option.ConnectionDriverName</name>
    <value>org.postgresql.Driver</value>
  </property>
  <property>
    <name>javax.jdo.option.ConnectionUserName</name>
    <value>${METASTORE_DB_USER}</value>
  </property>
  <property>
    <name>javax.jdo.option.ConnectionPassword</name>
    <value>${METASTORE_DB_PASSWORD}</value>
  </property>
  <property>
    <name>datanucleus.autoCreateSchema</name>
    <value>false</value>
  </property>
  <property>
    <name>hive.metastore.schema.verification</name>
    <value>true</value>
  </property>

  <!-- Metastore работает отдельным сервисом, клиенты ходят к нему по Thrift -->
  <property>
    <name>hive.metastore.uris</name>
    <value>thrift://${EDGE_HOST}:${METASTORE_PORT}</value>
  </property>
  <property>
    <name>hive.metastore.port</name>
    <value>${METASTORE_PORT}</value>
  </property>
  <property>
    <name>hive.metastore.warehouse.dir</name>
    <value>${HIVE_WAREHOUSE}</value>
  </property>
  <property>
    <name>hive.metastore.event.db.notification.api.auth</name>
    <value>false</value>
  </property>

  <!-- HiveServer2: точка входа для многих клиентов (beeline, JDBC) -->
  <property>
    <name>hive.server2.thrift.bind.host</name>
    <value>0.0.0.0</value>
  </property>
  <property>
    <name>hive.server2.thrift.port</name>
    <value>${HS2_PORT}</value>
  </property>
  <property>
    <name>hive.server2.webui.host</name>
    <value>0.0.0.0</value>
  </property>
  <property>
    <name>hive.server2.webui.port</name>
    <value>${HS2_WEBUI_PORT}</value>
  </property>
  <property>
    <name>hive.server2.transport.mode</name>
    <value>binary</value>
  </property>
  <property>
    <name>hive.server2.authentication</name>
    <value>NONE</value>
  </property>
  <!-- Запросы всех клиентов выполняются от hadoop: не нужен proxyuser в core-site.xml и перезапуск HDFS -->
  <property>
    <name>hive.server2.enable.doAs</name>
    <value>false</value>
  </property>

  <!-- Выполнение запросов: MapReduce в YARN из ДЗ-2 -->
  <property>
    <name>hive.execution.engine</name>
    <value>mr</value>
  </property>
  <property>
    <name>hive.exec.scratchdir</name>
    <value>/tmp/hive</value>
  </property>

  <!-- Динамическое партиционирование для загрузки -->
  <property>
    <name>hive.exec.dynamic.partition</name>
    <value>true</value>
  </property>
  <property>
    <name>hive.exec.dynamic.partition.mode</name>
    <value>nonstrict</value>
  </property>
</configuration>
EOF

log "Генерирую hive-env.sh"
cat > "$OUT/hive-env.sh" <<EOF
export JAVA_HOME=${HIVE_JAVA_HOME}
export HADOOP_HOME=${HADOOP_HOME}
export HIVE_CONF_DIR=${HIVE_HOME}/conf
# Память: 1 ГБ для Metastore и HiveServer2, 256 МБ для клиентов beeline (на edge ~4 ГБ RAM)
if [ "\$SERVICE" = "beeline" ]; then
  export HADOOP_HEAPSIZE=256
else
  export HADOOP_HEAPSIZE=${HIVE_HEAPSIZE_MB}
fi
EOF

for f in hive-site.xml hive-env.sh; do
  target="$HIVE_HOME/conf/$f"
  if sudo -n test -f "$target" && sudo -n cmp -s "$OUT/$f" "$target"; then
    skip "$f не изменился"
    continue
  fi
  if sudo -n test -f "$target"; then
    sudo -n cp -a "$target" "$target.bak-$(date +%Y%m%d-%H%M%S)"
  fi
  # hive-site.xml содержит пароль БД — читать его может только hadoop
  sudo -n install -o "$HADOOP_USER" -g "$HADOOP_USER" -m 600 "$OUT/$f" "$target"
  log "Записан $target"
  changed=1
done
if [[ -n "${changed:-}" && -n "$(hive_pid "$METASTORE_CLASS")$(hive_pid "$HS2_CLASS")" ]]; then
  warn "Hive уже запущен: новые настройки вступят в силу после bash scripts/stop_hive.sh и bash scripts/04_start_hive.sh"
fi
rm -f "$OUT/hive-site.xml"

log "Проверяю HDFS"
safemode=$(hdfs_cmd "dfsadmin -safemode get" 2>/dev/null || true)
[[ "$safemode" == *OFF* ]] || die "HDFS недоступен или в safe mode (см. ДЗ-1)"

log "Создаю каталоги Hive в HDFS"
hdfs_cmd "dfs -mkdir -p /tmp/hive $HIVE_WAREHOUSE $DATA_ROOT /user/$HADOOP_USER"
hdfs_cmd "dfs -chmod 1777 /tmp /tmp/hive"
hdfs_cmd "dfs -chmod 775 $HIVE_WAREHOUSE"

log "Проверяю схему метастора в PostgreSQL"
if hrun "schematool -dbType postgres -info" >"$WORK_DIR/schematool-info.log" 2>&1; then
  skip "схема уже создана: $(grep -i 'schema version' "$WORK_DIR/schematool-info.log" | tail -n1)"
else
  log "Инициализирую схему метастора (schematool -initSchema)"
  hrun "schematool -dbType postgres -initSchema" >"$WORK_DIR/schematool-init.log" 2>&1 \
    || { tail -n 30 "$WORK_DIR/schematool-init.log"; die "schematool -initSchema завершился с ошибкой"; }
  hrun "schematool -dbType postgres -info" 2>/dev/null | grep -i 'schema version' || true
fi
log "Конфигурация Hive готова"
