import os
import subprocess

from prefect import flow, task, get_run_logger
try:
    from prefect.cache_policies import NO_CACHE
except ImportError:
    from prefect.cache_policies import NONE as NO_CACHE

from pyspark.sql import SparkSession, functions as F

INPUT_PATH = os.environ["INPUT_PATH"]
OUTPUT_PATH = os.environ["OUTPUT_PATH"]
HIVE_TABLE = os.environ["HIVE_TABLE"]
HIVE_HOME = os.environ["HIVE_HOME"]
HIVE_JDBC_URL = os.environ["HIVE_JDBC_URL"]
DRIVER_HOST = os.environ["DRIVER_HOST"]
SQL_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "sql", "create_table.hql")

# spark-объекты не кешируются, кеш prefect выкл
spark_task = task(cache_policy=NO_CACHE, persist_result=False)


@spark_task
def start_spark() -> SparkSession:
    log = get_run_logger()
    spark = (
        SparkSession.builder
        .appName("HW5_Prefect_Orders")
        .master("yarn")
        .config("spark.submit.deployMode", "client")
        # driver на edge, executors ходят к нему сюда
        .config("spark.driver.host", DRIVER_HOST)
        .config("spark.driver.bindAddress", DRIVER_HOST)
        .config("spark.driver.port", "39000")
        .config("spark.blockManager.port", "39001")
        # на узлах под yarn всего 2 ГБ
        .config("spark.executor.instances", "1")
        .config("spark.executor.memory", "1g")
        .config("spark.driver.memory", "1g")
        .getOrCreate()
    )
    sc = spark.sparkContext
    log.info(f"Spark {spark.version} поднят, master={sc.master}, app={sc.applicationId}")
    return spark


@spark_task
def connect_hdfs(spark: SparkSession) -> str:
    log = get_run_logger()
    jvm = spark._jvm
    fs = jvm.org.apache.hadoop.fs.FileSystem.get(spark._jsc.hadoopConfiguration())
    log.info(f"HDFS: {fs.getUri().toString()}")

    files = fs.globStatus(jvm.org.apache.hadoop.fs.Path(INPUT_PATH))
    if not files:
        raise FileNotFoundError(f"Нет файлов по пути {INPUT_PATH}")
    for f in files:
        log.info(f"Нашел {f.getPath().toString()} ({f.getLen()} байт)")
    return INPUT_PATH


@spark_task
def read_orders(spark: SparkSession, path: str):
    log = get_run_logger()
    df = spark.read.option("header", True).csv(path)
    log.info(f"Строк: {df.count()}, колонки: {df.columns}")
    return df


@spark_task
def transform(df):
    log = get_run_logger()

    # типы + выкидываем битые строки
    typed = (
        df.withColumn("order_date", F.to_date("order_date"))
          .withColumn("quantity", F.col("quantity").cast("int"))
          .withColumn("price", F.col("price").cast("double"))
          .dropna(subset=["order_date", "product", "quantity", "price"])
    )

    enriched = (
        typed.withColumn("revenue", F.col("quantity") * F.col("price"))
             .withColumn("order_year", F.year("order_date"))
             .withColumn("order_month", F.month("order_date"))
    )

    # товар x месяц
    result = (
        enriched.groupBy("product", "order_year", "order_month")
        .agg(
            F.count("*").alias("orders_count"),
            F.sum("quantity").cast("bigint").alias("total_quantity"),
            F.round(F.sum("revenue"), 2).alias("total_revenue"),
            F.round(F.avg("price"), 2).alias("avg_price"),
        )
        .orderBy("product", "order_year", "order_month")
    )

    log.info(f"После агрегации: {result.count()} строк")
    result.show(10, truncate=False)
    return result


@spark_task
def save_parquet(df) -> str:
    log = get_run_logger()
    df.write.mode("overwrite").parquet(OUTPUT_PATH)
    log.info(f"Записал в {OUTPUT_PATH}")
    return OUTPUT_PATH


# таблицу делает hive, не saveAsTable: hive-клиент spark 3.5 старый для hive 4
@task(retries=1, retry_delay_seconds=10)
def register_table(output_path: str) -> None:
    log = get_run_logger()
    # beeline от hadoop, домашка team ему не видна -> sql через /tmp
    tmp_sql = "/tmp/hw5_create_table.hql"
    subprocess.run(["sudo", "cp", SQL_FILE, tmp_sql], check=True)
    subprocess.run(["sudo", "chmod", "644", tmp_sql], check=True)

    cmd = [
        "sudo", "-u", "hadoop", f"{HIVE_HOME}/bin/beeline",
        "-u", HIVE_JDBC_URL, "-n", "hadoop",
        "--silent=true", "--outputformat=table",
        "-f", tmp_sql,
    ]
    res = subprocess.run(cmd, capture_output=True, text=True)
    log.info(res.stdout)
    if res.returncode != 0:
        log.error(res.stderr[-3000:])
        raise RuntimeError(f"beeline упал, код {res.returncode}")
    log.info(f"Таблица {HIVE_TABLE} готова ({output_path})")


@flow(name="hw5-spark-yarn-hdfs-hive", log_prints=True)
def hw5_flow():
    spark = start_spark()
    try:
        path = connect_hdfs(spark)
        orders = read_orders(spark, path)
        result = transform(orders)
        output = save_parquet(result)
    finally:
        spark.stop()
    register_table(output)


if __name__ == "__main__":
    hw5_flow()