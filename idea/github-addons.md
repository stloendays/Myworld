# 喜欢的 Godot 开源项目｜技术候选清单

> **仅记录候选及原始来源。没有将插件源代码、第三方资源或许可证文件复制到仓库；没有完成 Godot 4.7.2 的集成测试。** 接入前应确认当时的版本、许可证和依赖。

## A. Lente — Godot Photo Mode

- 项目：https://github.com/mbiggeri/lente-godot-photo-mode
- 用途：独立摄影模式；相机位移／转动、景深、曝光、画面风格、超采样截图、游戏内图库。
- 适配 Dusk Lake：在湖畔按 `P` 进入摄影；照片保存在 `user://photos/`，可在木屋相框或旅行手账中展示。照片与世界时间／天气的元数据由游戏自己维护。
- 参考仓库 README（查询于 2026-10-21）：Godot 4.x 插件，提供 `addons/lente` 目录和 `LentePhotoMode` 节点；按键默认 `P`，退出可能与 `Esc` 冲突，应与现有 PauseMenu 协调。
- 注意：该插件使用自己的拍照镜头／UI、暂停状态和按键，应先独立试验回退相机、触发后鼠标焦点恢复。仓库较新，兼容性未经过本项目验证。

## B. Beehave — Behavior Trees

- 项目：https://github.com/bitbrain/beehave
- 用途：基于行为树实现野生动物和未来 NPC 的日程行为，比如巡游、觅食、下雨避雨、看到玩家时逃走。
- 适配 Dusk Lake：先让 1 只狐狸或 1 只鹿在限定区域内运行 3–4 种状态（Idle、Wander、AvoidPlayer、Shelter）；读取 `WorldClock` 和 `WeatherController` 时只通过统一状态 API，不复制天气逻辑。
- README 提供 Godot 4.x 分支和 4.5+ 对应插件版本；选定版本后仍须在项目 Godot 4.7.2 实测。
- 注意：复杂动物行为可能适用行为树，但 **3 状态以内的简单对象可直接使用 GDScript 状态机**，不必提前增加插件依赖。NPC 仍属于原计划 M5 后期范围。

## C. Dialogue Manager 4

- 项目：https://github.com/nathanhoad/godot_dialogue_manager
- 用途：脚本式分支对话、条件判断、人物对话气泡、对话状态；将来可配合湖边守护者／旅人 NPC 或书信选择。
- 适配 Dusk Lake：先实现普通信件阅读 UI；只有当故事出现多选项分支、NPC 对话、事件条件时，再用 Dialogue Manager 4 做概念验证。
- README（查询于 2026-10-21）写明 **Godot 4.6+**。需选定有许可证的固定发行版本，独立验证与当前 Godot 4.7.2、中文 UI、暂停机制的兼容性。
- 注意：对话系统不应成为世界状态单一权威；剧情 flag／已读信件仍归 `WorldState` 并由 `SaveManager` 存档。

## 引入插件的共同检查清单

- [ ] 在临时测试分支／独立场景做 POC，先不要覆盖现有 `Main.tscn`、`Player.tscn`。
- [ ] 核对插件**确切 release/tag/commit**、完整依赖、许可证全文和资源授权；候选仓库信息不是法律保证。
- [ ] 在 `docs/` 或适当的 third-party notice 中记录项目名称、URL、版本、MIT 等适用许可证及是否修改；导入的外部资产按 `assets/licenses.csv` 项目规则登记。
- [ ] Godot 4.7.2：`godot --headless --path . --import`、`res://tests/TestRunner.tscn`；画面相关再执行截图和基准测试。
- [ ] 测试与 `GameSettings` 按键、`EventBus` 信号、`WorldState` 状态／`SaveManager` 存档、摄像机和 `Esc` 菜单的冲突。
- [ ] 如果插件过重、维护不足或不兼容，改为轻量自实现，而不是为了接入插件修改全局架构。

## 与三个玩法的关系

| 玩法 | 首先需要的内容 | 插件何时有用 |
| --- | --- | --- |
| 木屋生活 | 现有 `Interactable`＋M3 `AudioDirector` | **Lente** 照片墙可后接；另两者非必需 |
| 神秘信件 | 数据驱动信件＋阅读 UI＋存档 | **Dialogue Manager 4** 在加入 NPC 分支对话时再引入 |
| 独木舟探索 | 划船运动与上／下船交互 | 三个插件都不是必需（船载镜头可选其他镜头插件） |
| 野生动物（额外可能性） | 简单状态机与导航试验 | 行为复杂后评估 **Beehave** |
