# Домашнее задание №3: развертывание Apache Hive

Развертывание Apache Hive 4.0.0-alpha-2 поверх кластера HDFS (ДЗ-1) и YARN (ДЗ-2) и автоматизированная загрузка данных в партиционированную таблицу.

Hive установлен **не в embedded-режиме**: метаданные хранятся во внешней БД PostgreSQL, Hive Metastore и HiveServer2 работают отдельными сервисами. Поэтому с Hive могут одновременно работать несколько клиентов (beeline, JDBC/DBeaver и т.д.).

## Схема кластера

| Узел | IP | Сервисы |
|---|---|---|
| `team-21-en` | 10.21.0.10 | **Hive Metastore** (9083), **HiveServer2** (10000, Web UI 10002), клиент beeline; клиент Hadoop и nginx из ДЗ-1/ДЗ-2 |
| `team-21-nn` | 10.21.0.11 | **PostgreSQL** (5432, БД метастора), NameNode, SecondaryNameNode, DataNode, ResourceManager, NodeManager, JobHistory Server |
| `team-21-00` | 10.21.0.12 | DataNode, NodeManager |
| `team-21-01` | 10.21.0.13 | DataNode, NodeManager |

```
 клиент 1 (beeline) ─┐
 клиент 2 (beeline) ─┼─ JDBC :10000 ─> HiveServer2 ─ Thrift :9083 ─> Hive Metastore ─ JDBC :5432 ─> PostgreSQL (team-21-nn)
 клиент 3 (DBeaver) ─┘                     │                          (описания таблиц и партиций)
                                           ├─ задачи MapReduce ─> YARN ─┐
                                           └────────────────────────────┴─> данные таблиц в HDFS
```

Клиенты подключаются только к HiveServer2. Описания таблиц и партиций HiveServer2 получает от Metastore, который хранит их в PostgreSQL. Сами данные лежат в HDFS: тяжелые запросы (например, загрузка) выполняются задачами MapReduce в YARN, простые HiveServer2 читает из HDFS сам.

### Почему не embedded

| | Embedded (по умолчанию) | Наша установка |
|---|---|---|
| БД метастора | Derby в локальном каталоге `metastore_db` | PostgreSQL на `team-21-nn` |
| Metastore | внутри процесса клиента | отдельный сервис, `hive.metastore.uris=thrift://team-21-en:9083` |
| Клиенты | Derby блокирует БД — работает только один клиент | любое число клиентов через HiveServer2 (JDBC) |

## Структура

* `config.env` — параметры: узлы, версия и путь Hive, порты, БД метастора, каталоги HDFS
* `deploy.sh` — главный скрипт: выполняет все шаги по очереди и сохраняет лог в `evidence/`
* `scripts/common.sh` — общие функции
* `scripts/01_install_hive.sh` — скачивание и установка Hive, JDBC-драйвер PostgreSQL
* `scripts/02_setup_postgres.sh` + `scripts/remote/postgres_node.sh` — PostgreSQL для метастора на `team-21-nn`
* `scripts/03_configure_hive.sh` — `hive-site.xml`, `hive-env.sh`, каталоги в HDFS, инициализация схемы метастора
* `scripts/04_start_hive.sh` — запуск Metastore и HiveServer2
* `scripts/05_load_data.sh` — загрузка CSV в партиционированную таблицу
* `scripts/06_check.sh` — итоговая проверка (включая одновременную работу нескольких клиентов)
* `scripts/stop_hive.sh` — остановка Hive
* `sql/` — HiveQL: создание таблиц, загрузка, отчет
* `secrets.env` — пароль пользователя БД `hive`; создается автоматически при первом запуске, в git не попадает (`.gitignore`)

## Предварительные требования

