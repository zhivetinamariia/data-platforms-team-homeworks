#!/usr/bin/env bash
# venv с prefect
set -euo pipefail
cd "$(dirname "$0")"
source config.env

echo "[+] Проверка Spark, Hadoop, Hive"
for p in "$SPARK_HOME/bin/spark-submit" "$HADOOP_CONF_DIR/core-site.xml" "$HADOOP_CONF_DIR/yarn-site.xml"
do
  [[ -e "$p" ]] || { echo "[x] Нет $p"; exit 1; }
done
sudo test -x "$HIVE_HOME/bin/beeline" || { echo "[x] Нет beeline в $HIVE_HOME"; exit 1; }

if ! python3 -c "import ensurepip" 2>/dev/null
then
  echo "[+] Ставлю python3-venv"
  sudo apt-get update -q && sudo apt-get install -y -q python3-venv
fi

if [[ ! -x "$VENV_DIR/bin/python" ]]
then
  echo "[+] Создаю venv: $VENV_DIR"
  python3 -m venv "$VENV_DIR"
fi

echo "[+] Ставлю Prefect"
"$VENV_DIR/bin/pip" install -q --upgrade pip
"$VENV_DIR/bin/pip" install -q -r requirements.txt
"$VENV_DIR/bin/prefect" version

echo "[+] Окружение готово"