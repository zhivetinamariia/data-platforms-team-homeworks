
CREATE DATABASE IF NOT EXISTS hw4;

CREATE EXTERNAL TABLE IF NOT EXISTS hw4.sales_summary (
    region STRING,
    orders_count BIGINT,
    total_revenue DOUBLE
)
PARTITIONED BY (
    order_year INT,
    order_month INT
)
STORED AS PARQUET
LOCATION 'hdfs:///data/hw4/sales_summary';

MSCK REPAIR TABLE hw4.sales_summary;

SHOW PARTITIONS hw4.sales_summary;

SELECT *
FROM hw4.sales_summary
LIMIT 10;
