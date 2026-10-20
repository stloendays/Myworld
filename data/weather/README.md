# 天气配置（M2）

计划为每种天气放一个 `WeatherProfile` Resource：CLEAR、OVERCAST、LIGHT_RAIN、HEAVY_RAIN、FOG、SNOW。字段草案：

- `weather_id`、`cloud_cover`、`fog_density`、`wetness`、`precipitation`（none / rain / snow）与粒子密度
- `transition_seconds`：30–90 现实秒
- `min_hours` / `max_hours`：单次驻留 3–8 游戏小时
- `audio_layers`：M3 的天气音层

测试预设：Autumn_Dusk_Clear、Autumn_Night_HeavyRain、Winter_Morning_Snow、Spring_Fog。室内区域 `cabin_interior` 禁止降水粒子。目前目录为空，M1 不读取它。
