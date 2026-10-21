# Dusk Lake · 暮色湖畔

一个可以自由行走的 3D 私人湖畔世界：250 × 250 m 连续地图、针叶林、湖泊、码头、一座 A 字形木屋，以及一座带泳池的玻璃泳池馆——从池底潜下去能游进地下水族馆。所有室内都和室外处在同一坐标系里（进屋不切场景、不传送、不黑屏）。

- 引擎：**Godot 4.7.2 Standard**（GDScript，Forward+，Jolt Physics），Windows 单机优先
- 需求规格：[docs/DEVELOPMENT_SPEC.md](docs/DEVELOPMENT_SPEC.md)（唯一需求来源）；阶段指令：[docs/AGENT_HANDOFF.md](docs/AGENT_HANDOFF.md)
- 当前进度：**M0、M1、第一轮正式美术、M2 天气系统、方块人物、泳池馆与地下水族馆、小动物、雷暴/彩虹/风、小地图、开发者模式、第一人称双手、木屋生活、独木舟与湖上探索、性能优化、可潜水的海洋大缸已完成**，自动检查 49/49 通过。见 [docs/QA_M0_M1.md](docs/QA_M0_M1.md)、[docs/ART_PASS.md](docs/ART_PASS.md)、[docs/M2_WEATHER_CHARACTER.md](docs/M2_WEATHER_CHARACTER.md)、[docs/POOLHOUSE_FAUNA.md](docs/POOLHOUSE_FAUNA.md)、[docs/MINIMAP_DEVMODE.md](docs/MINIMAP_DEVMODE.md)、[docs/CABIN_LIFE_CANOE.md](docs/CABIN_LIFE_CANOE.md)、[docs/PERFORMANCE.md](docs/PERFORMANCE.md)、[docs/AQUARIUM_DIVE.md](docs/AQUARIUM_DIVE.md)

![湖岸出生点](docs/screenshots/m1_01_spawn_dusk.png)

| 木屋外观 | 木屋室内（窗外是真实的室外场景） |
|---|---|
| ![](docs/screenshots/m1_03_cabin_front.png) | ![](docs/screenshots/m1_04_cabin_interior.png) |
| 码头望向木屋 | 湖面倒影 |
| ![](docs/screenshots/m1_02_lake_to_cabin.png) | ![](docs/screenshots/m1_09_lake_reflection.png) |
| 秋夜大雨（屋内无雨） | 冬日下雪 |
| ![](docs/screenshots/m2_01_night_rain_cabin.png) | ![](docs/screenshots/m2_03_winter_snow.png) |
| 方块人物 | 换装 |
| ![](docs/screenshots/m2_08_character_front.png) | ![](docs/screenshots/m2_10_outfits.png) |
| 泳池馆 | 地下水族馆 |
| ![](docs/screenshots/m2b_02_pool_hall.png) | ![](docs/screenshots/m2b_04_aquarium.png) |
| 雨后彩虹 | 林间的兔子 |
| ![](docs/screenshots/m2b_09_rainbow.png) | ![](docs/screenshots/m2b_11_rabbit.png) |

## 运行

1. 下载 Godot 4.7.2 Standard（Windows）：https://godotengine.org/download/windows/
2. 打开 Godot → 导入 → 选择本目录的 `project.godot` → 按 **F5** 运行（主场景 `scenes/main/Main.tscn`）。

命令行（把 `godot` 换成你本机的 Godot 可执行文件路径）：

```bash
godot --path . 
```

```bash
godot --headless --path . --fixed-fps 60 res://tests/TestRunner.tscn
```

第二条是自动检查，退出码 0 表示全部通过。重新生成文档截图（会弹出窗口约 10 秒）、测帧率：

```bash
godot --path . --resolution 1600x900 res://devtools/CaptureShots.tscn
```

```bash
godot --path . --resolution 1920x1080 --disable-vsync res://devtools/Benchmark.tscn
```

重新生成木屋模型（需要 Blender 5.2）、重新下载贴图：

```bash
blender --background --factory-startup --python devtools/blender/build_cabin.py
```

```bash
pwsh -File devtools/fetch_polyhaven.ps1
```

## 按键