* Работают HDFS из ДЗ-1 (3 DataNode, safe mode выключен) и YARN из ДЗ-2 (3 NodeManager)
* Hadoop 3.4.0 в `/home/hadoop/hadoop-3.4.0` на всех узлах, включая edge; Java 11
* Пользователь `hadoop` на edge заходит по ssh без пароля на `team-21-nn` (настроено в ДЗ-1)
* На `team-21-nn`, `team-21-00`, `team-21-01` имя узла указывает на его адрес `10.21.0.x`, а не на `127.0.1.1`. Ubuntu по умолчанию добавляет в `/etc/hosts` строку `127.0.1.1 <имя узла>`; с ней ApplicationMaster задачи MapReduce слушает только loopback, и map-задачи падают с `Connection refused`. Строку нужно закомментировать (так же, как на `team-21-nn`), а к строке `10.21.0.x <имя>` дописать полное имя узла. Шаг 2 проверяет это и останавливается с подсказкой. Пример для `team-21-00`:

  ```bash
  ssh -i ~/.ssh/team_internal team@team-21-00 "sudo sed -i.bak -e 's/^127\.0\.1\.1/#127.0.1.1/' -e 's/^10\.21\.0\.12 team-21-00\$/10.21.0.12 team-21-00.hse.c.mws team-21-00/' /etc/hosts"
  sudo -u hadoop ssh team-21-00 'bash -lc "/home/hadoop/hadoop-3.4.0/bin/yarn --daemon stop nodemanager; /home/hadoop/hadoop-3.4.0/bin/yarn --daemon start nodemanager"'
  ```
* Пользователь `team` на edge: sudo без пароля, ключ `/home/team/.ssh/team_internal` для ssh на внутренние узлы с sudo (как в ДЗ-1)
* Доступ к `archive.apache.org` (дистрибутив Hive, несколько сотен МБ) и репозиториям Ubuntu

## Быстрый запуск

На edge-ноде от пользователя `team`:

```bash
git clone https://github.com/zhivetinamariia/data-platforms-team-homeworks.git
cd data-platforms-team-homeworks/task-03
bash deploy.sh
```

Чтобы загрузить свой файл вместо сгенерированного: `bash deploy.sh orders.csv` (путь можно указать относительный или полный).

Все скрипты можно запускать повторно: уже выполненные шаги установки и настройки пропускаются с сообщением `SKIP`, схема метастора повторно не создается, работающие сервисы не перезапускаются. Загрузка данных выполняется заново при каждом запуске, но перезаписывает только свои партиции, поэтому дубликатов не появляется.

Ниже — что делает каждый шаг.

## Шаг 1. Установка Hive

```bash
bash scripts/01_install_hive.sh
```

* ставит пакеты: клиент PostgreSQL и JDBC-драйвер;
* скачивает `apache-hive-4.0.0-alpha-2-bin.tar.gz` (352 МБ) и проверяет контрольную сумму SHA-256;
* распаковывает в `/home/hadoop/apache-hive-4.0.0-alpha-2-bin`;
* заменяет guava-19.0.jar из Hive на Guava 27 из Hadoop, чтобы не было конфликта версий с Hadoop 3;
* копирует `yarn-site.xml` и `mapred-site.xml` с `team-21-nn` на edge, чтобы Hive отправлял задачи в YARN.

## Шаг 2. PostgreSQL для метастора

```bash
bash scripts/02_setup_postgres.sh
```

* проверяет, что имена узлов указывают на адреса `10.21.0.x` (см. «Предварительные требования»);
* на `team-21-nn` ставит PostgreSQL 16, создает базу `metastore` и пользователя `hive` (выполняется `scripts/remote/postgres_node.sh`);
* разрешает подключение к базе только с edge; пароль генерируется в `secrets.env`;
* проверяет, что с edge к базе можно подключиться.

## Шаг 3. Конфигурация Hive и схема метастора

```bash
bash scripts/03_configure_hive.sh
```

* создает `hive-site.xml`: метастор в PostgreSQL (`jdbc:postgresql://team-21-nn:5432/metastore`), отдельный Metastore (`thrift://team-21-en:9083`), HiveServer2 на порту 10000, выполнение запросов через MapReduce в YARN, динамические партиции;
* создает `hive-env.sh` (Java, Hadoop, память);
* создает каталоги Hive в HDFS и схему метастора в PostgreSQL (`schematool -initSchema`).

## Шаг 4. Запуск Metastore и HiveServer2

```bash
bash scripts/04_start_hive.sh
```

* запускает Metastore и HiveServer2 от `hadoop` отдельными фоновыми процессами;
* ждет открытия портов 9083, 10000, 10002 и проверяет подключение запросом `SELECT 1` через beeline.

Остановка: `bash scripts/stop_hive.sh`.

## Шаг 5. Загрузка данных в партиционированную таблицу

```bash
bash scripts/05_load_data.sh              # сгенерировать тестовые данные и загрузить
bash scripts/05_load_data.sh orders.csv   # загрузить свой файл
```

