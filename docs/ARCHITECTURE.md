# 架构说明（M1）

## 坐标与单位

- 单位米；地面平面 X/Z ∈ [−125, 125]；Y 向上；**北 = −Z**；朝向角 0° = 北，顺时针为正。
- 地形网格覆盖 ±128 m（257×257 采样，Jolt 高度场最优尺寸），可活动区由 108–125 m 之间的陡坡自然封闭。
- 所有位置来自 `data/world/world_layout.json`，代码通过 `WorldLayout` 读取，通过 `WorldTerrain.height_at(x, z)` 取地面高度。网格、碰撞、树木、出生点都调用同一个高度函数，保证一致（自动检查实测偏差 ≤ 0.035 m）。

## 场景组成

启动时的主场景是 `scenes/boot/Boot.tscn`（`BootLoader`）：显示加载画面（`LoadingScreen`），后台线程读当前世界的场景（`worlds.json → current`），实例化后加到根节点下并设为 `current_scene`，在加载画面后面渲染 40 帧编译着色器，再交给开场过场（`IntroCutscene`，镜头在 `world_layout.json → intro`）和大厅菜单，自己释放。直接运行 `Main.tscn`（编辑器、自动检查、截图工具）时不经过这一步，大厅菜单照旧自己弹出。

```
Main (Main.gd)
├── Systems (ClimateSystem)              预设 / 跳季 / 改时刻 / 改天气的统一入口
│   ├── WorldClock                       推进时间（一天 = 现实 48 分钟）
│   ├── SeasonController                 由日期推出季节
│   └── WeatherController                按季节权重抽天气、过渡、种子
├── World
│   ├── Environment EnvironmentDirector  太阳月亮、天空、雾、环境光、湿润积雪、降水强度、植被季节色
│   ├── Precipitation                    雨雪粒子 + 跟随相机的高度场碰撞（屋顶下无雨雪）
│   ├── Terrain    TerrainBuilder       高度场网格 + HeightMapShape3D，terrain.gdshader 五层 PBR
│   ├── Lake       LakeBuilder          水面 + 反射探针 + 涉水上限
│   ├── Forest     ForestBuilder        Kenney 树木 / 岩石 MultiMesh + 碰撞
│   ├── GroundCover GroundCoverBuilder  地被（40 m 区块，按距离隐藏）
│   ├── Dock       DockBuilder
│   ├── Backdrop   DistantBackdrop      远山与地图外台地
│   └── Zones      ZonesBuilder         室外区域触发器
├── Cabin (Cabin.gd)                     世界坐标 (−69, 2.4, 37)
│   ├── FrontDoor  InteractableDoor     uid = cabin_front_door（门板 door_leaf.glb）
│   └── Generated  cabin_aframe.glb + Kenney 家具 / 灯光 / 碰撞 / 室内区域 cabin_interior
├── Player (FirstPersonController)       entity_id = player_local
│   ├── Body (CharacterModel)            方块人物：6 部位 × 7 外观插槽 + 4 挂点，渲染层 player_body
│   └── Head ── InteractRay / CameraBoom(SpringArm3D) ── Camera3D   V 切换第一/第三人称
├── HUD / PauseMenu（含人物外观面板）/ DebugOverlay / DevPanel（F2 开发者模式）/ Minimap（M）
├── ChatBox（Main 启动时创建）           左下角聊天框与 / 命令
├── ActionBar（G 动作轮盘，快捷键 1–4，F12 拍照）/ WorldMap（Tab 世界地图）
├── Cave (Cave.gd)                       北缘岩脊里的图腾山洞：洞道与岩丘、石厅、老图腾 CaveTotem、篝火、尽头光门
├── StoneCottage (StoneCottage.gd)       南部草地的石头小屋（CottageDoor 三环转锁；读完三封信能进，屋里是室内区域 cottage_interior）
├── StarField (StarField.gd)             夜空里的五个星座，跟着相机走
├── Streams (Streams.gd)                 小溪水面、瀑布水雾、溪边石头芦苇、木板桥与原木桥（河床、裂谷本身是地形沟槽）
├── DialoguePanel / JournalPanel（Main 启动时创建）  图腾对话框；J 旅行日志与左上角任务追踪
```

