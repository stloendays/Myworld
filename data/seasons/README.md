# 季节配置（M2）

计划为每个季节放一个 `SeasonProfile` Resource（`spring.tres` / `summer.tres` / `autumn.tres` / `winter.tres`），字段草案：

- `season_id`：SPRING / SUMMER / AUTUMN / WINTER
- `foliage_tint`、`grass_tint`、`ground_tint`：树冠实例色、草地顶点色的季节调色
- `sun_color`、`sky_top`、`sky_horizon`、`fog_color`：光照与天空色温
- `allowed_weather`：可出现的 weather_id 与权重（冬季只有雪，不下雨）
- `ambience_layers`：M3 的环境音层 id

时间尺度默认值（规格 5.2）：游戏内 1 天 = 现实 48 分钟，1 季 = 12 个游戏日，初次进入 = 秋季第 1 天 17:20。目前目录为空，M1 不读取它。
