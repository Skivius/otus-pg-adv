-- DROP TABLE otusdb.weather;
CREATE TABLE otusdb.weather (
    station_id              String,
    city_name               String,
    date                    TIMESTAMP,
    season                  String,
    avg_temp_c              Decimal,
    min_temp_c              Decimal,
    max_temp_c              Decimal,
    precipitation_mm        Decimal,
    snow_depth_mm           Decimal,
    avg_wind_dir_deg        Decimal,
    avg_wind_speed_kmh      Decimal,
    peak_wind_gust_kmh      Decimal,
    avg_sea_level_pres_hpa  Decimal,
    sunshine_total_min      Decimal
);

SELECT * FROM otusdb.weather;

IMPORT INTO otusdb.weather (station_id, city_name, "date", season, avg_temp_c, min_temp_c, max_temp_c, precipitation_mm, snow_depth_mm, avg_wind_dir_deg, avg_wind_speed_kmh, peak_wind_gust_kmh, avg_sea_level_pres_hpa, sunshine_total_min)
CSV DATA (
    'http://10.129.0.29:3000/weather_data.csv'
)
WITH skip = '1';

SHOW JOBS;
-- CANCEL JOB 916076843619287041;

