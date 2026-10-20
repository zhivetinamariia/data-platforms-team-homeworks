#!/usr/bin/env bash
# Автоматизированная загрузка данных в партиционированную таблицу Hive
#   bash scripts/05_load_data.sh               — сгенерировать тестовый CSV и загрузить его
#   bash scripts/05_load_data.sh orders.csv    — загрузить свой файл
# Формат CSV (первая строка — заголовок):
#   order_id,order_date(YYYY-MM-DD),region,product,quantity,price
source "$(dirname "$0")/common.sh"
require_edge

[[ -n "$(hive_pid "$HS2_CLASS")" ]] || die "HiveServer2 не запущен, сначала 04_start_hive.sh"

mkdir -p "$WORK_DIR/data"
chmod 755 "$WORK_DIR" "$WORK_DIR/data"
SRC="${1:-}"

if [[ -z "$SRC" ]]; then
  SRC="$WORK_DIR/data/orders_generated.csv"
  log "Генерирую $GEN_ROWS строк тестовых заказов за 2025 год: $SRC"
  # Свой генератор псевдослучайных чисел (Park–Miller): rand() в mawk из Ubuntu 24.04
  # не повторяется даже с srand(42), а так файл при каждом запуске одинаковый
  awk -v rows="$GEN_ROWS" '
  function rnd() { seed = (seed * 16807) % 2147483647; return seed / 2147483647 }
  BEGIN {
    seed = 42
    split("31 28 31 30 31 30 31 31 30 31 30 31", days, " ")
    split("Moscow Saint-Petersburg Vladivostok Novosibirsk Kazan Yekaterinburg", reg, " ")
    split("laptop phone tablet monitor keyboard mouse headphones printer", prod, " ")
    split("899.00 499.00 349.00 199.00 49.00 25.00 89.00 159.00", base, " ")
    print "order_id,order_date,region,product,quantity,price"
    for (i = 1; i <= rows; i++) {
      m = int(rnd() * 12) + 1
      d = int(rnd() * days[m]) + 1
      p = int(rnd() * 8) + 1
      r = int(rnd() * 6) + 1
      q = int(rnd() * 5) + 1
      printf "%d,2025-%02d-%02d,%s,%s,%d,%.2f\n", i, m, d, reg[r], prod[p], q, base[p] * (0.8 + rnd() * 0.4)
    }
  }' > "$SRC"
else
  [[ -r "$SRC" ]] || die "Файл $SRC не найден"
  head -n1 "$SRC" | grep -qi '^order_id,order_date' || warn "Первая строка не похожа на заголовок — она будет пропущена"
fi

rows=$(( $(wc -l < "$SRC") - 1 ))
log "Строк данных в файле: $rows"
chmod 644 "$SRC" 2>/dev/null || true

STAGING_DIR="$DATA_ROOT/staging/orders"
TABLE_DIR="$DATA_ROOT/orders"
HDFS_FILE="$STAGING_DIR/$(date +%Y%m%d-%H%M%S)_$(basename "$SRC")"

log "Кладу файл в HDFS: $HDFS_FILE"
# staging содержит только текущую порцию данных
hdfs_cmd "dfs -mkdir -p $STAGING_DIR $TABLE_DIR"
hdfs_cmd "dfs -rm -r -f -skipTrash '$STAGING_DIR/*'" >/dev/null
sudo -n -u "$HADOOP_USER" -H env JAVA_HOME="$JAVA_HOME" \
  "$HADOOP_HOME/bin/hdfs" dfs -put -f - "$HDFS_FILE" < "$SRC"
hdfs_cmd "dfs -ls $STAGING_DIR"

# SQL-файлы копируем туда, где их может прочитать hadoop
cp "$REPO_DIR"/sql/*.hql "$WORK_DIR/"
chmod 644 "$WORK_DIR"/*.hql
VARS="--hivevar db=$HIVE_DB --hivevar staging_dir=$STAGING_DIR --hivevar table_dir=$TABLE_DIR"

log "Создаю базу $HIVE_DB и таблицы (если их нет)"
beeline_as hadoop "$VARS -f $WORK_DIR/01_create_tables.hql" 2>"$WORK_DIR/beeline.err" \
  || { tail -n 20 "$WORK_DIR/beeline.err"; die "Ошибка создания таблиц"; }

if ! staging_cnt=$(beeline_as hadoop "-e 'SELECT count(*) FROM $HIVE_DB.orders_staging WHERE order_id IS NOT NULL AND order_date IS NOT NULL'" 2>"$WORK_DIR/beeline.err" | tail -n1); then
  grep -iE 'error|exception|FAILED' "$WORK_DIR/beeline.err" | tail -n 20
  die "Hive не смог прочитать staging-таблицу (запрос в YARN). Подробности: $WORK_DIR/beeline.err и /tmp/$HADOOP_USER/hive.log"
fi
log "Hive видит в staging строк с данными: $staging_cnt"

log "Загружаю данные в партиционированную таблицу $HIVE_DB.orders (MapReduce в YARN)"
beeline_as hadoop "$VARS -f $WORK_DIR/02_load_orders.hql" 2>"$WORK_DIR/beeline.err" \
  || { grep -iE 'error|exception' "$WORK_DIR/beeline.err" | tail -n 20; die "Ошибка загрузки в $HIVE_DB.orders"; }

log "Партиции и итоги по месяцам:"
beeline_as hadoop "$VARS -f $WORK_DIR/03_report.hql" 2>/dev/null

log "Файлы таблицы в HDFS:"
hdfs_cmd "dfs -ls -R $TABLE_DIR" | grep -E '^d' | awk '{print "    " $NF}' || true
log "Загрузка завершена"
