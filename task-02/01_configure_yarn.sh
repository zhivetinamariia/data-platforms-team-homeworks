#!/usr/bin/env bash
# Генерация yarn-site.xml и mapred-site.xml и раскладывание их на все узлы кластера
source "$(dirname "$0")/common.sh"

# Каталог в /tmp для того чтобы пользователь hadoop точно мог прочитать файлы для scp
OUT_DIR="${OUT_DIR:-/tmp/hw2-yarn-conf}"
mkdir -p "$OUT_DIR"
CONF_DIR="$HADOOP_HOME/etc/hadoop"

log "Генерирую yarn-site.xml"
cat > "$OUT_DIR/yarn-site.xml" <<EOF
<?xml version="1.0"?>
<configuration>
  <property>
    <name>yarn.resourcemanager.hostname</name>
    <value>${NN_HOST}</value>
  </property>
  <property>
    <name>yarn.resourcemanager.webapp.address</name>
    <value>0.0.0.0:8088</value>
  </property>
  <property>
    <name>yarn.nodemanager.webapp.address</name>
    <value>0.0.0.0:8042</value>
  </property>

  <property>
    <name>yarn.nodemanager.aux-services</name>
    <value>mapreduce_shuffle</value>
  </property>
  <property>
    <name>yarn.nodemanager.env-whitelist</name>
    <value>JAVA_HOME,HADOOP_COMMON_HOME,HADOOP_HDFS_HOME,HADOOP_CONF_DIR,CLASSPATH_PREPEND_DISTCACHE,HADOOP_YARN_HOME,HADOOP_HOME,PATH,LANG,TZ,HADOOP_MAPRED_HOME</value>
  </property>

  <property>
    <name>yarn.nodemanager.resource.memory-mb</name>
    <value>${NM_MEMORY_MB}</value>
  </property>
  <property>
    <name>yarn.nodemanager.resource.cpu-vcores</name>
    <value>${NM_VCORES}</value>
  </property>
  <property>
    <name>yarn.scheduler.minimum-allocation-mb</name>
    <value>${CONTAINER_MB}</value>
  </property>
  <property>
    <name>yarn.scheduler.maximum-allocation-mb</name>
    <value>${NM_MEMORY_MB}</value>
  </property>
  <property>
    <name>yarn.scheduler.maximum-allocation-vcores</name>
    <value>${NM_VCORES}</value>
  </property>
  <property>
    <name>yarn.nodemanager.vmem-check-enabled</name>
    <value>false</value>
  </property>

  <property>
    <name>yarn.log-aggregation-enable</name>
    <value>true</value>
  </property>
  <property>
    <name>yarn.nodemanager.remote-app-log-dir</name>
    <value>/tmp/logs</value>
  </property>
  <property>
    <name>yarn.log.server.url</name>
    <value>http://${NN_HOST}:19888/jobhistory/logs</value>
  </property>
</configuration>
EOF

log "Генерирую mapred-site.xml"
cat > "$OUT_DIR/mapred-site.xml" <<EOF
<?xml version="1.0"?>
<configuration>
  <property>
    <name>mapreduce.framework.name</name>
    <value>yarn</value>
  </property>
  <property>
    <name>mapreduce.application.classpath</name>
    <value>\$HADOOP_MAPRED_HOME/share/hadoop/mapreduce/*:\$HADOOP_MAPRED_HOME/share/hadoop/mapreduce/lib/*</value>
  </property>
  <property>
    <name>yarn.app.mapreduce.am.env</name>
    <value>HADOOP_MAPRED_HOME=${HADOOP_HOME}</value>
  </property>
  <property>
    <name>mapreduce.map.env</name>
    <value>HADOOP_MAPRED_HOME=${HADOOP_HOME}</value>
  </property>
  <property>
    <name>mapreduce.reduce.env</name>
    <value>HADOOP_MAPRED_HOME=${HADOOP_HOME}</value>
  </property>

  <property>
    <name>yarn.app.mapreduce.am.resource.mb</name>
    <value>${CONTAINER_MB}</value>
  </property>
  <property>
    <name>yarn.app.mapreduce.am.command-opts</name>
    <value>-Xmx$((CONTAINER_MB * 8 / 10))m</value>
  </property>
  <property>
    <name>mapreduce.map.memory.mb</name>
    <value>${CONTAINER_MB}</value>
  </property>
  <property>
    <name>mapreduce.reduce.memory.mb</name>
    <value>${CONTAINER_MB}</value>
  </property>

  <property>
    <name>mapreduce.jobhistory.address</name>
    <value>${NN_HOST}:10020</value>
  </property>
  <property>
    <name>mapreduce.jobhistory.webapp.address</name>
    <value>0.0.0.0:19888</value>
  </property>
</configuration>
EOF

# Файл workers НЕ ТРОГАЕМ: он же используется start-dfs.sh для DataNode-ов

chmod 755 "$OUT_DIR"
chmod 644 "$OUT_DIR"/*.xml

STAMP=$(date +%Y%m%d-%H%M%S)
for host in $(all_hadoop_hosts); do
  log "Копируем конфиги на $host"
  hscp "$OUT_DIR/yarn-site.xml" "$OUT_DIR/mapred-site.xml" "${HADOOP_USER}@${host}:${CONF_DIR}/"
done

log "Конфигурация YARN разложена на все узлы"