木屋是主场景里常驻的真实子场景；进屋只是角色走进一个 `Area3D`。工程中没有任何场景切换调用（自动检查会扫描 `scripts/`）。

换世界（`WorldTravel`）也不调用切场景函数：当前世界的根节点（`world_root` 组：`Main` 或 `World02`）在原父节点下被整个释放，清掉 `ArtMaterials` 缓存后，再在后台线程读下一个世界并放回同一个父节点。两个世界任何时候都不同时在内存里；Autoload（WorldState、QuestLog 等）跨世界保留。

`World` 下的生成器都是 `@tool` 脚本：在编辑器里打开场景也能看到地形、树木和木屋；生成的节点放在各自的 `Generated` 子节点下，不写入 `.tscn`。碰撞只在运行时生成。

## 物理层

| 层 | 值 | 内容 |
|---|---|---|
| world | 1 | 地形、树干、岩石、建筑、码头 |
| actors | 2 | 玩家（以后的 NPC、其他玩家） |
| interactable | 4 | 门等可交互物 |
| water_limit | 8 | 湖中涉水上限挡墙 |
| terrain | 16 | 仅地形（高度查询射线用） |

玩家碰撞掩码 = world + interactable + water_limit；交互射线掩码 = world + interactable（墙后的物体点不到）。

## 模块职责与事件

