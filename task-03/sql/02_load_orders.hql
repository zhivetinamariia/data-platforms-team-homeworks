-- Загрузка из staging в партиционированную таблицу (динамические партиции)
-- Перезаписываются только партиции, которые есть в загружаемом файле,
-- поэтому повторная загрузка того же файла не создает дубликатов.
USE ${hivevar:db};

SET hive.exec.dynamic.partition = true;
SET hive.exec.dynamic.partition.mode = nonstrict;
SET hive.exec.max.dynamic.partitions = 1000;
SET hive.exec.max.dynamic.partitions.pernode = 500;

INSERT OVERWRITE TABLE orders PARTITION (order_year, order_month)
SELECT
  order_id,
  order_date,
  region,
  product,
  quantity,
  price,
  year(order_date)  AS order_year,
  month(order_date) AS order_month
FROM orders_staging
WHERE order_id IS NOT NULL
  AND order_date IS NOT NULL;
