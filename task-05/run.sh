#!/usr/bin/env bash
# запуск флоу, лог пишется в evidence/
set -euo pipefail
cd "$(dirname "$0")"

set -a
source config.env
set +a

[[ -x "$VENV_DIR/bin/python" ]] || bash setup_env.sh

# pyspark из самого Spark, чтобы версии совпадали
PY4J_ZIP=$(ls "$SPARK_HOME"/python/lib/py4j-*-src.zip | head -n1)
export PYTHONPATH="$SPARK_HOME/python:$PY4J_ZIP:${PYTHONPATH:-}"
export SPARK_LOCAL_IP="$DRIVER_HOST"
export PYSPARK_PYTHON=python3
export PATH="$SPARK_HOME/bin:$PATH"

# /data принадлежит hadoop -> папку под результат создаем от него и отдаем текущему юзеру
echo "[+] Папка /data/hw5 в HDFS"
sudo -u hadoop "$HDFS_BIN" dfs -mkdir -p /data/hw5
sudo -u hadoop "$HDFS_BIN" dfs -chown "$(whoami)" /data/hw5

mkdir -p evidence
LOG="evidence/run-$(date +%Y%m%d-%H%M%S).log"
echo "[+] Запуск флоу, лог: $LOG"

"$VENV_DIR/bin/python" flow.py 2>&1 | tee "$LOG"
echo "[+] Готово"
