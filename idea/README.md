# Dusk Lake · Idea Lab（游戏创意库）

> 记录日期：2026-10-21 ｜ 状态：**喜欢／待评估**，不是已承诺的开发需求，也不代表功能已经实现。
>
> 本目录属于创意备忘；**正式需求仍以 [docs/DEVELOPMENT_SPEC.md](../docs/DEVELOPMENT_SPEC.md) 为准**。一旦决定实施某个创意，先明确范围、设计测试，再更新正式规格与里程碑。Claude Code / Codex 不应把本目录所有想法一次性实现。

## 已选中的玩法创意

| 创意 | 体验目标 | 文档 | 粗略依赖 |
| --- | --- | --- | --- |
| 木屋生活系统（Cabin Life） | 真正能在木屋中生活、休息和布置自己的空间 | [cabin-life.md](cabin-life.md) | M3 交互／音频；M4 存档 |
| 神秘信件与温柔剧情（Gentle Mystery） | 非强制探索、通过书信了解湖畔的小故事 | [gentle-mystery.md](gentle-mystery.md) | 现有 Interactable；M4 持久化 |
| 独木舟探索（Canoe Exploration） | 驾舟看湖景，寻找隐藏岸线 | [canoe-exploration.md](canoe-exploration.md) | 现有码头／湖泊、船与玩家状态 |
| 私人联机与玩家自建房（Player-hosted Co-op） | 任意玩家的电脑都可当房主，最多 4 人共享湖畔；未来正式 Windows 安装版内置建房和加入功能 | [multiplayer-player-hosted.md](multiplayer-player-hosted.md) | 角色外观／M4 存档／M5 网络改造 |

## 喜欢的 GitHub 开源项目（只记录，尚未引入）

- **[Lente — Godot Photo Mode](https://github.com/mbiggeri/lente-godot-photo-mode)**：照片模式、镜头控制、滤镜和相册；适合“旅行手账／木屋照片墙”。
- **[Beehave — Behavior Trees](https://github.com/bitbrain/beehave)**：动物／未来 NPC 的行为树；不需要为简单交互立即引入。
- **[Dialogue Manager 4](https://github.com/nathanhoad/godot_dialogue_manager)**：未来 NPC 和剧情的分支对话；信件阅读本身不需要对话插件。

技术匹配、接入策略、开源授权与测试见 [github-addons.md](github-addons.md)。

## 建议体验主线

**在木屋醒来 → 沿岸发现旧信 → 驾独木舟到隐秘湖湾 → 用摄影模式留下记忆 → 回屋读信、点壁炉、把照片展示在相框。**

它们服务同一条低压力体验闭环：**探索 → 发现 → 留下回忆 → 回家**。不得把世界变成需要赶时间的生存任务游戏。

## 与现有工程的关系

- 已有 M0/M1 250×250 m 无缝世界、码头、湖、A-frame 木屋和第一人称交互。木屋内已有家具、铸铁炉、收音机等美术资产，但大部分生活互动尚未实现。
- M2 时间／四季／天气、M3 AudioDirector 与部分生活交互、M4 SaveManager 仍须以代码和验收确认。不要将创意文档当作功能状态依据。
- 保留稳定 `uid`／`entity_id`／`zone_id`，`WorldState` 是状态权威，`EventBus` 负责通知；不允许为了新玩法打破室内外连续场景。
- **公开仓库安全要求**：不提交未确认许可的截图、第三方模型、素材。正式集成任何插件时锁定具体版本并保留相应开源许可文件。

## 未来 Windows 安装包的联机目标（新增）
- **确定的产品方向：** 在面向朋友发布的正式 Windows 安装版里，默认附带创建私人房间、加入朋友房间和单人模式。所有人的客户端都能充当房主，**无需单独下载服务端程序**。
- **首发最低能力：** 玩家托管式 Listen Server，房主权威管理共享世界、上限 4 人、各自角色外观和访客权限；异地连接途径应经过真实测试。
- **不混淆的限制：** 房主退出后房间默认结束。自动房主迁移、无人在线仍运行的专服、无需外部网络配置的房间码／Relay 是后续能力；Windows 游戏内置建房 ≠ 自带公网 NAT 穿透服务。
- **尚未实现：** 本项是安装包规划与以后版本的发行验收要求，不代表现有仓库已经有网络代码或安装包。详细见 [multiplayer-player-hosted.md](multiplayer-player-hosted.md)。

## 实施提示

[roadmap.md](roadmap.md) 记录推荐优先级与最小验收。想法可以独立评估，**不要自动启动开发、安装插件或修改正式规格**。