| 操作 | 按键 |
|---|---|
| 移动 | W / A / S / D（或方向键） |
| 环视 | 鼠标 |
| 奔跑 | Shift（步行 3.2 m/s，奔跑 5.2 m/s） |
| 跳跃 | 空格（水中：上浮；靠池壁按空格爬上岸） |
| 下潜 | C 或 Ctrl（水中） |
| 交互 | E（准星中心射线 2.5 m）：开关门、生火 / 熄火、开关灯、坐下 / 站起、睡觉、上 / 下独木舟 |
| 划独木舟 | W / S 划、A / D 转向、Shift 用力划、E 下船（靠码头或岸边） |
| 第一 / 第三人称 | V（第一人称能看到自己的双手） |
| 小地图 | M（右上角圆形小地图，随朝向旋转，下方显示区域名） |
| 暂停 / 释放鼠标 | Esc（“设置”：画面、视角、操作、小地图、开发者，自动保存；“人物外观”换发型和衣服） |
| 坐标信息 | F3（日期时间天气、帧率、世界坐标、朝向、所在区域、室内/室外） |
| 聊天 | T 或 Enter 打开，/ 直接输入命令（/help 查看），↑↓ 翻历史，Esc 取消 |
| 开发者模式 | F2（左侧开发者面板：天气、季节、时间、传送；F 飞行，N 穿墙，F4 收起面板） |

## 如何验证坐标与室内外连续性

- **坐标**：按 F3。左上角显示 `X / Y / Z`（米）与朝向（0° = 北 = −Z）。出生点在湖岸 (−50, 29)，木屋中心 (−69, 37)，码头从 (−46, 26) 延伸到 (−1, 26)，湖心 (35, −2)。所有坐标都来自 `data/world/world_layout.json`。
- **连续性**：从出生点沿土路走到木屋门廊，按 E 开门走进去，F3 中“区域”会出现 `cabin_interior`、状态变为“室内”；整个过程中画面不黑屏、不跳帧、不加载。透过三角窗能看到码头和湖面——那是实时渲染的室外场景，不是贴图。
- **地图边界**：四周是逐渐变陡的山坡和密林，走到约 |114| m 处会因坡度超过 45° 而上不去，不存在空气墙。
- **湖水**：可以走进浅水，水深约 0.7 m 处停下（湖里不做深水游泳）；码头入水段有栏杆。
- **泳池馆与水族馆**：从出生点旁的岔路沿步道往南走到 (4, 84)，推开西墙的门进大厅，F3 区域显示 `poolhouse`。下楼梯或从泳池深水区池底的洞口潜下去（C 下潜），穿过玻璃水管就到了地下水族馆（区域 `aquarium`，地面 Y ≈ −5）。水下画面会变成蓝绿色。

## 目录与文件用途

