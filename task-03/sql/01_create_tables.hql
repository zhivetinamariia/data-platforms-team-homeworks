-- Таблицы для загрузки данных о заказах
-- Параметры передаются через --hivevar: db, staging_dir, table_dir

CREATE DATABASE IF NOT EXISTS ${hivevar:db};
USE ${hivevar:db};

-- Staging: внешняя таблица поверх CSV-файлов в HDFS (данные не копируются)
CREATE EXTERNAL TABLE IF NOT EXISTS orders_staging (
  order_id    BIGINT,
  order_date  DATE,
  region      STRING,
  product     STRING,
  quantity    INT,
  price       DECIMAL(10,2)
)
ROW FORMAT DELIMITED
  FIELDS TERMINATED BY ','
STORED AS TEXTFILE
LOCATION '${hivevar:staging_dir}'
TBLPROPERTIES ('skip.header.line.count' = '1');

-- Целевая таблица: партиции по году и месяцу заказа, формат ORC
CREATE EXTERNAL TABLE IF NOT EXISTS orders (
  order_id    BIGINT,
  order_date  DATE,
  region      STRING,
  product     STRING,
  quantity    INT,
  price       DECIMAL(10,2)
)
PARTITIONED BY (order_year INT, order_month INT)
STORED AS ORC
LOCATION '${hivevar:table_dir}'
TBLPROPERTIES ('external.table.purge' = 'true');
