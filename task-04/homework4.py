
from pyspark.sql import SparkSession
from pyspark.sql.functions import (
    col, to_date, year, month, sum, count
)

spark = (
    SparkSession.builder
    .appName("HW4_Orders")
    .getOrCreate()
)

df = (
    spark.read
    .option("header", True)
    .csv("hdfs:///data/hw3/staging/orders/20261020-171405_orders_generated.csv")
)

df = (
    df.withColumn("order_date", to_date("order_date"))
      .withColumn("quantity", col("quantity").cast("int"))
      .withColumn("price", col("price").cast("double"))
)

df = df.withColumn(
    "revenue",
    col("quantity") * col("price")
)

df = (
    df.withColumn("order_year", year("order_date"))
      .withColumn("order_month", month("order_date"))
)

result = (
    df.groupBy("region", "order_year", "order_month")
      .agg(
          count("*").alias("orders_count"),
          sum("revenue").alias("total_revenue")
      )
)

result.show(20)

(
    result.write
    .mode("overwrite")
    .partitionBy("order_year", "order_month")
    .parquet("hdfs:///data/hw4/sales_summary")
)

spark.stop()
