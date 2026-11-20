# Домашнее задание №5: обработка данных в Prefect

Флоу Prefect поднимает Spark под YARN, читает заказы из HDFS, считает агрегаты и сохраняет результат как таблицу Hive

## Схема

```
Prefect flow (edge-нода team-21-en)
  1. start_spark     -> SparkSession, master = yarn
  2. connect_hdfs    -> подключение к HDFS, проверка входных файлов
  3. read_orders     -> чтение CSV из HDFS
  4. transform       -> типы, выручка, агрегация по товарам и месяцам
  5. save_parquet    -> запись в HDFS (Parquet)
  6. register_table  -> таблица Hive поверх этих файлов + проверка
```

| Узел | Что используется |
|---|---|
| `team-21-en` | Prefect, Spark Driver, beeline, Hive Metastore, HiveServer2 |
| `team-21-nn` | NameNode, ResourceManager, NodeManager |
| `team-21-00`, `team-21-01` | DataNode, NodeManager (тут работают Spark executors) |

## Структура

* `config.env` — пути к Spark, Hadoop, Hive, входные и выходные пути в HDFS
* `requirements.txt` — Prefect
* `setup_env.sh` — создание venv с Prefect
* `run.sh` — запуск флоу, лог сохраняется в `evidence/`
* `flow.py` — флоу и задачи
* `sql/create_table.hql` — создание таблицы Hive и проверочные запросы

## Предварительные требования

* Работают HDFS, YARN и Hive (Metastore и HiveServer2) из прошлых ДЗ
* На edge-ноде есть Spark 3.5.9 (`/home/team/spark-3.5.9-bin-hadoop3`) и конфиги Hadoop (`/home/team/hadoop-conf`)
* В HDFS лежит CSV с заказами: `/data/hw3/staging/orders/`, колонки `order_id, order_date, region, product, quantity, price`
* У `team` есть `sudo` без пароля: beeline запускается от `hadoop`, и от него же создается папка `/data/hw5` в HDFS (`/data` принадлежит `hadoop`)
* Есть доступ к PyPI для установки Prefect

## Запуск

На edge-ноде от `team`:

```bash
git clone https://github.com/zhivetinamariia/data-platforms-team-homeworks.git hw5
cd hw5/task-05
bash run.sh
```

* При первом запуске `run.sh` вызывает `setup_env.sh`: создается `/home/team/hw5-venv` и ставится Prefect
* PySpark берется из установленного Spark, версия совпадает с кластером
* Перед флоу `run.sh` создает в HDFS папку `/data/hw5` и делает `team` ее владельцем, иначе Spark не сможет туда писать
* Флоу можно запускать повторно: данные в HDFS перезаписываются, таблица пересоздается

## Шаги флоу

**1. `start_spark`** — `SparkSession` с `master=yarn`, режим `client`: driver на edge-ноде, executors в контейнерах YARN. Адрес и порты driver зафиксированы (`10.21.0.10`, `39000`, `39001`), чтобы executors могли к нему подключиться. Память: 1 executor по 1 ГБ, driver 1 ГБ (узлы отдают YARN по 2 ГБ). В лог пишется id приложения в YARN

**2. `connect_hdfs`** — через Hadoop FileSystem API выводится адрес HDFS и проверяется, что входные файлы есть. Если нет — флоу падает с понятной ошибкой

**3. `read_orders`** — CSV из HDFS в DataFrame, в лог число строк и колонки

**4. `transform`**
* типы: `order_date` → date, `quantity` → int, `price` → double, строки с пустыми значениями выкидываются
* новые колонки: `revenue = quantity * price`, год и месяц заказа
* агрегация по товару и месяцу: число заказов, количество, выручка, средняя цена

**5. `save_parquet`** — результат в HDFS в Parquet: `/data/hw5/product_monthly_sales`

**6. `register_table`** — beeline выполняет `sql/create_table.hql`: база `hw5`, внешняя таблица `hw5.product_monthly_sales` поверх файлов из шага 5, потом проверочные запросы

Таблица создается через Hive, а не `saveAsTable`: в Spark 3.5 встроен клиент Hive 2.3, а у нас Hive 4.0.0-alpha-2, совместимость не гарантируется

## Проверка

* `run.sh` заканчивается на `[+] Готово`, в логе Prefect все задачи `Completed`, флоу — `Finished in state Completed()`
* в логе `register_table` число строк в таблице и топ-10 по выручке
* в ResourceManager (`http://<внешний IP edge-ноды>:8088`) приложение `HW5_Prefect_Orders`, тип SPARK, статус `FINISHED`
* таблица вручную:

```bash
sudo -u hadoop /home/hadoop/apache-hive-4.0.0-alpha-2-bin/bin/beeline \
  -u "jdbc:hive2://localhost:10000/default" -n hadoop \
  -e "SELECT * FROM hw5.product_monthly_sales LIMIT 10;"
```

Логи запусков: `evidence/run-<дата>.log`