| 模块 | 状态 | 职责 |
|---|---|---|
| `WorldState`（Autoload） | 已实现 | 日期时间、季节覆盖、天气与过渡进度、种子、地面积雪/湿润、可交互物状态、角色区域、探索发现、载具、任务与图鉴、收集品；`snapshot()` / `migrate()` / `restore()`（存档版本 4：加入本局规则、收集品、玩家所在世界与位置） |
| `EventBus`（Autoload） | 已实现 | 只发通知不存状态 |
| `GameSettings`（Autoload） | 已实现 | FOV、灵敏度、按键表、UI 中文字体主题 |
| `PlayerProfile`（Autoload） | 已实现 | 本地玩家外观，存 `user://appearance.json` |
| `Net`（Autoload，NetworkManager）/ `RemotePlayers` / `LobbyMenu` | M2 扩展已实现 | 房主自建房间（ENet），20 Hz 同步人物位置与身体状态（坐、躺、划船、手势），4 Hz 广播房主的时间天气；门等交互由房主核对距离后广播；欢迎包带房主的本局规则（GameRules），房主改了再广播，访客离开房间后换回自己的；协议版本 3。见 `docs/COOP.md` |
| 界面语言 | 已实现 | 原文中文，`locale/en.po` 英文；`GameSettings.language` = auto（跟随系统）/ en / zh |
| `InteractionSystem` / `Interactable` | 已实现 | 统一 `interact(actor, target)`；子类提供提示、状态、`apply_state()` |
| `WorldClock` / `SeasonController` / `WeatherController` / `ClimateSystem` | M2 已实现 | 只写 WorldState、只发事件，不碰任何画面节点 |
| `EnvironmentDirector` | M2 已实现 | 只读 WorldState，把状态合成为画面；通过 `seasonal`、`precipitation`、`lake_reflection` 组通知各生成器 |
| `CharacterModel` / `CharacterAppearance` / `Wardrobe` | 已实现 | 方块人物、可序列化外观、衣橱目录（`data/characters/`） |
| `PoolHouse` / `WaterVolume` / `UnderwaterOverlay` | 已实现 | 泳池馆与地下水族馆（地形 `pits` 挖坑、`keepouts` 避让植被与动物）；可游泳水体（`water_volume` 组，玩家按身体中部所在水体切换游泳）；相机在水面以下时的滤镜 |
| `FaunaSpawner` / `Animal` / `FishSchool` / `FaunaData` | 已实现 | 小动物按 `data/animals/species.json` 生成；出没规则只读 WorldState；每只有稳定 `entity_id`；鱼群只在缸的 AABB 内游 |
| `ChatBox` / `ChatCommands` | M2 扩展已实现 | 聊天框：订阅 `weather_changed`、`season_changed` 写系统消息；命令只调用 `ClimateSystem`、`WorldTerrain` 等已有入口，不存世界状态；聊天名字存 `user://chat.json` |
| `CabinLife` / `InteractableToggle` / `Seat` / `Bed` | 已实现 | 木屋生活交互，状态按 uid 记在 WorldState |
| `Canoe` / `Exploration` | 已实现 | 独木舟（自算运动，位置记在 `WorldState.vehicles`）；湖上探索点（`WorldState.discoveries`，存档 v2） |
| `ActionBar`（动作轮盘）/ 控制器 `do_emote()` / `CharacterModel` 姿势与手势 | 已实现 | 动作：`ground_sit`、`lie` 是姿势（身体放低或放倒，眼睛跟着移动），`wave`、`dance`、`clap` 是叠加在站姿上的手势；状态在 `FirstPersonController.emote` |
| `WorldRegistry` / `WorldMap` | 已实现 | `data/worlds/worlds.json` 列出所有世界（status、根场景、布局数据、到达位置）；地图画当前世界（湖畔读布局，别的世界问 `MiniWorld`）；`WorldRegistry.enter()` 把能去的世界交给 WorldTravel |
| `MiniWorld` / `World02`（云海浮岛）/ `World03`（琥珀沙丘） | v0.5 | 湖畔以外的世界的共用底座：按数据文件建天空雾光、地形（解析高度函数 → 网格 + 碰撞）、卷轴、收集品、探索点、光门、玩家与全套界面；掉出世界回到最后站稳的地方；`height_at()`、`map_markers()`、`draw_map()` 供小地图、世界地图、罗盘、自动检查使用。天气季节系统只在湖畔，这两个世界的光照固定（太阳不动，阴影不会爬） |
| `GameRules`（Autoload） | v0.5 | 新建游戏的玩法与设定（23 个选项、5 种模式、9 个预设）：只记规则、回答查询；时钟、季节、天气、小动物、仙境、任务图鉴、HUD、体力、夜晚亮度各自来问；开局一次性的（季节时刻天气、出生世界与出生点）由 `apply_start()` 设 |
| `CompassBar` / `PhotoList` | v0.5 | 罗盘条与体力条；摄影清单（`data/photo/subjects.json`，F12 拍照时认出画面中央的对象，记进 `WorldState.journal.photos`） |
| `World04`（亚特兰蒂斯）/ `LightStatue` / `MantaHandle` / `ShapedWater` / `AtlantisRing` | 亚特兰蒂斯 | 世界四：同心环城（`height_at` 按环给高度，石堤是缓坡）、气泡穹顶（`ShapedWater`：整片海减去穹顶球、环形水道），海里没有浮力、游速 ×1.7；氧气、光束谜题（雕像朝向按 uid 存 `dir:N`，每次转动重追光路）、洋流和蝠鲼（`RailRide`）；这里有自己的时钟，光照随时刻变；`AtlantisRing` 是湖畔海洋大缸底的入口（游过环面就去） |
| `RailRide` | 亚特兰蒂斯 | 沿一条 Curve3D 把玩家带着走（`FirstPersonController.start_rail`，`is_riding()` 为真），头 0.4 秒从站的地方平滑接上路线；可以带一个跟着走的模型（蝠鲼） |
| `Play`（Autoload）/ `PlayActivities` / `CookPot` / `CookingPanel` / `TrophyCabinet` | 更多玩法 | `Play` 读 `data/play/*.json`，管规则开关与联机限制、鱼、菜与效果倍率、宝藏位置（按种子）、挑战成绩与奖牌、成就；`PlayActivities` 是每个世界里的操作（R 钓鱼、Q 打水漂、B 挖宝、挑战金环）；水面由世界根节点的 `water_at()` 回答 |
| `WorldTravel`（Autoload） | M2 扩展已实现 | 跨世界旅行：渐黑 → 卸载当前世界 → 清缓存 → 后台线程加载 → 实例化 → 渐亮；记录当前世界与来时的世界；联机时不能离开 |
| `BootLoader` / `LoadingScreen` / `IntroCutscene` | 已实现 | 启动流程、共用的加载画面（启动与跨世界旅行）、开场过场；`BootLoader.active` 期间大厅菜单不自己弹出 |
| `Fade`（Autoload） | 已实现 | 盖在所有界面上的转场黑幕：`fade_out` / `fade_in` / `flash`；启动交接、进出房间、传送时用 |
| `QuestLog`（Autoload）/ `CaveTotem` / `DialoguePanel` / `JournalPanel` | M2 扩展已实现 | 任务内容在 `data/quests/quests.json`；状态在 `WorldState.quests`、图鉴在 `WorldState.journal`；每 0.4 秒只读世界状态检查目标；有变化时请 SaveManager 存档（旧的 `user://journal.json` 作为 v3 存档迁移读取）；规则关掉任务 / 图鉴时不发任务、不记图鉴 |
| `WorldTerrain` 沟槽 / `Streams` | M2 扩展已实现 | `terrain.channels`：小溪（沟底只降不升、跌水成瀑布）与裂谷（陡壁窄底、两头渐浅）；沟底高度首次调用时按原地形算好，碰撞、网格、植被共用；`Streams` 画水面、水雾、桥（桥头引坡贴地） |
| `Cave` / `StoneCottage` / `StarField` | M2 扩展已实现 | 图腾山洞（世界坐标生成的洞道网格与双面三角网碰撞，室内区域 `cave`）；划船人的石头小屋（墙按门洞、窗洞切块，缓坡进门，屋里桌上的星图用 SubViewport 画）；星座（`data/sky/constellations.json`） |
| `Precipitation` 季节飘落物 | 已实现 | 方案在 `data/weather/seasonal_fx.json`（落叶、花瓣、保留的原版红点）；`profile_override` 供开发者面板临时切换 |
| `PaddlerStory` / `LetterSpot` / `LetterPanel` / `CottageDoor` | 世界观落地①（2026-10-26） | 划船人的三封信：内容在 `data/story/letters.json`，湖边两处的位置在 `world_layout.json → letters`，木屋那本旧书在 `CabinLife`（木屋局部坐标）；读过的信记 `WorldState.flags.letters`（本机玩家的记录，不同步），开锁记 `flags.cottage_unlocked`，门的 locked / closed / open 按 uid 存档并联机同步；访客不能开锁；任务目标 `letters`、成就 `paddler_letters` |
| `Cutscene` / `StoryDirector` / `EmberField` | 世界观落地②（2026-10-26） | `Cutscene`：通用过场（`IntroCutscene` 是它的子类），镜头与字幕在 `data/story/cutscenes.json`，锚点由播放方给（湖畔 `StoryDirector.anchor`，其他世界 `MiniWorld.story_anchor`），`cue` 信号在某段开头做事；`StoryDirector`（挂在 Main 下，只读世界状态、写 `WorldState.flags`）：新星座（`StarField.reveal`）、暮烬之夜（`EmberField` + `Precipitation.story_profile = legacy_red_motes`）、图腾讲完最后的故事后的终章（`DialoguePanel` 调 `finale_heard`）、小屋台灯与第四封信；各世界点亮的那一刻由世界自己 `play_story`；设置 `story_cutscenes` 关掉时只给结果；联机访客不放 |
| `AudioDirector` | M3 接口占位 | 订阅区域与天气事件做室内外混音 |
| `SaveManager`（Autoload） | v0.5 已实现 | `user://saves/world.json`（v5，临时文件 + 原子替换）：新建（旧档先备份）/ 继续 / 每 60 s、换世界、退出时自动存；读档后按 uid 恢复门灯、船位，回到存档时的世界与位置；联机做客和自动检查里不写盘 |
| `Interactable` 状态延续 | v0.5 | 读过档或从别的世界回来时，可交互物按 `WorldState.interactables` 里存下的状态摆（不再被新建的初始状态覆盖） |

