# Dusk Lake · 暮色湖畔

一个可以自由行走的 3D 私人湖畔世界：250 × 250 m 连续地图、针叶林、湖泊、码头，以及一座与室外处在同一坐标系里的 A 字形木屋（进屋不切场景、不传送、不黑屏）。

- 引擎：**Godot 4.7.2 Standard**（GDScript，Forward+，Jolt Physics），Windows 单机优先
- 需求规格：[docs/DEVELOPMENT_SPEC.md](docs/DEVELOPMENT_SPEC.md)（唯一需求来源）；阶段指令：[docs/AGENT_HANDOFF.md](docs/AGENT_HANDOFF.md)
- 当前进度：**M0 基础工程 + M1 地图闭环已完成，并完成第一轮正式美术**（Kenney 模型 + Poly Haven PBR 贴图 + Blender 建模的木屋），自动检查 16/16 通过。见 [docs/QA_M0_M1.md](docs/QA_M0_M1.md)、[docs/ART_PASS.md](docs/ART_PASS.md)

![湖岸出生点](docs/screenshots/m1_01_spawn_dusk.png)

| 木屋外观 | 木屋室内（窗外是真实的室外场景） |
|---|---|
| ![](docs/screenshots/m1_03_cabin_front.png) | ![](docs/screenshots/m1_04_cabin_interior.png) |
| 码头望向木屋 | 湖面倒影 |
| ![](docs/screenshots/m1_02_lake_to_cabin.png) | ![](docs/screenshots/m1_09_lake_reflection.png) |

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
| 跳跃 | 空格 |
| 交互 | E（准星中心射线 2.5 m，例如开关木门） |
| 暂停 / 释放鼠标 | Esc（菜单内可调 FOV 65°–95°、鼠标灵敏度） |
| 坐标信息 | F3（帧率、世界坐标、朝向、所在区域、室内/室外） |

## 如何验证坐标与室内外连续性

- **坐标**：按 F3。左上角显示 `X / Y / Z`（米）与朝向（0° = 北 = −Z）。出生点在湖岸 (−50, 29)，木屋中心 (−69, 37)，码头从 (−46, 26) 延伸到 (−1, 26)，湖心 (35, −2)。所有坐标都来自 `data/world/world_layout.json`。
- **连续性**：从出生点沿土路走到木屋门廊，按 E 开门走进去，F3 中“区域”会出现 `cabin_interior`、状态变为“室内”；整个过程中画面不黑屏、不跳帧、不加载。透过三角窗能看到码头和湖面——那是实时渲染的室外场景，不是贴图。
- **地图边界**：四周是逐渐变陡的山坡和密林，走到约 |114| m 处会因坡度超过 45° 而上不去，不存在空气墙。
- **湖水**：可以走进浅水，水深约 0.7 m 处停下（MVP 不做深水游泳）；码头入水段有栏杆。

## 目录与文件用途

| 路径 | 用途 |
|---|---|
| `project.godot` | 工程配置：主场景、Autoload、物理层命名、Forward+、Jolt Physics |
| `data/world/world_layout.json` | **世界布局唯一数据源**：边界、地形参数、湖泊、木屋、码头、区域 zone_id、步道、森林密度、M1 光照、出生点 |
| `data/seasons/`、`data/weather/` | M2 的季节 / 天气配置目录（目前只有说明） |
| `scenes/main/Main.tscn` + `scripts/main/Main.gd` | 主场景：常驻 World、Cabin、Player 与 UI；放置出生点 |
| `scenes/world/World.tscn` | 室外世界：光照、地形、湖、森林、码头、远景、区域触发器 |
| `scenes/world/Terrain.tscn` + `scripts/world/TerrainBuilder.gd` | 257×257 高度场网格与碰撞；顶点色写入五层地表的混合权重 |
| `shaders/terrain.gdshader` | 地形五层 PBR 混合：草地 / 林下落叶 / 土路 / 岩石（三平面）/ 湖岸；预留季节、积雪、湿润参数 |
| `scenes/world/Lake.tscn` + `scripts/world/LakeBuilder.gd` | 水面（顶点色水深）、湖面反射探针、涉水上限（水下挡墙，码头处压低） |
| `scenes/world/Forest.tscn` + `scripts/world/ForestBuilder.gd` | 固定种子摆放约 2500 棵 Kenney 针叶树与秋色阔叶树、250 块岩石（每种模型一个 MultiMesh + 树干/岩石碰撞） |
| `scripts/world/GroundCoverBuilder.gd` | 地被层：草丛、灌木、野花（南部草甸）、蘑菇、树桩倒木、小石块、睡莲；40 m 区块 + 可见距离 |
| `scripts/world/Vegetation.gd` | 植被分布规则（林地密度、空地、步道走廊），地形、树木、地被共用 |
| `scripts/art/ArtMaterials.gd` | 材质库：Poly Haven 贴图按真实尺寸平铺；Kenney 模型与自制 GLB 按材质名换成项目配色 |
| `shaders/sky.gdshader` | 天空：渐变、太阳盘与光晕、飘动薄云（颜色与云量为 M2 预留参数） |
| `scripts/world/DockBuilder.gd` | 码头木板、桩、栏杆与碰撞 |
| `scripts/world/StaticDuskLighting.gd` | M1 固定暮色光照（Autumn_Dusk_Clear），M2 由 EnvironmentDirector 取代 |
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
| `scripts/core/WorldLayout.gd`、`WorldTerrain.gd`、`PhysicsLayers.gd` | 布局数据读取、解析式地形高度函数、物理层常量 |
| `scripts/systems/*.gd` | WorldClock / SeasonController / WeatherController / EnvironmentDirector / AudioDirector / SaveManager 的**接口占位**（未运行，标注所属里程碑） |
| `tests/TestRunner.tscn` | 自动检查（QA-01、QA-02、QA-10 等 16 项） |
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
- 自动检查与截图工具

## 未实现（按里程碑）

- **M2**：世界时钟、四季、6 类天气、昼夜光照（`scripts/systems/` 中只有接口占位）
- **M3**：音频 Bus 与环境音、壁炉 / 灯 / 沙发交互
- **M4**：存档读档、完整设置菜单、画质档位、Windows 导出、性能统计（尚未测帧率，不宣称 60 FPS）
- **M5**：NPC、联机（只保留了 entity_id、统一交互契约与区域事件）
- 季节换装：树冠颜色、阔叶树夏季模型、地表季节色和积雪参数已经留好接口，切换逻辑属于 M2

## 素材与版权

外部素材全部登记在 [assets/licenses.csv](assets/licenses.csv)，均为 CC0（Kenney、Poly Haven）或本项目自制（Blender 脚本生成的木屋）；自动检查会核对 `assets/imported/` 下每个文件都有登记。规格中的两张用户参考图仅作私有视觉参考，不进入本仓库（`.gitignore` 已排除 `assets/references/`）。
