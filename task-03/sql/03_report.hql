-- Проверка результата загрузки
USE ${hivevar:db};

SHOW PARTITIONS orders;

SELECT order_year, order_month, count(*) AS orders_cnt, round(sum(quantity * price), 2) AS revenue
FROM orders
GROUP BY order_year, order_month
ORDER BY order_year, order_month;
