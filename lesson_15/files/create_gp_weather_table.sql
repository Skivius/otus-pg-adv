CREATE TABLE weather (
    station_id              INTEGER,
    city_name               VARCHAR(250),
    dt                      TIMESTAMP,
    season                  VARCHAR(50),
    avg_temp_c              float4,
    min_temp_c              float4,
    max_temp_c              float4,
    precipitation_mm        float4,
    snow_depth_mm           float4,
    avg_wind_dir_deg        float4,
    avg_wind_speed_kmh      float4,
    peak_wind_gust_kmh      float4,
    avg_sea_level_pres_hpa  float4,
    sunshine_total_min      float4
)
DISTRIBUTED BY (station_id, dt);

    