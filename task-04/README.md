# Домашнее задание №4 — Apache Spark под управлением YARN

## 1. Цель работы
Реализовать обработку данных в Apache Spark под управлением YARN на ранее развёрнутом кластере Hadoop: чтение данных из HDFS, преобразование, агрегация, партиционирование, сохранение и проверка через Apache Hive.

## 2. Используемые технологии
- Hadoop 3.4.0
- Spark 3.5.9
- Hive 4.0.0-alpha-2
- Java 11, Python 3.12
- HDFS, YARN, PySpark, Parquet

Кластер: `team-21`. Узел запуска: `team-21-en`.

## 3. Исходные данные
Используется CSV-файл из предыдущего задания:
`/data/hw3/staging/orders/20261020-171405_orders_generated.csv`

Столбцы: `order_id`, `order_date`, `region`, `product`, `quantity`, `price`.

## 4. Запуск Spark через YARN
Spark запускается через `spark-submit` с параметрами:
- `--master yarn` — управление ресурсами через YARN;
- `--deploy-mode client` — Driver работает на edge-узле;
- `spark.executor.instances=1` — один executor;
- `spark.executor.memory=1g`, `spark.driver.memory=1g` — выделение памяти;
- `spark.driver.host=10.21.0.10` — адрес Driver;
- `spark.driver.port=39000`, `spark.blockManager.port=39001` — фиксированные порты.

Работоспособность Spark под YARN проверена тестом SparkPi.

## 5. Чтение и преобразование данных
Обработка реализована в `homework4.py`. Spark читает CSV непосредственно из HDFS через DataFrame API.

Выполняются следующие операции:
1. Преобразование `order_date` в date, `quantity` в int, `price` в double.
2. Расчёт выручки: `revenue = quantity * price`.
3. Извлечение года и месяца из даты заказа.
4. Группировка по `region`, `order_year`, `order_month`.
5. Подсчёт количества заказов через `count` и общей выручки через `sum`.

Итоговые поля: `region`, `order_year`, `order_month`, `orders_count`, `total_revenue`.

## 6. Сохранение и партиционирование
Результат сохраняется в формате Parquet по пути:
`/data/hw4/sales_summary`

Партиционирование выполняется методом `partitionBy("order_year", "order_month")`. Данные распределяются по каталогам вида:
`order_year=2025/order_month=1/`

## 7. Создание таблицы Hive
Через SQL-скрипт `create_table.sql` создаётся база `hw4` и внешняя таблица `hw4.sales_summary`, расположенная по пути `/data/hw4/sales_summary`.

Для регистрации партиций используется:
```sql
MSCK REPAIR TABLE hw4.sales_summary;
```
Таблица регистрируется через Hive Beeline поверх файлов Parquet, сформированных Spark.

## 8. Проверка через Hive
Подключение к Hive:
```bash
sudo -u hadoop /home/hadoop/apache-hive-4.0.0-alpha-2-bin/bin/beeline \
  -u "jdbc:hive2://localhost:10000/default" -n hadoop
```
Проверочные SQL-запросы:
```sql
SHOW DATABASES;
SHOW TABLES IN hw4;
SHOW PARTITIONS hw4.sales_summary;
SELECT * FROM hw4.sales_summary LIMIT 10;
```
Результат: обнаружено 12 партиций за 2025 год, запрос SELECT успешно возвращает обработанные данные.

## 9. Автоматизированный запуск
Для автоматического выполнения используется `run.sh`, который настраивает окружение, запускает Spark через YARN, сохраняет данные в HDFS и выполняет создание и проверку таблицы Hive.

Запуск:
```bash
cd /home/team/hw4
./run.sh
```
Сохранение журнала:
```bash
./run.sh > run.log 2>&1
echo $?
```
Автоматический запуск проверен, код завершения — `0`.

## 10. Структура проекта
```text
task-04/
├── README.md
├── homework4.py
├── create_table.sql
└── run.sh
```
- `homework4.py` — обработка данных в PySpark.
- `create_table.sql` — создание и проверка Hive-таблицы.
- `run.sh` — автоматический запуск.
- `README.md` — инструкция.

## 11. Результат
Apache Spark успешно запущен под YARN. Данные прочитаны из HDFS, выполнены преобразования типов, расчёт выручки и агрегация. Результаты сохранены в Parquet с партиционированием по году и месяцу. Создана таблица `hw4.sales_summary`, зарегистрированы 12 партиций. Возможность чтения через Hive Beeline подтверждена. Автоматизированный сценарий `run.sh` успешно выполнен.

## 12. Вывод
Реализован полный процесс обработки данных: HDFS → Spark под YARN → преобразование и агрегация → партиционированный Parquet → Hive. Подготовлены скрипты и инструкция для повторного выполнения задания.