| 路径 | 用途 |
|---|---|
| `project.godot` | 工程配置：主场景、Autoload、物理层命名、Forward+、Jolt Physics |
| `data/world/world_layout.json` | **世界布局唯一数据源**：边界、地形参数、湖泊、木屋、码头、区域 zone_id、步道、森林密度、M1 光照、出生点 |
| `scenes/main/Main.tscn` + `scripts/main/Main.gd` | 主场景：常驻 World、Cabin、Player 与 UI；放置出生点 |
| `scenes/world/World.tscn` | 室外世界：光照、地形、湖、森林、码头、远景、区域触发器 |
| `scenes/world/Terrain.tscn` + `scripts/world/TerrainBuilder.gd` | 257×257 高度场网格与碰撞；顶点色写入五层地表的混合权重 |
| `shaders/terrain.gdshader` | 地形五层 PBR 混合：草地 / 林下落叶 / 土路 / 岩石（三平面）/ 湖岸；预留季节、积雪、湿润参数 |
| `scenes/world/Lake.tscn` + `scripts/world/LakeBuilder.gd` | 水面（顶点色水深）、湖面反射探针、涉水上限（水下挡墙，码头处压低） |
| `scenes/world/Forest.tscn` + `scripts/world/ForestBuilder.gd` | 固定种子摆放约 2500 棵 Kenney 针叶树与秋色阔叶树、250 块岩石（每种模型一个 MultiMesh + 树干/岩石碰撞） |
| `scripts/world/GroundCoverBuilder.gd` | 地被层：草丛、灌木、野花（南部草甸）、蘑菇、树桩倒木、小石块、睡莲；40 m 区块 + 可见距离 |
| `scripts/world/Vegetation.gd` | 植被分布规则（林地密度、空地、步道走廊），地形、树木、地被共用 |
| `scripts/art/ArtMaterials.gd` | 材质库：Poly Haven 贴图按真实尺寸平铺；Kenney 模型与自制 GLB 按材质名换成项目配色 |
| `scripts/world/DockBuilder.gd` | 码头木板、桩、栏杆与碰撞 |
| `scripts/world/DistantBackdrop.gd` | 地图外的远山与台地（无碰撞） |
| `scripts/world/ZoneArea.gd`、`ZonesBuilder.gd` | 区域触发器，按 zone_id 记录角色进出 |
| `scripts/world/MeshUtil.gd` | 程序化几何工具（远山、碰撞用凸棱柱） |
| `shaders/water.gdshader` | 湖面：不透明 + 屏幕空间反射，滚动法线波纹，按水深渐变颜色 |
| `scenes/buildings/Cabin.tscn` + `scripts/buildings/Cabin.gd` | A 字形木屋：载入 Blender 模型与 Kenney 家具、灯光、碰撞、室内区域 `cabin_interior` |
| `devtools/blender/build_cabin.py` | 用 Blender 脚本生成木屋与门板 GLB（尺寸与碰撞一致，米制 UV） |
| `assets/imported/cabin/`、`assets/source/cabin_aframe.blend` | 木屋与门板模型（GLB）及可编辑的 Blender 源文件 |
| `assets/imported/kenney/`、`assets/imported/textures/` | Kenney 模型（CC0，78 个 GLB）与 Poly Haven 贴图（CC0，16 组 1k PBR） |
| `scenes/props/InteractableDoor.tscn` + `scripts/interactions/InteractableDoor.gd` | 铰链门（AnimatableBody3D，门板为 Blender 模型），uid = `cabin_front_door` |
| `scripts/interactions/Interactable.gd`、`InteractionSystem.gd` | 可交互物基类与统一 `interact(actor, target)` 契约 |
| `scenes/player/Player.tscn` + `scripts/player/FirstPersonController.gd` | 第一人称 CharacterBody3D，眼高 1.65 m，FOV 75° |
| `scenes/ui/HUD.tscn`、`PauseMenu.tscn`、`DebugOverlay.tscn` 及 `scripts/ui/` | 准星与交互提示、Esc 菜单、F3 坐标信息 |
| `scripts/core/EventBus.gd` | 事件总线（Autoload），信号名按规格第 08 章 |
| `scripts/core/WorldState.gd` | 世界状态唯一权威（Autoload）：可交互物状态、角色所在区域 |
| `scripts/core/GameSettings.gd` | 设置与按键表（Autoload），运行时注册按键 |
| `scripts/buildings/CabinLife.gd`、`scripts/interactions/`（InteractableToggle、Seat、Bed） | 木屋生活：炉火与炊烟、灯和开关、座位、床 |
| `scripts/vehicles/Canoe.gd` | 独木舟：划桨、四点取水面高度的浮动、搁浅、上下船、位置存档 |
| `scripts/systems/PerformanceDirector.gd` | 画质分级、帧率上限、动态分辨率（FSR）、局部灯距离淡出、地下关太阳阴影 |
| `devtools/Profile.tscn` | 性能剖析：逐项关特性，看帧时、CPU / GPU、绘制调用、三角形 |
| `scripts/world/Exploration.gd` | 湖上探索点（`world_layout.json → lake_pois`）：发现记录、营火帐篷芦苇睡莲摆件 |
| `scripts/core/WorldLayout.gd`、`WorldTerrain.gd`、`PhysicsLayers.gd` | 布局数据读取、解析式地形高度函数、物理层常量 |
| `scripts/systems/WorldClock.gd`、`SeasonController.gd`、`WeatherController.gd`、`ClimateSystem.gd` | 世界时间、季节、天气规则与过渡、预设入口（Main/Systems） |
| `scripts/systems/EnvironmentDirector.gd` | 把时间/季节/天气合成为太阳月亮、天空、雾、湿润积雪、降水、植被季节色 |
| `scripts/world/Precipitation.gd` | 雨雪粒子 + 跟随相机的屋顶/地面高度场碰撞（室内不下雨雪） |
| `shaders/sky.gdshader`、`glass.gdshader`、`snow_overlay.gdshader` | 天空（星空、月亮、云）、带雨痕的玻璃、积雪覆盖层 |
| `data/seasons/seasons.json`、`data/weather/weather.json` | 四季与六类天气的全部参数、测试预设 |
| `scripts/character/`（CharacterModel、CharacterAppearance、Wardrobe） | 方块人物：部位、外观插槽与挂点、动画；外观数据；衣橱目录 |
| `data/characters/wardrobe.json`、`default_appearance.json` | 所有发型/帽子/衣服/鞋/背饰款式（像素盒子），默认外观 |
| `scripts/core/PlayerProfile.gd`、`scripts/ui/WardrobePanel.gd` | 本地玩家外观（存 user://appearance.json）、外观编辑面板 |
| `scripts/ui/ChatBox.gd`、`ChatCommands.gd` | 聊天框（左下角消息记录与输入行、系统消息）与 / 命令 |
| `scripts/ui/DevPanel.gd` | F2 开发者面板：天气、季节、时间、飞行、穿墙、传送（地点在布局文件 `dev_spots`） |
| `scripts/ui/Minimap.gd` | 右上角圆形小地图：底图后台烘焙并缓存，步道和建筑矢量绘制 |
| `scripts/player/FirstPersonArms.gd` | 第一人称的双手（随外观变化，走路、跳跃、交互、游泳都有动作） |
| `scripts/core/GameSettings.gd` | 设置与按键（Autoload），保存在 `user://settings.json` |
| `scripts/systems/AudioDirector.gd`、`SaveManager.gd` | M3/M4 的**接口占位**（未运行） |
| `scripts/buildings/PoolHouse.gd` | 泳池馆与地下水族馆：大厅、泳池、池底洞口与玻璃水管、楼梯、鱼缸、灯光、碰撞、水体与区域（全部程序生成，坐标来自布局） |
| `scripts/buildings/ReefTank.gd` | 地下水族馆的海洋大缸：落地玻璃、水下通道、礁石海带沉船、气泡与光束、灯光 |
| `scripts/world/WaterVolume.gd`、`scripts/ui/UnderwaterOverlay.gd`、`shaders/underwater.gdshader` | 可游泳水体（盒形 / 圆柱）、水下滤镜 |
| `shaders/pool_tiles.gdshader`、`pool_water.gdshader`、`caustic_sand.gdshader`、`foliage.gdshader`、`include/` | 泳池马赛克与焦散、池水、缸底沙、随风摆动的植被、雨点涟漪与焦散函数 |
| `scripts/animals/`（FaunaData、FaunaSpawner、Animal、BlockyModel、BlockyMesh、FishSchool） | 小动物：出没规则、生成、行为、方块模型、鱼群 |
| `data/animals/species.json` | 所有动物的部件、配色、速度、出没规则与生成点、萤火虫 |
| `scripts/world/SignBoard.gd`、`SignsBuilder.gd`、`data/world/signs.json` | 中英双语解说立牌（立式 / 讲台 / 挂墙，牌面按文字自动定尺寸）；室外立牌位置在布局文件 `signs` 里 |
| `tests/TestRunner.tscn` | 自动检查（49 项：QA-01、QA-02、QA-10、天气、人物、泳池馆、游泳、动物、聊天框、小地图、开发者模式、设置等；`DUSK_TEST_ONLY=_test_xxx` 只跑某几项） |
| `devtools/CaptureShots.tscn` | 按预设机位截图到 `docs/screenshots/` |
| `devtools/Benchmark.tscn` | 固定机位测帧率、帧时、绘制调用与显存 |
| `devtools/fetch_polyhaven.ps1` | 下载 Poly Haven 贴图并核对 md5，写清单 |
| `assets/licenses.csv` | 外部素材许可登记表 |
| `docs/` | 规格、阶段指令、架构说明、QA 记录、地图草图、截图 |