已使用的事件：`time_changed`、`season_changed`、`weather_transition_started`、`weather_changed`、`zone_entered`、`zone_exited`、`interactable_state_changed`、`interaction_prompt_changed`。
v0.5 新增：`collected`（捡到收集品）、`photo_taken`（摄影清单记下新对象）；`save_loaded` 由 SaveManager 读档后发送。

事件顺序：WorldClock 推进时间 → SeasonController / WeatherController 更新状态 → EnvironmentDirector 每帧读取 WorldState 合成画面。天气随机数只由 `weather_seed` 与 `weather_change_count` 决定，读档后天气序列不变。

## 渲染层与全局着色器参数

| 渲染层 | 值 | 内容 |
|---|---|---|
| world | 1 | 一般场景 |
| water | 2 | 湖面（反射探针不拍它） |
| player_body | 4 | 本地玩家身体（第一人称相机不画，仍投影子） |
| 落叶层 | 8 | 季节落叶/花瓣粒子（不接跟随相机的高度场，只碰建筑的 `Precipitation.leaf_blocker()` 挡板） |
| first_person_arms | 16 | 第一人称的双手（只有第一人称相机画；不投影、不受影） |

全局着色器参数（`project.godot → shader_globals`，由 EnvironmentDirector 每帧写入）：`rain_amount`、`snow_fall`、`snow_cover`、`wetness`、`season_tint`、`wind_strength`、`wind_direction`、`lightning_flash`。

