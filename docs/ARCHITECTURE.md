# 架构说明（M1）

## 坐标与单位

- 单位米；地面平面 X/Z ∈ [−125, 125]；Y 向上；**北 = −Z**；朝向角 0° = 北，顺时针为正。
- 地形网格覆盖 ±128 m（257×257 采样，Jolt 高度场最优尺寸），可活动区由 108–125 m 之间的陡坡自然封闭。
- 所有位置来自 `data/world/world_layout.json`，代码通过 `WorldLayout` 读取，通过 `WorldTerrain.height_at(x, z)` 取地面高度。网格、碰撞、树木、出生点都调用同一个高度函数，保证一致（自动检查实测偏差 ≤ 0.035 m）。

## 场景组成

```
Main (Main.gd)
├── World
│   ├── Lighting   StaticDuskLighting   M1 固定暮色；M2 由 EnvironmentDirector 取代
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
├── HUD / PauseMenu / DebugOverlay
```

木屋是主场景里常驻的真实子场景；进屋只是角色走进一个 `Area3D`。工程中没有任何场景切换调用（自动检查会扫描 `scripts/`）。

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
| `WorldState`（Autoload） | M1 已实现部分 | 可交互物状态（按 uid）、角色所在区域（按 entity_id）；M2/M4 扩展时间、季节、天气与存档字段 |
| `EventBus`（Autoload） | M1 已实现部分 | 只发通知不存状态 |
| `GameSettings`（Autoload） | M1 已实现 | FOV、灵敏度、按键表、UI 中文字体主题 |
| `InteractionSystem` / `Interactable` | M1 已实现 | 统一 `interact(actor, target)`；子类提供提示、状态、`apply_state()` |
| `WorldClock` / `SeasonController` / `WeatherController` / `EnvironmentDirector` | M2 接口占位 | 见 `scripts/systems/` 文件头的计划接口 |
| `AudioDirector` | M3 接口占位 | 订阅区域事件做室内外混音 |
| `SaveManager` | M4 接口占位 | `user://saves/` 版本化 JSON |

已使用的事件：`zone_entered(zone_id, actor_id)`、`zone_exited`、`interactable_state_changed(uid, state)`、`interaction_prompt_changed(text)`。
预留事件（目前没有发送方）：`time_changed`、`season_changed`、`weather_transition_started`、`weather_changed`、`save_loaded`。

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

- **太阳方位**：为还原参考图 01 的构图（从木屋/码头望向湖对岸的落日），M1 把暮色太阳放在湖对岸，方位角 64°（从北顺时针）。M2 改为按时间计算，方位由配置决定。
- **涉水**：MVP 不做游泳，用沿 0.7 m 等深线的水下挡墙限制，码头处压低到甲板以下。
- **码头栏杆**：入水段加栏杆，碰撞比可见栏杆高 0.45 m，防止跳过后落入深水。
- **湖面倒影**：屏幕空间反射负责近处（码头、岸边），远岸树林由湖心上方 2 m 处只拍一次的盒投影反射探针提供；水面在可见层 2，不进入探针。反射图集只开 2 个槽（`reflection_count=2`），避免默认 64 槽占用数 GB 显存。
- **木屋定位**：木屋在 `_enter_tree()` 中按布局定位。门板是 AnimatableBody3D，进入场景树后不会跟随父节点的后续移动，所以必须先定位再让子节点进树。
