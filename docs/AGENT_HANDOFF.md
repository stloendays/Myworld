# Dusk Lake | Claude Code / Codex 实施指令

> 请先阅读 `DEVELOPMENT_SPEC.md`，它是需求唯一真相（single source of truth）。本文件是 AI 编程代理的任务启动说明，不代替主规格书。

## 工程边界

- Godot **4.7.2 Standard**（GDScript，Windows 单机，Forward+ 优先）。
- **250 × 250 m** 连续地图，X/Z ∈ [-125, +125]，北为 -Z。
- `Main.tscn` 载入同一世界内的室外 / 室内；进入木屋**不得** teleport、加载场景或黑屏。
- 优先可玩的灰盒原型，再导入外部素材；所有下载来源和许可必须进入 `assets/licenses.csv`。
- 第一人称控制优先；四季、天气、音频独立；为 NPC 和未来多人保留稳定 ID、导航区域与事件接口。
- 两张原始参考图位于 `assets/references/`，仅作为私有视觉参考；不默认提交至公开仓库。

## Task A | 从零创建可运行工程（只做 M0 + M1）

**把下面整段复制给 Claude Code / Codex：**

```text
请阅读同目录下的 DEVELOPMENT_SPEC.md 和 ASSET_SOURCES.csv。你是 Godot 4.7.2 资深技术美术和游戏客户端工程师，项目是 Dusk Lake。

只实现里程碑 M0、M1：
1. 新建 Windows Godot 4.7.2 Standard + GDScript 项目，清晰拆分 scenes、scripts、data、assets、docs、tests。
2. 地图坐标固定 X/Z [-125,125] 米，World.tscn 内创建最小可游玩的地形、低模针叶林、湖泊占位、湖边码头、带有门和可进入室内空间的 A-Frame 木屋。
3. CharacterBody3D 第一人称：WASD、鼠标环视、Shift 奔跑、Esc 菜单、E 射线交互；默认 FOV 75 度，控制器独立于地图。
4. 木屋必须与室外在同一个连续场景 / 坐标系，不能加载新关卡、瞬移或通过场景切换做室内。
5. 为后续季节、天气、环境音、存档、NPC 导航预留模块文件 / 协议，但本轮不要把它们伪装成已完成，不要实现联网。
6. 允许程序生成占位几何体，但不假设已有任何第三方模型；未来资产通过 GLB 导入替换。
7. 创建 README，标注启动、调试、按键以及如何验证坐标和连续性；输出每个文件的用途。
8. 你必须运行 Godot 的导入与脚本检查（若本机命令可用）；失败要修复。不具备运行条件则说明未验证，给出 Windows GUI 验证步骤。

交付时返回：文件树、已实现清单、未实现清单、运行命令、验收用例 QA-01/02 的结果和已知问题。不要一次完成 M2-M5。
```

## Task B | M2 四季 / 天气 / 日夜系统

当前一阶段验收通过后，再派发：

```text
基于 DEVELOPMENT_SPEC.md 第 05 章，实现 WorldClock / SeasonController / WeatherController / EnvironmentDirector / WorldState，季节与天气独立。预置四季、六类天气、昼夜光照及测试界面，支持 Autumn_Dusk_Clear、Autumn_Night_HeavyRain、Winter_Morning_Snow、Spring_Fog。实现有淡入淡出过渡的天气切换；冬季只下雪，其他三季支持下雨，室内不能显示降水粒子。配置数据独立于场景脚本。提供 QA-03/04/06 的测试记录与截图。
```

## Task C | M3 音频 / 交互

```text
基于 DEVELOPMENT_SPEC.md 第 06/07 章添加 AudioDirector 和音区，配置 AMB_OUTDOOR、AMB_WEATHER、AMB_INDOOR、FOLEY、MUSIC、UI。森林风声、湖水、雨、壁炉支持独立循环与空间声源，进入室内时室外雨声平滑衰减 1–2.5 秒；窗外雨仍可见。添加开门、开灯、炉火和坐下的基本交互。没有许可证的音效用静音占位并写明 TODO。验证 QA-05 和交互物重访的稳定性。
```

## Task D | M4 存档 / 优化

```text
实现 user://saves/ 的 WorldState V1 JSON 存档、升级路径、设置菜单和 Windows 导出。恢复季节、时间、天气、玩家位置、门和壁炉状态。逐项核验 assets/licenses.csv，提供 QA-07/08/09/10 记录。未经测试不得宣称达到 60 FPS。
```

## 非功能性验收清单

- [ ] 代码可以在指定版本 Godot 里导入且无脚本解析错误。
- [ ] 关卡进入木屋无场景切换或瞬移。
- [ ] 季节与天气状态不重复实现，世界状态能保存和复现。
- [ ] 场景节点不通过绝对路径互相紧耦合。
- [ ] NPC 接口有文档，但 MVP 不包含虚假的“AI NPC”承诺。
- [ ] 许可状态不确定的素材不得提交公开仓库。