* генерирует 50 000 заказов за 2025 год (`order_id,order_date,region,product,quantity,price`) и кладет файл в HDFS;
* создает staging-таблицу поверх CSV и таблицу `hw3.orders` в формате ORC, **партиционированную по `order_year` и `order_month`**;
* переносит данные с динамическими партициями — Hive сам раскладывает строки по месяцам:

  ```sql
  INSERT OVERWRITE TABLE orders PARTITION (order_year, order_month)
  SELECT order_id, order_date, region, product, quantity, price,
         year(order_date), month(order_date)
  FROM orders_staging
  WHERE order_id IS NOT NULL AND order_date IS NOT NULL;
  ```

* выводит список партиций и итоги по месяцам.

## Шаг 6. Проверка

```bash
bash scripts/06_check.sh
```

* Metastore и HiveServer2 работают отдельными процессами, метастор в PostgreSQL, Derby не используется;
* **3 клиента одновременно** (`client1`, `client2`, `client3`) выполняют запросы, HiveServer2 показывает 3 активные сессии;
* в `hw3.orders` есть партиции, число строк совпадает с загруженным файлом.

При успехе выводится `PASS`. Для сгенерированных данных: 12 партиций, 50 000 строк.

## Подключение клиентов

С edge-ноды (несколько терминалов одновременно — это и есть многопользовательский режим):

```bash
sudo -iu hadoop
/home/hadoop/apache-hive-4.0.0-alpha-2-bin/bin/beeline -u jdbc:hive2://team-21-en:10000/default -n hadoop
```

```sql
SHOW PARTITIONS hw3.orders;
SELECT region, count(*) FROM hw3.orders WHERE order_year = 2025 AND order_month = 3 GROUP BY region;
```

Со своего компьютера (DBeaver или любой JDBC-клиент) через SSH-туннель:

```bash
ssh -N -L 127.0.0.1:10000:10.21.0.10:10000 -L 127.0.0.1:10002:10.21.0.10:10002 team@171.22.73.179
```

* JDBC URL: `jdbc:hive2://localhost:10000/default`, пользователь `hadoop`, без пароля
* Web UI HiveServer2: `http://localhost:10002` — активные сессии и история запросов

## Веб-интерфейс

На своем компьютере открыть SSH-туннель через edge. В команде указать свой ключ и адрес подключения:

```bash
ssh -i ~/.ssh/team21_ed25519 -o IdentitiesOnly=yes -o ExitOnForwardFailure=yes -N -L 127.0.0.1:10002:10.21.0.10:10002 team@171.22.73.179
```

Оставить терминал открытым и перейти в браузере на http://localhost:10002. В разделе Active Sessions отображаются подключенные клиенты: во время проверки `06_check.sh` — три сессии `client1`, `client2`, `client3`. В разделе Last Max 25 Closed Queries видны выполненные запросы, в том числе загрузка `INSERT OVERWRITE TABLE orders ...`.


## Результаты

Развертывание выполнено на кластере team-21 командой `bash deploy.sh`. Вывод разложен по шагам в `evidence/`: `01_install_hive.txt` … `06_check.txt` (шаги 1–4 — из первого запуска, где все реально устанавливалось; шаги 5–6 — из повторного запуска с `PASS`), диагностика и исправление `/etc/hosts` — в `00_hosts_fix.txt`.

* Hive 4.0.0-alpha-2 установлен на `team-21-en` (архив 352 МБ), контрольная сумма SHA-256 совпала, JDBC-драйвер PostgreSQL уже был в дистрибутиве, Guava 19 заменена на Guava 27 из Hadoop.
* PostgreSQL 16 на `team-21-nn`: база `metastore`, пользователь `hive`, доступ только с edge; схема метастора версии 4.0.0-alpha-2 создана `schematool`.
* Hive Metastore (9083) и HiveServer2 (10000, Web UI 10002) работают отдельными процессами на Java 11; каталога Derby `metastore_db` нет.
* Сгенерировано и загружено 50 000 заказов: таблица `hw3.orders` в формате ORC, 12 партиций `order_year=2025/order_month=1..12`, число строк совпадает со staging, записи о партициях есть в PostgreSQL.
* Три клиента (`client1`, `client2`, `client3`) одновременно работали с HiveServer2 — Web UI показал 3 активные сессии, все запросы завершились успешно (4057, 4216 и 4143 заказа).
* Итог `06_check.sh`: `PASS`.

При первом запуске загрузка упала с `Connection refused`: на `team-21-00` и `team-21-01` имя узла указывало на `127.0.1.1`. После исправления `/etc/hosts` (см. «Предварительные требования») и перезапуска NodeManager повторный `bash deploy.sh` пропустил выполненные шаги и завершился `PASS`.
