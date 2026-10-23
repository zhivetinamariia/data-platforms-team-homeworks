#!/usr/bin/env bash
set -euo pipefail

export SPARK_HOME=/home/team/spark-3.5.9-bin-hadoop3
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export HADOOP_CONF_DIR=/home/team/hadoop-conf
export YARN_CONF_DIR=/home/team/hadoop-conf
export SPARK_LOCAL_IP=10.21.0.10
export PATH="$SPARK_HOME/bin:$PATH"

cd /home/team/hw4

spark-submit \
  --master yarn \
  --deploy-mode client \
  --conf spark.driver.host=10.21.0.10 \
  --conf spark.driver.bindAddress=10.21.0.10 \
  --conf spark.driver.port=39000 \
  --conf spark.blockManager.port=39001 \
  --conf spark.executor.instances=1 \
  --conf spark.executor.memory=1g \
  --conf spark.driver.memory=1g \
  homework4.py

sudo cp create_table.sql /tmp/hw4_create_table.sql
sudo chmod 644 /tmp/hw4_create_table.sql

sudo -u hadoop \
  /home/hadoop/apache-hive-4.0.0-alpha-2-bin/bin/beeline \
  -u "jdbc:hive2://localhost:10000/default" \
  -n hadoop \
  -f /tmp/hw4_create_table.sql
