#!/usr/bin/env bash
# Полное развертывание YARN и публикация веб-интерфейсов
# Запускать на edge-ноде: bash deploy.sh

set -euo pipefail
cd "$(dirname "$0")"

bash scripts/01_configure_yarn.sh
bash scripts/02_start_yarn.sh
bash scripts/03_publish_nginx.sh
bash scripts/04_check.sh