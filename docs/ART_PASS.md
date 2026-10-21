# 正式美术第一轮（2026-10-21）

目标：把 M1 的程序化灰盒换成规格第 02、11 章的风格化写实素材，地图、坐标、碰撞与 M1 验收行为保持不变。

## 换了什么

| 部分 | 灰盒 | 现在 | 来源 |
|---|---|---|---|
| 针叶林 | 一种程序化圆锥树 | 12 种 Kenney 针叶树（高 3.5–18 m）+ 4 种秋色阔叶树；林地越稀疏阔叶树越多；树冠颜色按实例变化 | Kenney Nature Kit（CC0） |
| 岩石 | 拉伸球体 | 9 种 Kenney 岩石，石面贴 rock_face_03，顶部苔藓；地图边缘山脊上另有 90 块大岩壁 | Kenney + Poly Haven（CC0） |
| 地被 | 无 | 草丛、灌木、南部草甸的野花、林下蘑菇、树桩倒木、小石块、浅水睡莲，共 7731 个实例，40 m 区块按距离隐藏 | Kenney（CC0） |
| 地表 | 顶点纯色 | 五层 PBR 混合（草地 leafy_grass、林下落叶 forest_leaves_04、土路 rocky_trail、陡坡岩石 rock_face_03、湖岸 brown_mud_rocks_01），按林地密度、坡度、步道、水深分配 | Poly Haven（CC0） |
| 湖面 | 透明色块，只反射天空 | 不透明水面 + 屏幕空间反射（码头等近处物体）+ 湖心盒投影反射探针（远岸树林、山脊），按水深变色 | 自制 shader |
| 天空 | 程序化天空 | 自定义天空 shader：渐变、太阳盘与光晕、飘动薄云；SSAO、雾中太阳散射 | 自制 shader |
| 木屋 | 代码拼的方块 | Blender 脚本建模：17 行石板瓦、封檐板、椽子与系梁、三角窗窗框、竖向护墙板、逐块门廊木板与坡道、铸铁炉与烟囱帽、门廊灯；石板瓦、墙板、地板、木梁、石基都用 PBR 贴图 | `devtools/blender/build_cabin.py` + Poly Haven |
| 门 | 方块 | Blender 门板（rough_pine_door 整张贴图）+ 金属把手 | 同上 |
| 家具 | 方块 | Kenney L 形沙发（米白针织面料）、茶几、地毯、两个书架和书、落地灯与台灯、扶手椅、边几收音机、盆栽；门廊长椅与门垫；屋后柴堆 | Kenney Furniture Kit（CC0） |
| 码头 | 纯色木板 | weathered_planks 木板、stained_pine 桩与栏杆；岸边独木舟与船桨 | Poly Haven + Kenney |

所有素材都登记在 `assets/licenses.csv`；Poly Haven 贴图的 md5 在 `assets/imported/textures/manifest.csv`，可用 `devtools/fetch_polyhaven.ps1` 重新下载核对。

## 怎么做的

- **材质库** `scripts/art/ArtMaterials.gd`：Poly Haven 贴图按官方标注的真实尺寸平铺（例如石板瓦 3 m、地板 1.7 m）；Kenney 模型原本是平涂卡通色，按材质名（`leafsDark`、`woodBark`、`carpet`……）换成本项目的配色或贴图；木屋 GLB 的材质名为 `M_*`，同样按名替换。
- **季节接口**：树冠、草叶的颜色全部来自 MultiMesh 实例颜色；阔叶树记录了夏季模型（`tree_oak` 等）；地形 shader 有 `season_tint`、`snow_amount`、`wetness`。M2 只需改参数，不用重建场景。
- **木屋模型**由脚本生成，尺寸常量与 `Cabin.gd` 的碰撞一致；UV 以米为单位、沿构件长边，所以木纹方向正确。Blender 源文件在 `assets/source/cabin_aframe.blend`，可以手工继续修改后重新导出。
- **湖面倒影**：Godot 的屏幕空间反射在远距离、掠射角下几乎采不到远岸，所以在湖心水面上方 2 m 加了一个只拍一次的盒投影反射探针，水面本身放在单独的可见层上不被拍入。

## 验证

- 导入无错误；`tests/TestRunner.tscn` **16/16 通过**（新增 QA-10：`assets/imported/` 下 131 个文件全部有许可登记）。QA-01、QA-02 的步行与开门数据与灰盒版一致，碰撞没有变化。
- `devtools/Benchmark.tscn`，1920×1080、MSAA 2×、关闭垂直同步，RTX 5060 Laptop：

| 机位 | 帧率 | 帧时 | 绘制调用 | 显存 |
|---|---|---|---|---|
| 湖岸出生点 | 223 FPS | 4.5 ms | 620 | 808 MB |
| 码头望木屋 | 227 FPS | 4.4 ms | 1047 | 840 MB |
| 木屋室内 | 177 FPS | 5.7 ms | 742 | 846 MB |
| 北部林道 | 213 FPS | 4.7 ms | 768 | 846 MB |

这是这台机器上的实测，不是性能目标验收（QA-09 属于 M4）。

## 截图

| | |
|---|---|
| ![](screenshots/m1_01_spawn_dusk.png) 湖岸出生点 | ![](screenshots/m1_02_lake_to_cabin.png) 码头望向木屋 |
| ![](screenshots/m1_03_cabin_front.png) 木屋正立面 | ![](screenshots/m1_04_cabin_interior.png) 室内望向三角窗 |
| ![](screenshots/m1_05_interior_stove.png) 沙发、铸铁炉与书架 | ![](screenshots/m1_09_lake_reflection.png) 码头尽头的湖面倒影 |
| ![](screenshots/m1_06_north_trail.png) 北部针叶林步道 | ![](screenshots/m1_07_viewpoint.png) 西北观景点 |

## 已知问题

- Kenney 模型是低多边形风格，树木与家具的轮廓仍偏简洁；地表、木屋和水面已是 PBR 质感，整体是“低多边形造型 + 写实材质”。如果要更写实的树木，下一步可以评估 Quaternius 或自建树模型（需逐包核验许可）。
- 反射探针只在启动时拍一次；M2 加入昼夜和天气后，需要在光照变化时调用 `LakeBuilder.refresh_reflection()`。
- 西北观景点被近处树冠挡住一部分湖景。
