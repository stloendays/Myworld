class_name IntroCutscene
extends Cutscene
## 开场过场：启动加载完成后，镜头先从高处越过湖面看落日（出现标题），再贴着水面沿码头滑向木屋，
## 最后落到玩家眼睛的位置、交还给玩家相机。后两段带两行序幕字幕（湖边的门、山洞里等人的老图腾）。
## 镜头与字幕在 world_layout.json → intro（"player" 表示玩家当前的眼睛 / 视线）；黑边、字幕、跳过由 Cutscene 负责。


static func shots() -> Array:
	return WorldLayout.section("intro").get("shots", [])


## 播放开场过场（可 await）。main 为主场景；没有玩家时直接结束。
func play(main: Node) -> void:
	var list := shots().duplicate(true)
	var title_shot := int(WorldLayout.section("intro").get("title_shot", 0))
	if title_shot < list.size():
		(list[title_shot] as Dictionary)["title"] = {"text": "Dusk Lake", "sub": tr("暮色湖畔 · 一片属于你的湖")}
	await play_shots(main, list)