## 为 NPC 与多人预留的部分

- 玩家不是单例：`FirstPersonController` 只有 `is_local_controlled` 的实例读取输入、拥有当前相机；其他实例可以由网络或 AI 驱动。
- `autopilot_enabled / autopilot_direction / look_at_point()` 让非键盘来源（测试、NPC、回放）驱动同一个角色控制器；自动检查就是用它走完 QA-01/02。
- 所有可交互物有稳定 `uid`，角色有稳定 `entity_id`，区域有稳定 `zone_id`；存档与同步都不使用节点路径。
- 步道、码头、门廊坡道、门洞两侧与室内地面均为连续可走的几何，M5 可直接烘焙 `NavigationRegion3D`。

## 美术管线

- 外部模型：Kenney（CC0）GLB 放在 `assets/imported/kenney/`，几何不改，材质在运行时由 `ArtMaterials.for_kenney()` 按材质名替换。
- 贴图：Poly Haven（CC0）1k PBR 放在 `assets/imported/textures/<id>/`，`ArtMaterials.pbr()` 按官方真实尺寸设置平铺。地形把五层贴图合成 `Texture2DArray` 给 `terrain.gdshader`。
- 自制模型：`devtools/blender/build_cabin.py` 生成 `assets/imported/cabin/*.glb`，Blender 材质名 `M_*` 在 Godot 中由 `ArtMaterials.named()` 替换；碰撞仍由 `Cabin.gd` 生成，两边共用尺寸常量。
- 植被分布：`Vegetation` 统一给出林地密度、空地、步道走廊，地形材质、树木、地被因此一致。
- 新增外部文件必须登记到 `assets/licenses.csv`（自动检查 QA-10 会核对）。

## 设计取舍（M1）

- **太阳方位**：为还原参考图 01 的构图（从木屋/码头望向湖对岸的落日），本世界的太阳在湖对岸落下：`seasons.json → sun_set_azimuth_deg = 79°`，太阳从日出到日落沿正弦弧线转 180°，秋季 17:20 正好位于方位 64°、高度约 10°（与 M1 的暮色构图一致）。
- **涉水**：MVP 不做游泳，用沿 0.7 m 等深线的水下挡墙限制，码头处压低到甲板以下。
- **码头栏杆**：入水段加栏杆，碰撞比可见栏杆高 0.45 m，防止跳过后落入深水。
- **湖面倒影**：屏幕空间反射负责近处（码头、岸边），远岸树林由湖心上方 2 m 处只拍一次的盒投影反射探针提供；水面在可见层 2，不进入探针。反射图集只开 2 个槽（`reflection_count=2`），避免默认 64 槽占用数 GB 显存。
- **木屋定位**：木屋在 `_enter_tree()` 中按布局定位。门板是 AnimatableBody3D，进入场景树后不会跟随父节点的后续移动，所以必须先定位再让子节点进树。
