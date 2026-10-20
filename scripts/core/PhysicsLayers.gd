class_name PhysicsLayers
extends RefCounted
## 3D 物理层位掩码（与 project.godot 的 layer_names 一致）。

const WORLD := 1          ## 地形、树干、建筑等静态碰撞
const ACTORS := 2         ## 玩家（以后的 NPC、其他玩家）
const INTERACTABLE := 4   ## 门等可交互物体
const WATER_LIMIT := 8    ## 湖中涉水上限（MVP 不可深水游泳）
const TERRAIN := 16       ## 仅地形，用于高度查询射线
