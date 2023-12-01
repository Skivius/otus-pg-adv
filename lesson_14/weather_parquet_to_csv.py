import time
import findspark
import pandas as pd
from pyspark.sql import SparkSession
from pyspark.sql.functions import to_timestamp

findspark.init()

# --
# т.к. в датасете есть исторические даты (Some locations provide historical data tracing back to January 2, 1833)
# то выставим параметры в LEGACY иначе потом получим ошибку INCONSISTENT_BEHAVIOR_CROSS_VERSION.READ_ANCIENT_DATETIME
#.config('spark.jars.packages', 'org.apache.spark:spark-avro_2.13:3.5.0')\
spark = SparkSession\
    .builder\
    .appName("WeatherLoadApp")\
    .config("spark.sql.parquet.int96RebaseModeInRead", "LEGACY")\
    .config("spark.sql.parquet.int96RebaseModeInWrite", "LEGACY")\
    .config("spark.sql.parquet.datetimeRebaseModeInRead", "LEGACY")\
    .config("spark.sql.parquet.datetimeRebaseModeInWrite", "LEGACY")\
    .getOrCreate()

# читаем данные
df = spark.read.parquet("daily_weather.parquet")

# уберём пустые города
# удалим колонку с индексом из датафрейма, т.к. она нам не нужна
# поскольку даты в формате timestamp_ntz то применяем to_timestamp, иначе также упает с ошибкой
df = df.filter("city_name is not NULL")\
    .withColumn("date", to_timestamp("date"))\
    .drop("__index_level_0__")

# Convert to csv
df.write\
    .option("header","true")\
    .csv("daily_weather.csv")
