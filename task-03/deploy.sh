#!/usr/bin/env bash
# Полное развертывание Hive и загрузка данных в партиционированную таблицу
# Запускать на edge-ноде от пользователя team: bash deploy.sh [файл.csv]

set -euo pipefail
# путь к своему CSV делаем абсолютным до смены каталога
if [[ $# -gt 0 ]]; then
  [[ -r "$1" ]] || { echo "[x] Файл $1 не найден" >&2; exit 1; }
  set -- "$(realpath "$1")"
fi
cd "$(dirname "$0")"
mkdir -p evidence
LOG="evidence/deploy-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1

bash scripts/01_install_hive.sh
bash scripts/02_setup_postgres.sh
bash scripts/03_configure_hive.sh
bash scripts/04_start_hive.sh
bash scripts/05_load_data.sh "$@"
bash scripts/06_check.sh

echo "Лог развертывания: $LOG"
