CREATE DATABASE IF NOT EXISTS hw5;

-- external: дропается только описание, файлы остаются
DROP TABLE IF EXISTS hw5.product_monthly_sales;

CREATE EXTERNAL TABLE hw5.product_monthly_sales (
    product        STRING,
    order_year     INT,
    order_month    INT,
    orders_count   BIGINT,
    total_quantity BIGINT,
    total_revenue  DOUBLE,
    avg_price      DOUBLE
)
STORED AS PARQUET
LOCATION 'hdfs:///data/hw5/product_monthly_sales';

-- проверка
SELECT count(*) AS rows_in_table FROM hw5.product_monthly_sales;

SELECT *
FROM hw5.product_monthly_sales
ORDER BY total_revenue DESC
LIMIT 10;