## 已实现（M0 + M1）

- Godot 4.7.2 工程与目录结构；Autoload：GameSettings、EventBus、WorldState
- 250 × 250 m 连续地形（X/Z ∈ [−125, 125]，北 = −Z），湖盆、木屋地基、码头岸边平台、西北观景山丘、自然封闭的边缘陡坡
- 湖面（屏幕空间反射 + 盒投影反射探针，远岸树林倒映在水中）、涉水上限；码头（木板贴图、可走到尽头、带栏杆）、岸边独木舟
- Kenney 针叶林与秋色阔叶树、岩石、草丛野花蘑菇树桩等地被，步道走廊与空地自动避让
- 地表五层 PBR 材质混合，自定义天空（渐变、太阳光晕、薄云）、SSAO、雾
- 正式美术的木屋：Blender 脚本建模（石板瓦屋面、梁架、窗框、门廊坡道、铸铁炉），Kenney 家具（L 形沙发、茶几、书架、落地灯、扶手椅等）
- A 字形木屋：真实门窗、可进入的室内（沙发、茶几、书架、铸铁炉、落地灯、暖光），可开关的木门；同一场景、同一坐标系
- 第一人称控制：WASD、鼠标、Shift、空格、E、Esc、F3；FOV / 灵敏度可调
- 区域 zone_id、室内外判定（为 M3 的音区准备）
- **M2 天气系统**：世界时钟（一天 = 现实 48 分钟）与昼夜、四季（每季 12 天，植被与地表随季变色）、六类天气（晴/阴/小雨/大雨/雾/雪）及平滑过渡；雨雪粒子不进室内，窗上有雨痕，地面会变湿、积雪；F4 调试面板与四个测试预设
- **方块人物**：脸、发型、帽子、上衣、下装、鞋、背饰七个外观插槽和四个挂点，款式全部写在 JSON 里；Esc 菜单“人物外观”实时预览与保存；V 切换第一/第三人称；走跑摆臂摆腿
- **泳池馆与地下水族馆**：玻璃大厅与泳池（深水区 3.1 m），池底洞口接玻璃水管通到地下水族馆的下潜池，也可以走楼梯下去；三个鱼缸里有 59 只鱼、海龟和水母；可以游泳（浮力、下潜、爬上岸）和看到水下画面
- **小动物**：兔子、狐狸、松鼠、绿头鸭、知更鸟、蝴蝶、萤火虫，按季节、昼夜、天气出没，兔子和松鼠见人就跑
- **天气细化**：雷暴（闪电照亮天地）、风（植被摆动，带阵风）、雨后彩虹、地面水坑与雨点涟漪、雨滴溅水花、秋季落叶与春季花瓣
- **解说立牌**：步道、泳池馆、鱼缸前的中英双语立牌，场景里没有悬空文字
- **聊天框**：T 打开，可写消息、用 / 命令改时间、天气、季节与传送，天气和季节变化自动提示（见 `docs/CHAT.md`）
- **小地图与开发者模式**：右上角圆形小地图；F2 开发者模式里改天气季节、飞行、穿墙、传送
- **设置**：画面、视角（启动视角、手的显示、镜头晃动、第三人称距离与肩位）、操作、小地图，自动保存
- **第一人称的双手**：从画面下方伸出的方块手臂，袖子随外观变化，走路、跳跃、开门、游泳都有动作
- **木屋生活**：炉子生火 / 熄火（火光、火苗、炊烟）、四盏灯的开关、沙发扶手椅长椅可以坐、床可以睡到早上
- **独木舟与湖上探索**：从码头上船划到湖心小岛营地，四个探索点（小地图问号 → 金色标记）
- **性能优化**：树林分块、地形遮挡剔除、画质分级、默认 60 帧上限、动态分辨率、远处动物降频；地下水族馆每帧三角形从 630 万降到 37 万
- **海洋大缸**：从泳池一路潜进 24 m 长的大缸，和蝠鲼、礁鲨、鱼群一起游；地下大厅换了水磨石地面、水纹光和灯带
- 自动检查（49 项）、截图与性能测试工具

## 未实现（按里程碑）

- **M3**：音频 Bus 与环境音、壁炉 / 灯 / 沙发交互
- **M4**：存档读档、完整设置菜单、画质档位、Windows 导出、性能统计（尚未测帧率，不宣称 60 FPS）
- **M5**：NPC、联机（只保留了 entity_id、统一交互契约与区域事件）

## 素材与版权

外部素材全部登记在 [assets/licenses.csv](assets/licenses.csv)，均为 CC0（Kenney、Poly Haven）或本项目自制（Blender 脚本生成的木屋）；自动检查会核对 `assets/imported/` 下每个文件都有登记。规格中的两张用户参考图仅作私有视觉参考，不进入本仓库（`.gitignore` 已排除 `assets/references/`）。
