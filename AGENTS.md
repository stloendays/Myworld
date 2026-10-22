# AGENTS.md — Dusk Lake

给参与本仓库的 AI 编程代理（Claude Code / Codex）的共享规则。

- 需求唯一来源：`docs/DEVELOPMENT_SPEC.md`；阶段指令：`docs/AGENT_HANDOFF.md`。**一次只做一个里程碑**，验收通过再进下一个。
- 引擎固定 Godot 4.7.2 Standard + GDScript。改动后必须运行：
  - `godot --headless --path . --import`（无解析错误）
  - `godot --headless --path . --fixed-fps 60 res://tests/TestRunner.tscn`（退出码 0）
  - 涉及画面时运行 `devtools/CaptureShots.tscn` 并亲自查看截图。
- 世界坐标与位置只写在 `data/world/world_layout.json`，地面高度只用 `WorldTerrain.height_at()`。不要在场景脚本里硬编码坐标。
- 室内外必须在同一场景、同一坐标系；禁止任何场景切换或传送式进屋。
- 季节与天气是两个独立系统；状态以 `WorldState` 为准，`EventBus` 只发通知。改存档字段必须升级 `schema_version` 并写迁移。
- 交互对象必须有稳定 `uid`，角色有 `entity_id`，区域有 `zone_id`；不要用节点路径存档或同步。
- 未完成的功能不得写成已完成；接口占位文件要标明所属里程碑。
- 本仓库是**公开仓库**：不要提交 `assets/references/` 下的用户参考图，不要提交许可未核验的第三方素材。每个导入的外部文件都要登记到 `assets/licenses.csv`。
- 美术：外部模型/贴图放 `assets/imported/`，材质统一走 `scripts/art/ArtMaterials.gd`（按材质名替换），不要在各脚本里各自新建贴图材质。木屋模型改 `devtools/blender/build_cabin.py` 后重新导出，尺寸常量要与 `Cabin.gd` 碰撞保持一致。
- 渲染相关改动后用 `devtools/Benchmark.tscn` 复测帧率与显存，并写进文档。
- 调试不打扰用户：`res://devtools/` 场景启动后窗口自动挪到屏幕外、不拿焦点、不抓鼠标、不跟随玩家的全屏设置（`GameSettings._park_dev_window()`）。命令加 `--position 100000,100000`，让启动后挪走之前的 2–4 秒只在屏幕右下角露一角。**调试时绝不开全屏**（不加 `-f` / `--fullscreen` / `--maximized`）。改鼠标模式一律先判断 `GameSettings.can_grab_mouse()`。用户想看窗口时才设 `DUSK_SHOW_WINDOW=1`。
- 提交信息用英文祈使句；用户沟通用中文。
