# загрузка датасета погоды в ClickHouse
# https://www.kaggle.com/datasets/guillemservera/global-daily-climate-data/data
# 27.6kk строк, 2.7Gb в виде датафрейма

import time
import findspark
import pandas as pd
from pyspark.sql import SparkSession
from pyspark.sql.functions import to_timestamp

findspark.init()

# --
# ru.yandex.clickhouse устарел, начиная с версии 0.4.0 надо использовать com.clickhouse:clickhouse-jdbc:0.5.0
# однако этот драйвер предполагает работу по http (8132), чтобы заливать по tcp через 9000 порт нужен нативный драйвер
# --
# т.к. в датасете есть исторические даты (Some locations provide historical data tracing back to January 2, 1833)
# то выставим параметры в LEGACY иначе потом получим ошибку INCONSISTENT_BEHAVIOR_CROSS_VERSION.READ_ANCIENT_DATETIME
# --
# нужно использовать shaded драйвер, иначе будет ошибка 
# pyspark.errors.exceptions.captured.IllegalArgumentException: Invalid offset or length (25, 52) in array of length 52 
spark = SparkSession\
    .builder\
    .appName("WeatherLoadApp")\
    .config('spark.jars.packages', 'com.github.housepower:clickhouse-native-jdbc-shaded:2.7.1')\
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

# пишем данные
start = time.time()

df.write\
    .format("jdbc")\
    .mode('append')\
    .option("driver", "com.github.housepower.jdbc.ClickHouseDriver")\
    .option("url", "jdbc:clickhouse://localhost:9000")\
    .option("dbtable", "weatherdata.weather")\
    .save()

end = time.time()

print(end - start)