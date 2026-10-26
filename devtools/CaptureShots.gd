extends Node
## 开发工具：在真实渲染窗口中按预设机位截图，输出到 docs/screenshots/。
##   Godot_console.exe --path . --resolution 1600x900 res://devtools/CaptureShots.tscn [-- 名称前缀]
## 机位 eye/look 为世界坐标；"ground": true 表示 eye.y 为离地高度。
## climate：preset（weather.json 预设）或 season/hour/weather；截图期间时间暂停，光照固定。
## character：front / back 为玩家人物特写（第三人称），lineup 为多套外观并排。
## chat：open / recent 为聊天框（输入中 / 关闭后最近消息）；其他机位隐藏聊天框。
## arms：{"size", "shoulder", "pose"} 调第一人称手；wave：拍右键挥手的那一下。

const MAIN_SCENE := "res://scenes/main/Main.tscn"
const OUT_DIR := "res://docs/screenshots"
const DUSK := {"preset": "Autumn_Dusk_Clear"}

const SHOTS := [
	{"name": "m1_01_spawn_dusk", "climate": DUSK, "eye": [-50, 1.65, 29], "ground": true, "look": [35, 2, -2]},
	{"name": "m1_02_lake_to_cabin", "climate": DUSK, "eye": [-8, 1.0 + 1.65, 25], "look": [-69, 4, 37]},
	{"name": "m1_03_cabin_front", "climate": DUSK, "eye": [-53, 1.65, 40], "ground": true, "look": [-66, 4.0, 37]},
	{"name": "m1_04_cabin_interior", "climate": DUSK, "eye": [-72.2, 2.4 + 1.65, 37.6], "look": [-60, 4.0, 36.5]},
	{"name": "m1_05_interior_stove", "climate": DUSK, "eye": [-65.6, 2.4 + 1.65, 38.2], "look": [-73, 3.0, 35.8]},
	{"name": "m1_06_north_trail", "climate": DUSK, "eye": [-80, 1.65, -50], "ground": true, "look": [-78, 2, -28]},
	{"name": "m1_07_viewpoint", "climate": DUSK, "eye": [-93, 1.8, -101], "ground": true, "look": [20, -5, 10]},
	{"name": "m1_08_aerial", "climate": DUSK, "eye": [-40, 190, 175], "look": [-10, 0, 0]},
	{"name": "m1_09_lake_reflection", "climate": DUSK, "eye": [-3, 1.0 + 1.65, 25], "look": [70, 2, -30]},
	{"name": "m2_01_night_rain_cabin", "climate": {"preset": "Autumn_Night_HeavyRain"}, "eye": [-53, 1.65, 40], "ground": true, "look": [-66, 4.0, 37]},
	{"name": "m2_02_night_rain_interior", "climate": {"preset": "Autumn_Night_HeavyRain"}, "eye": [-72.2, 2.4 + 1.65, 37.6], "look": [-60, 4.0, 36.5]},
	{"name": "m2_03_winter_snow", "climate": {"preset": "Winter_Morning_Snow"}, "eye": [-53, 1.65, 40], "ground": true, "look": [-66, 4.0, 37]},
	{"name": "m2_04_winter_lake", "climate": {"preset": "Winter_Morning_Snow"}, "eye": [-8, 1.0 + 1.65, 25], "look": [-69, 4, 37]},
	{"name": "m2_05_spring_fog", "climate": {"preset": "Spring_Fog"}, "eye": [-8, 1.0 + 1.65, 25], "look": [-69, 4, 37]},
	{"name": "m2_06_summer_noon", "climate": {"season": "SUMMER", "hour": 12.5, "weather": "CLEAR"}, "eye": [-50, 1.65, 29], "ground": true, "look": [35, 2, -2]},
	{"name": "m2_07_overcast_afternoon", "climate": {"season": "AUTUMN", "hour": 14.0, "weather": "OVERCAST"}, "eye": [-80, 1.65, -50], "ground": true, "look": [-78, 2, -28]},
	{"name": "m2_08_character_front", "climate": DUSK, "character": "front"},
	{"name": "m2_09_character_back", "climate": DUSK, "character": "back"},
	{"name": "m2_10_outfits", "climate": {"season": "AUTUMN", "hour": 15.5, "weather": "CLEAR"}, "character": "lineup"},
	{"name": "m2b_01_poolhouse_exterior", "climate": DUSK, "eye": [-7, 1.8, 69], "ground": true, "look": [4, 2.6, 84]},
	{"name": "m2b_02_pool_hall", "climate": DUSK, "house": true, "eye": [-4.5, 1.7, -6.2], "look": [10, -0.5, 1.5]},
	{"name": "m2b_03_underwater_pool", "climate": DUSK, "house": true, "eye": [2.0, -1.9, 1.8], "look": [-1.6, -3.4, 0.0]},
	{"name": "m2b_04_aquarium", "climate": DUSK, "house": true, "eye": [9.0, -5.3, 1.0], "look": [-3.0, -5.6, -0.5]},
	{"name": "m2b_05_fish_tank", "climate": DUSK, "house": true, "eye": [4.0, -5.4, -3.0], "look": [4.0, -5.4, -7.5]},
	{"name": "m2b_06_glass_ceiling", "climate": DUSK, "house": true, "eye": [1.6, -5.6, 0.4], "look": [1.6, 0.0, -0.4]},
	{"name": "m2b_07_night_poolhouse", "climate": {"season": "SUMMER", "hour": 22.0, "weather": "CLEAR"}, "eye": [-8, 1.7, 64], "ground": true, "look": [4, 2.0, 84]},
	{"name": "m2b_08_thunderstorm", "climate": {"preset": "Summer_Night_Thunderstorm"}, "lightning": true, "eye": [-50, 1.65, 29], "ground": true, "look": [35, 8, -2]},
	{"name": "m2b_09_rainbow", "climate": {"preset": "Summer_Rainbow"}, "eye": [-2, 2.65, 26], "antisolar": 16.0},
	{"name": "m2b_10_autumn_leaves", "climate": {"season": "AUTUMN", "hour": 15.0, "weather": "OVERCAST"}, "eye": [-80, 1.65, -50], "ground": true, "look": [-78, 2.5, -28]},
	{"name": "m2b_11_rabbit", "climate": {"season": "SUMMER", "hour": 10.0, "weather": "CLEAR"}, "animal": "rabbit"},
	{"name": "m2b_12_duck", "climate": {"season": "SUMMER", "hour": 10.0, "weather": "CLEAR"}, "animal": "duck"},
	{"name": "m2b_13_fox", "climate": {"season": "SUMMER", "hour": 10.0, "weather": "CLEAR"}, "animal": "fox"},
	{"name": "m2b_14_butterfly", "climate": {"season": "SUMMER", "hour": 10.0, "weather": "CLEAR"}, "animal": "butterfly"},
	{"name": "m2b_15_squirrel", "climate": {"season": "SUMMER", "hour": 10.0, "weather": "CLEAR"}, "animal": "squirrel"},
	{"name": "m2d_01_chat_open", "climate": DUSK, "eye": [-50, 1.65, 29], "ground": true, "look": [35, 2, -2], "chat": "open"},
	{"name": "m2d_02_chat_recent", "climate": DUSK, "eye": [-53, 1.65, 40], "ground": true, "look": [-66, 4.0, 37], "chat": "recent"},
	{"name": "m2b_16_entrance_sign", "climate": DUSK, "house": true, "eye": [-19.5, 1.8, -0.5], "look": [-13.0, 1.9, 1.5]},
	{"name": "m2b_17_pool_sign", "climate": DUSK, "house": true, "eye": [-1.6, 1.75, -5.4], "look": [-1.6, 0.85, -3.6]},
	{"name": "m2b_18_tank_sign", "climate": DUSK, "house": true, "eye": [-1.2, -5.25, -2.4], "look": [-2.6, -6.0, -4.8]},
	{"name": "m2b_19_trail_sign", "climate": DUSK, "eye": [-47.3, 1.65, 29.4], "ground": true, "look": [-47.0, 2.0, 32.0]},
	{"name": "fix_01_trail_sign", "climate": DUSK, "eye": [-47.3, 1.65, 29.4], "ground": true, "look": [-47.0, 2.0, 32.0]},
	{"name": "fix_02_canoe_dock", "climate": DUSK, "eye": [-34.0, 2.4, 19.0], "look": [-28.0, 0.2, 24.0]},
	{"name": "fix_03_creek_bridge", "climate": {"season": "SUMMER", "hour": 16.0, "weather": "CLEAR"}, "eye": [-77.5, 1.7, -8.5], "ground": true, "look": [-84.0, 2.6, -1.5]},
	{"name": "fix_04_gorge_bridge", "climate": {"season": "SUMMER", "hour": 15.0, "weather": "CLEAR"}, "eye": [-83.5, 15.5, -93.5], "look": [-89.8, 11.5, -89.0]},
	{"name": "m2c_01_first_person_hands", "climate": DUSK, "player": [-49.0, 27.0], "heading": 75.0, "pitch": -6.0},
	{"name": "v04_06_hands", "climate": DUSK, "player": [-49.0, 27.0], "heading": 75.0, "pitch": -6.0},
	{"name": "v04_07_hand_wave", "climate": DUSK, "player": [-49.0, 27.0], "heading": 75.0, "pitch": 4.0, "wave": true},
	{"name": "m2c_02_minimap_poolhouse", "climate": DUSK, "player": [-12.0, 80.0], "heading": 95.0, "pitch": -4.0},
	{"name": "m2c_03_dev_panel", "climate": DUSK, "player": [-49.0, 27.0], "heading": 75.0, "pitch": -2.0, "dev": true},
	{"name": "m2c_04_settings_view", "climate": DUSK, "player": [-49.0, 27.0], "heading": 75.0, "settings": 1},
	{"name": "m2c_05_hands_aquarium", "climate": DUSK, "player": [12.0, 84.0], "y": -5.0, "heading": 270.0, "pitch": -4.0},
	{"name": "m2e_01_cabin_night_stove", "climate": {"season": "AUTUMN", "hour": 21.0, "weather": "CLEAR"}, "player": [-60.0, 37.0], "heading": 0.0, "seat": "Seat_cabin_sofa_left", "pitch": -12.0},
	{"name": "m2e_02_chimney_smoke", "climate": DUSK, "eye": [-58, 4.5, 31], "look": [-72.9, 10.0, 36.0]},
	{"name": "m2e_03_canoe_paddling", "climate": DUSK, "player": [-28.0, 24.0], "canoe": [10.0, 14.0, 60.0], "heading": 60.0, "pitch": -10.0, "walk": true},
	{"name": "m2e_04_islet_camp", "climate": DUSK, "eye": [33, 2.2, 3], "look": [42, 1.6, -6]},
	{"name": "m2e_05_minimap_lake", "climate": DUSK, "player": [-28.0, 24.0], "canoe": [-2.0, 18.0, 70.0], "heading": 70.0, "pitch": -4.0},
	{"name": "m2e_06_cabin_bed", "climate": {"season": "AUTUMN", "hour": 21.0, "weather": "CLEAR"}, "eye": [-69.0, 4.3, 36.4], "look": [-73.0, 2.7, 39.4]},
	{"name": "m2f_01_aquarium_hall", "climate": DUSK, "house": true, "eye": [8.8, -5.0, 4.4], "look": [-3.0, -6.3, -4.0]},
	{"name": "m2f_02_ocean_tank", "climate": DUSK, "house": true, "eye": [1.0, -5.4, -1.2], "look": [0.5, -6.8, -6.5]},
	{"name": "m2f_03_diving_reef", "climate": DUSK, "player": [1.0, 79.2], "y": -6.4, "heading": 90.0, "pitch": -6.0},
	{"name": "m2f_04_channel", "climate": DUSK, "player": [2.2, 84.8], "y": -7.7, "heading": 0.0, "pitch": -14.0},
	{"name": "m2f_05_tank_depth", "climate": DUSK, "house": true, "eye": [6.0, -5.0, -2.4], "look": [4.0, -9.4, -6.2]},
	{"name": "m2g_01_chess_2d", "climate": {"season": "AUTUMN", "hour": 20.5, "weather": "CLEAR"}, "player": [-60.0, 37.0], "heading": 0.0, "seat": "Seat_cabin_sofa_left", "pitch": -30.0, "chess": ["e2e4", "e7e5", "g1f3", "b8c6", "f1c4", "g8f6"], "open_chess": true},
	{"name": "m2g_02_chess_table", "climate": {"season": "AUTUMN", "hour": 20.5, "weather": "CLEAR"}, "eye": [-67.6, 3.45, 39.25], "look": [-67.92, 2.87, 38.3], "chess": ["e2e4", "e7e5", "g1f3", "b8c6", "f1c4", "g8f6"]},
	{"name": "m2h_01_aquarium_decor", "climate": DUSK, "house": true, "eye": [9.0, -5.3, 3.2], "look": [-6.0, -5.9, -1.6]},
	{"name": "m2h_02_aquarium_whale", "climate": DUSK, "house": true, "eye": [2.2, -5.7, 3.6], "look": [6.6, -4.75, 0.2]},
	{"name": "m2h_03_emote_sit", "climate": {"season": "AUTUMN", "hour": 16.0, "weather": "CLEAR"}, "character": "front", "emote": "ground_sit"},
	{"name": "m2h_04_emote_wave", "climate": {"season": "AUTUMN", "hour": 16.0, "weather": "CLEAR"}, "character": "front", "emote": "wave"},
	{"name": "m2h_05_emote_dance", "climate": {"season": "AUTUMN", "hour": 16.0, "weather": "CLEAR"}, "character": "front", "emote": "dance"},
	{"name": "m2h_06_lie_stars", "climate": {"season": "SUMMER", "hour": 22.5, "weather": "CLEAR"}, "player": [-50.0, 29.0], "heading": 75.0, "emote": "lie", "pitch": 60.0},
	{"name": "m2h_07_action_wheel", "climate": DUSK, "player": [-49.0, 27.0], "heading": 75.0, "pitch": -4.0, "wheel": 0},
	{"name": "m2h_08_world_map", "climate": DUSK, "player": [-49.0, 27.0], "heading": 75.0, "world_map": true},
	{"name": "m2h_09_autumn_clear_leaves", "climate": {"season": "AUTUMN", "hour": 15.0, "weather": "CLEAR"}, "eye": [-80, 1.65, -50], "ground": true, "look": [-78, 2.5, -28]},
	{"name": "m2h_10_legacy_red_motes", "climate": {"season": "AUTUMN", "hour": 15.0, "weather": "CLEAR"}, "fx": "legacy_red_motes", "eye": [-80, 1.65, -50], "ground": true, "look": [-78, 2.5, -28]},
	{"name": "m2h_11_rain_lighter", "climate": {"season": "SUMMER", "hour": 14.0, "weather": "HEAVY_RAIN"}, "eye": [-8, 2.65, 25], "look": [-69, 4, 37]},
	{"name": "m2h_12_action_wheel_en", "lang": "en", "climate": DUSK, "player": [-49.0, 27.0], "heading": 75.0, "pitch": -4.0, "wheel": 1},
	{"name": "m2h_13_world_map_en", "lang": "en", "climate": DUSK, "player": [-49.0, 27.0], "heading": 75.0, "world_map": true},
	{"name": "m2h_14_lobby", "climate": DUSK, "player": [-49.0, 27.0], "heading": 75.0, "lobby": true},
	{"name": "m2h_15_lobby_en", "lang": "en", "climate": DUSK, "player": [-49.0, 27.0], "heading": 75.0, "lobby": true},
	{"name": "m2i_01_sign_day", "climate": {"season": "SUMMER", "hour": 15.0, "weather": "CLEAR"}, "eye": [-47.4, 1.75, 29.0], "ground": true, "look": [-47.0, 2.9, 32.0]},
	{"name": "m2i_02_update_banner", "climate": DUSK, "player": [-49.0, 27.0], "heading": 75.0, "lobby": true, "update": "0.3.1"},
	{"name": "m2i_03_fairy_glade_night", "climate": {"season": "SUMMER", "hour": 22.5, "weather": "CLEAR"}, "eye": [62, 1.7, 86.5], "ground": true, "look": [82, 9.0, 86]},
	{"name": "m2i_04_moon_gate", "climate": {"season": "SUMMER", "hour": 21.5, "weather": "CLEAR"}, "eye": [79.5, 1.7, 89.5], "ground": true, "look": [86, 9.0, 88]},
	{"name": "m2i_05_fairy_tree", "climate": {"season": "SUMMER", "hour": 21.0, "weather": "CLEAR"}, "eye": [77, 1.6, 95.5], "ground": true, "look": [76, 12.0, 82]},
	{"name": "m2i_06_fairy_glade_day", "climate": {"season": "SUMMER", "hour": 12.0, "weather": "CLEAR"}, "eye": [58.4, 1.75, 88.7], "ground": true, "look": [72, 7.2, 89]},
	{"name": "m2j_01_snow_peak_from_dock", "climate": {"season": "SUMMER", "hour": 16.0, "weather": "CLEAR"}, "eye": [-2, 2.65, 26], "look": [96, 26.0, -104]},
	{"name": "m2j_02_snow_peak_dusk", "climate": DUSK, "eye": [-50, 1.65, 29], "ground": true, "look": [96, 24.0, -104]},
	{"name": "m2j_03_summit_view", "climate": DUSK, "eye": [100.5, 1.7, -105.0], "ground": true, "look": [35, 4.0, -2]},
	{"name": "m2j_04_summit_cairn", "climate": {"season": "SUMMER", "hour": 14.0, "weather": "CLEAR"}, "eye": [97.5, 1.8, -103.0], "ground": true, "look": [103.6, 40.5, -107.4]},
	{"name": "m2j_05_ridge_trail", "climate": {"season": "SUMMER", "hour": 15.0, "weather": "CLEAR"}, "eye": [62, 1.7, -96], "ground": true, "look": [86, 33.0, -106]},
	{"name": "m2k_01_cave_mouth", "climate": {"season": "SUMMER", "hour": 16.0, "weather": "CLEAR"}, "eye": [-5.5, 1.7, -80.5], "ground": true, "look": [-7.5, 4.0, -96]},
	{"name": "m2k_02_cave_aerial", "climate": {"season": "SUMMER", "hour": 16.0, "weather": "CLEAR"}, "eye": [-24, 26, -66], "look": [8, 4, -100]},
	{"name": "m2k_03_cave_tunnel", "climate": {"season": "SUMMER", "hour": 16.0, "weather": "CLEAR"}, "eye": [-8.0, 3.85, -92.0], "look": [-5.0, 3.4, -101.0]},
	{"name": "m2k_04_cave_chamber", "climate": {"season": "SUMMER", "hour": 16.0, "weather": "CLEAR"}, "eye": [-0.5, 3.9, -100.6], "look": [8.0, 3.2, -103.0]},
	{"name": "m2k_05_totem", "climate": {"season": "SUMMER", "hour": 16.0, "weather": "CLEAR"}, "eye": [8.6, 4.0, -100.6], "look": [8.0, 4.1, -105.6]},
	{"name": "m2k_06_cave_portal", "climate": {"season": "SUMMER", "hour": 16.0, "weather": "CLEAR"}, "eye": [21.5, 3.8, -102.4], "look": [29.3, 3.95, -103.2]},
	{"name": "m2k_07_cottage", "climate": {"season": "SUMMER", "hour": 16.0, "weather": "CLEAR"}, "eye": [-83, 1.7, 91], "ground": true, "look": [-70, 3.0, 96]},
	{"name": "m2l_01_creek_falls", "climate": {"season": "SUMMER", "hour": 16.0, "weather": "CLEAR"}, "eye": [-93.2, 1.25, 2.2], "ground": true, "look": [-99.6, 4.4, 2.8]},
	{"name": "m2l_02_creek_bridge", "climate": {"season": "SUMMER", "hour": 16.0, "weather": "CLEAR"}, "eye": [-77.5, 1.7, -8.5], "ground": true, "look": [-84.0, 2.6, -1.5]},
	{"name": "m2l_03_creek_mouth", "climate": DUSK, "eye": [-47.0, 1.7, 10.5], "ground": true, "look": [-62.0, 1.6, 0.5]},
	{"name": "m2l_04_gorge_floor", "climate": {"season": "SUMMER", "hour": 15.0, "weather": "CLEAR"}, "eye": [-79.0, 1.7, -92.0], "ground": true, "look": [-90.0, 11.0, -89.2]},
	{"name": "m2l_05_gorge_rim", "climate": {"season": "SUMMER", "hour": 15.0, "weather": "CLEAR"}, "eye": [-103.0, 1.7, -86.0], "ground": true, "look": [-88.0, 8.0, -90.5]},
	{"name": "m2l_08_gorge_bridge", "climate": {"season": "SUMMER", "hour": 15.0, "weather": "CLEAR"}, "eye": [-83.5, 15.5, -93.5], "look": [-89.8, 11.5, -89.0]},
	{"name": "m2l_06_gorge_aerial", "climate": {"season": "SUMMER", "hour": 15.0, "weather": "CLEAR"}, "eye": [-66.0, 38.0, -72.0], "look": [-90.0, 8.0, -91.0]},
	{"name": "m2l_07_creek_aerial", "climate": {"season": "SUMMER", "hour": 16.0, "weather": "CLEAR"}, "eye": [-70.0, 30.0, 22.0], "look": [-84.0, 2.0, 0.0]},
	{"name": "m2k_08_constellations", "climate": {"season": "SUMMER", "hour": 23.0, "weather": "CLEAR"}, "state": {"constellations": ["pinecone", "canoe"]}, "eye": [-2, 2.65, 26], "look": [47.7, 52.65, -44.9]},
	{"name": "m2k_09_totem_dialogue", "climate": {"season": "SUMMER", "hour": 16.0, "weather": "CLEAR"}, "state": {}, "player": [8.0, -102.2], "heading": 0.0, "pitch": 9.0, "dialogue": true},
	{"name": "m2k_10_journal_quests", "climate": {"season": "SUMMER", "hour": 16.0, "weather": "CLEAR"}, "state": {"quests": {"fireside": "done", "lake_survey": "active", "summit": "active"}, "species": ["rabbit", "fox", "duck", "bird", "clownfish"], "constellations": ["canoe", "fox"]}, "player": [-49.0, 27.0], "heading": 75.0, "pitch": -4.0, "journal": 0},
	{"name": "m2k_12_journal_dex", "climate": {"season": "SUMMER", "hour": 16.0, "weather": "CLEAR"}, "state": {"quests": {"fireside": "done", "lake_survey": "active", "summit": "active"}, "species": ["rabbit", "fox", "duck", "bird", "clownfish"], "constellations": ["canoe", "fox"]}, "player": [-49.0, 27.0], "heading": 75.0, "pitch": -4.0, "journal": 1},
	{"name": "m2k_13_quest_tracker", "climate": {"season": "SUMMER", "hour": 16.0, "weather": "CLEAR"}, "state": {"quests": {"fireside": "done", "lake_survey": "active", "summit": "active"}}, "player": [-49.0, 27.0], "heading": 75.0, "pitch": -4.0},
	{"name": "v05_01_scroll_rolled", "climate": DUSK, "eye": [-46.2, 1.65, 23.5], "ground": true, "look": [-47.0, 2.2, 32.0]},
	{"name": "v05_02_scroll_open", "climate": DUSK, "eye": [-47.1, 1.65, 29.4], "ground": true, "look": [-47.0, 1.75, 32.0]},
	{"name": "v05_03_scroll_lectern", "climate": DUSK, "house": true, "eye": [-1.6, 1.75, -5.6], "look": [-1.6, 0.85, -3.6]},
	{"name": "v05_04_scroll_wall", "climate": DUSK, "house": true, "eye": [-19.0, 1.8, -1.5], "look": [-12.0, 2.6, 0.5]},
	{"name": "v05_05_scroll_third_person", "climate": DUSK, "player": [-46.3, 22.6], "heading": 90.0, "pitch": -4.0, "third_person": true},
	{"name": "v05_06_scroll_night", "climate": {"season": "SUMMER", "hour": 22.0, "weather": "CLEAR"}, "eye": [-47.1, 1.65, 29.4], "ground": true, "look": [-47.0, 1.75, 32.0]},
	{"name": "v05_07_dune_gate", "climate": DUSK, "eye": [-83.5, 1.7, 89.0], "ground": true, "look": [-94.0, 3.0, 86.0]},
	{"name": "v05_08_lobby_home", "climate": DUSK, "player": [-49.0, 27.0], "heading": 75.0, "lobby": true},
	{"name": "v05_09_new_game", "climate": DUSK, "player": [-49.0, 27.0], "heading": 75.0, "lobby": true, "newgame": ""},
	{"name": "v05_10_new_game_winter", "climate": DUSK, "player": [-49.0, 27.0], "heading": 75.0, "lobby": true, "newgame": "winter"},
	{"name": "v05_11_new_game_en", "lang": "en", "climate": DUSK, "player": [-49.0, 27.0], "heading": 75.0, "lobby": true, "newgame": "hardcore"},
	{"name": "v05_12_compass_stamina", "climate": DUSK, "player": [-60.0, 10.0], "heading": 20.0, "pitch": -3.0, "stamina": 0.45},
	{"name": "v05_13_journal_collection", "climate": DUSK, "player": [-49.0, 27.0], "heading": 75.0, "journal": 2},
	# 亚特兰蒂斯入口与更多玩法（atl_00、play_）
	{"name": "atl_00_ring", "climate": DUSK, "house": true, "eye": [-7.0, -7.7, -3.4], "look": [-10.0, -8.0, -5.5]},
	{"name": "play_01_fishing", "climate": DUSK, "player": [-3.0, 26.0], "y": 1.0, "heading": 80.0, "pitch": -2.0, "fish": true},
	{"name": "play_02_skipping", "climate": {"season": "SUMMER", "hour": 17.0, "weather": "CLEAR"}, "eye": [4.0, 2.4, 31.5], "look": [16.0, 0.3, 25.0], "skip": [-2.0, 1.0, 26.0, 90.0], "skip_frames": 26},
	{"name": "play_03_treasure", "climate": DUSK, "eye": [-44.6, 1.5, 35.8], "ground": true, "look": [-47.0, 0.4, 33.0], "look_ground": true, "chest": [-47.0, 33.0]},
	{"name": "play_04_cabinet", "climate": DUSK, "trophies": true, "eye": [-67.4, 2.4 + 1.25, 36.2], "look": [-67.75, 2.4 + 0.95, 34.0]},
	{"name": "play_05_achievements", "climate": DUSK, "trophies": true, "player": [-49.0, 27.0], "heading": 75.0, "journal": 5},
	{"name": "play_06_challenge", "climate": DUSK, "player": [-80.5, -48.0], "heading": 5.0, "pitch": -3.0, "course": "lake_trail"},
	{"name": "play_07_cooking", "climate": DUSK, "trophies": true, "player": [-71.6, 36.4], "y": 2.4, "heading": 290.0, "pitch": -12.0, "cooking": true},
	{"name": "play_08_journal_activities", "climate": DUSK, "trophies": true, "player": [-49.0, 27.0], "heading": 75.0, "journal": 3},
	{"name": "play_09_journal_lore", "climate": DUSK, "trophies": true, "player": [-49.0, 27.0], "heading": 75.0, "journal": 4},
	# 划船人的信与石头小屋（letters：read 读过的信、unlocked 门开着、lamp 台灯、open 打开读信界面 = 信 id 或 chart）
	{"name": "ltr_01_old_book", "climate": DUSK, "letters": {}, "player": [-70.75, 35.1], "y": 2.4, "heading": 345.0, "pitch": -8.0},
	{"name": "ltr_02_letter_open", "climate": DUSK, "letters": {"open": "cabin"}, "player": [-70.75, 35.1], "y": 2.4, "heading": 345.0, "pitch": -8.0},
	{"name": "ltr_03_dock_box", "climate": DUSK, "letters": {}, "player": [-4.3, 26.0], "y": 1.0, "heading": 108.0, "pitch": -26.0},
	{"name": "ltr_04_islet_tin", "climate": DUSK, "letters": {}, "player": [40.4, -2.6], "heading": 60.0, "pitch": -28.0},
	{"name": "ltr_04b_islet_overview", "climate": DUSK, "letters": {}, "eye": [36.0, 6.5, 1.5], "look": [41.8, 1.2, -3.4]},
	{"name": "ltr_05_cottage_lock", "climate": {"season": "SUMMER", "hour": 16.0, "weather": "CLEAR"}, "letters": {}, "eye": [-75.8, 1.6, 94.0], "ground": true, "look": [-72.6, 3.2, 95.0]},
	{"name": "ltr_06_cottage_night", "climate": {"season": "AUTUMN", "hour": 20.6, "weather": "CLEAR"}, "letters": {"read": ["cabin", "dock", "islet"], "unlocked": true, "lamp": true}, "eye": [-80.0, 1.7, 100.5], "ground": true, "look": [-71.5, 2.8, 95.8]},
	{"name": "ltr_07_interior", "climate": DUSK, "letters": {"read": ["cabin", "dock", "islet"], "unlocked": true, "lamp": true}, "player": [-71.7, 95.0], "y": 2.4, "heading": 126.0, "pitch": -12.0},
	{"name": "ltr_08_chart_open", "climate": DUSK, "letters": {"read": ["cabin", "dock", "islet"], "unlocked": true, "lamp": true, "open": "chart"}, "player": [-71.7, 95.0], "y": 2.4, "heading": 126.0, "pitch": -12.0},
	{"name": "ltr_09_journal_letters", "climate": DUSK, "letters": {"read": ["cabin", "dock"]}, "player": [-49.0, 27.0], "heading": 75.0, "journal": 4},
	{"name": "ltr_10_letter_en", "climate": DUSK, "lang": "en", "letters": {"open": "islet"}, "player": [40.4, -2.6], "heading": 60.0, "pitch": -28.0},
]

const OUTFITS := [
	{"styles": {"hair": "long", "hat": "none", "top": "tee", "bottom": "shorts", "shoes": "sneakers", "back": "none", "face": "smile"},
		"colors": {"hair": "#6b3a1f", "top": "#d9c9a0", "bottom": "#55606e", "shoes": "#f0ece4"}},
	{"styles": {"hair": "short", "hat": "beanie", "top": "jacket", "bottom": "jeans", "shoes": "boots", "back": "backpack", "face": "default"},
		"colors": {"hair": "#1e1a18", "hat": "#3f5e7a", "hat_accent": "#e6dccb", "top": "#8e3b2e", "top_accent": "#2b2b2b", "bottom": "#3a3f4a", "shoes": "#5a3b25", "back": "#6b7a4a"}},
	{"styles": {"hair": "ponytail", "hat": "cap", "top": "hoodie", "bottom": "jeans", "shoes": "sneakers", "back": "none", "face": "smile"},
		"colors": {"hair": "#c9a25e", "hat": "#2f4b3a", "hat_accent": "#e8e0cc", "top": "#c8b7d8", "top_accent": "#f4efe6", "bottom": "#2c3550"}},
	{"styles": {"hair": "bun", "hat": "none", "top": "tee", "bottom": "jeans", "shoes": "boots", "back": "backpack", "face": "default"},
		"colors": {"hair": "#2b1810", "skin": "#8d5a3c", "top": "#3c6e71", "bottom": "#a68a64", "shoes": "#2a2420", "back": "#b35c3a"}},
]

var _camera: Camera3D
var _main: Node
var _player: FirstPersonController
var _lineup: Node3D = null


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	# 截图不受本机设置影响：窗口模式、语言跟随每个机位的 "lang"（默认跟随系统）
	GameSettings.set_value("fullscreen", false, false)
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	add_child(_main)
	for layer_name in ["HUD", "DebugOverlay"]:
		(_main.get_node(layer_name) as CanvasLayer).visible = false
	_player = get_tree().get_first_node_in_group("local_player") as FirstPersonController
	_player.set_physics_process(false)
	_camera = Camera3D.new()
	_camera.fov = 75.0
	_camera.near = 0.05
	_camera.far = 1500.0
	add_child(_camera)
	_camera.current = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var prefix := ""
	if not OS.get_cmdline_user_args().is_empty():
		prefix = OS.get_cmdline_user_args()[0]
	await _wait(120)
	var last_climate := {}
	for shot in SHOTS:
		if not str(shot["name"]).begins_with(prefix):
			continue
		if GameSettings.language != str(shot.get("lang", "auto")):
			GameSettings.set_value("language", str(shot.get("lang", "auto")), false)
		var climate: Dictionary = shot.get("climate", DUSK)
		if climate != last_climate:
			var was_snowing := WorldState.weather_id == &"SNOW"
			_apply_climate(climate)
			last_climate = climate
			await _wait(150)
			# 仙境林地按时间天气直接到位（截图不等它慢慢长出来）
			var glade := get_tree().get_first_node_in_group("fairy_glade") as FairyGlade
			if glade != null:
				glade._apply(FairyGlade.should_appear(WorldState.time_minutes, WorldState.weather_id), true)
			# 雪花寿命约 11 秒：从下雪切走后等残留雪花落完再拍
			if was_snowing and WorldState.weather_id != &"SNOW":
				await get_tree().create_timer(12.0).timeout
		var precip := get_tree().get_first_node_in_group("precipitation") as Precipitation
		if precip.profile_override != str(shot.get("fx", "")):
			precip.profile_override = str(shot.get("fx", ""))
			await _wait(30)
		_camera.cull_mask = 0xFFFFF & ~FirstPersonArms.FP_ARMS_LAYER if shot.has("character") else (0xFFFFF & ~FirstPersonController.BODY_LAYER & ~FirstPersonArms.FP_ARMS_LAYER)
		await _setup_player_view(shot)
		if _lineup != null:
			_lineup.visible = shot.get("character", "") == "lineup"
		if shot.has("player"):
			pass
		elif shot.has("character"):
			_force_emote(str(shot.get("emote", "")))
			_frame_character(str(shot["character"]))
		elif shot.has("animal"):
			_frame_animal(str(shot["animal"]))
		elif shot.has("bridge_eye"):
			# 站在某座桥的正中间（桥面高度按 Streams.deck_height 算）
			for b: Dictionary in WorldLayout.section("nature").get("bridges", []):
				if str(b["id"]) == str(shot["bridge_eye"]):
					var mid := WorldLayout.v2(b["from"]).lerp(WorldLayout.v2(b["to"]), 0.5)
					_camera.global_position = Vector3(mid.x, Streams.deck_height(b, 0.5) + 2.0, mid.y)
			_camera.look_at(_vec(shot["look"]), Vector3.UP)
		elif shot.get("house", false):
			var house := _main.get_node("PoolHouse") as Node3D
			_camera.global_position = house.to_global(_vec(shot["eye"]))
			_camera.look_at(house.to_global(_vec(shot["look"])), Vector3.UP)
		else:
			var e := WorldLayout.v2([shot["eye"][0], shot["eye"][2]])
			var y := float(shot["eye"][1])
			if shot.get("ground", false):
				y += WorldTerrain.height_at(e.x, e.y)
			_camera.global_position = Vector3(e.x, y, e.y)
			if shot.has("antisolar"):
				await _wait(4)
				_look_antisolar(float(shot["antisolar"]))
			else:
				var look := Vector3(float(shot["look"][0]), float(shot["look"][1]), float(shot["look"][2]))
				if shot.get("look_ground", false):
					look.y += WorldTerrain.height_at(look.x, look.z)
				_camera.look_at(look, Vector3.UP)
		var chat := _main.get_node("ChatBox") as ChatBox
		chat.visible = shot.has("chat")
		await _wait(40)
		if shot.has("chat"):
			await _stage_chat(chat, str(shot["chat"]))
		await _stage_play(shot)
		if shot.has("state"):
			_apply_quest_state(shot["state"])
			await _wait(5)
		if shot.get("dialogue", false):
			(_main.find_child("Totem", true, false) as CaveTotem).interact(_player)
			await _wait(150)
		if shot.has("letters"):
			_stage_letters(shot["letters"])
			await _wait(8)
		if shot.has("journal"):
			(_main.get_node("JournalPanel") as JournalPanel).open(int(shot["journal"]))
			await _wait(5)
		if shot.get("wave", false) and _player.arms != null:
			_player.arms.wave()
			await _wait(24)
		if shot.get("lightning", false):
			var env := _main.get_node("World/Environment") as EnvironmentDirector
			env._flash_t = 0.0
			await _wait(2)
		var img := get_viewport().get_texture().get_image()
		var path := ProjectSettings.globalize_path("%s/%s.png" % [OUT_DIR, shot["name"]])
		img.save_png(path)
		print("saved ", path)
		_unstage_play()
		if shot.has("chat"):
			chat.close()
		(_main.get_node("DialoguePanel") as DialoguePanel).close()
		(_main.get_node("LetterPanel") as LetterPanel).close()
		var journal := _main.get_node("JournalPanel") as JournalPanel
		if journal.is_open():
			journal.close()
	await _shoot_worlds(prefix)
	get_tree().quit()


## 划船人的信与石头小屋的示例状态："letters": {"read": [信 id], "unlocked": 门开着, "lamp": 台灯亮着, "open": 信 id 或 "chart"}。
func _stage_letters(d: Dictionary) -> void:
	var cottage := get_tree().get_first_node_in_group("stone_cottage") as StoneCottage
	WorldState.flags["letters"] = (d.get("read", []) as Array).duplicate()
	WorldState.flags["cottage_unlocked"] = bool(d.get("unlocked", false))
	cottage.door.apply_state("open" if d.get("unlocked", false) else "locked")
	cottage.lamp.apply_state("on" if d.get("lamp", false) else "off")
	if d.has("open"):
		var panel := _main.get_node("LetterPanel") as LetterPanel
		if str(d["open"]) == "chart":
			panel.open_chart(_player)
		else:
			panel.open_letter(str(d["open"]), _player)


## 任务与图鉴的示例状态："state": {"quests": {id: state}, "species": [...], "constellations": [...]}。
func _apply_quest_state(d: Dictionary) -> void:
	QuestLog.reset()
	for id: String in d.get("quests", {}):
		WorldState.quests[id] = {"state": str(d["quests"][id]), "progress": 0, "thanked": str(d["quests"][id]) == "done"}
	for kind in ["species", "constellations"]:
		for id: String in d.get(kind, []):
			WorldState.journal_add(kind, id)
	var stars := _main.get_node("StarField") as StarField
	for id: String in stars._line_alpha:
		stars._line_alpha[id] = 1.0 if id in WorldState.journal_list("constellations") else 0.0
	QuestLog.changed.emit()


## 第二个世界（占位浮岛）：先把湖畔整个移出场景树，单独放进世界二拍一张，再放回来。
## 其他世界的机位：world 为世界 id；eye / look 为那个世界的坐标，"ground": true 时 eye.y 加地面高度；
## "player": [x, z] 用玩家自己的相机（看得到 HUD、小地图、罗盘），"world_map": true 打开 Tab 世界地图；
## "beacons": true 先点亮云海浮岛的四座风灯（天鲸游近），"altar": true 先把琥珀沙丘的碎片全部嵌回祭坛（光柱）。
const WORLD_SHOTS := [
	{"name": "v05_w2_01_overview", "world": "world_02", "eye": [46.0, 26.0, 52.0], "look": [-4.0, -2.0, -26.0]},
	{"name": "v05_w2_02_main_island", "world": "world_02", "eye": [7.0, 1.8, 15.0], "ground": true, "look": [-9.0, 4.5, -7.0]},
	{"name": "v05_w2_03_bridge", "world": "world_02", "eye": [-22.5, 1.8, -3.0], "ground": true, "look": [-52.0, 4.0, -6.0]},
	{"name": "v05_w2_04_falls", "world": "world_02", "eye": [12.0, 3.0, 24.0], "look": [29.0, -8.0, 12.0]},
	{"name": "v05_w2_05_sky_steps", "world": "world_02", "eye": [2.0, 10.5, -64.0], "look": [10.0, 13.0, -96.0]},
	{"name": "v05_w2_06_whale", "world": "world_02", "beacons": true, "eye": [50.0, 1.8, 8.0], "ground": true, "look": [10.0, 14.0, -30.0]},
	{"name": "v05_w2_07_hud", "world": "world_02", "player": [0.0, 12.0], "heading": 350.0, "pitch": -2.0},
	{"name": "v05_w2_08_world_map", "world": "world_02", "player": [0.0, 12.0], "heading": 0.0, "world_map": true},
	{"name": "v05_w3_01_overview", "world": "world_03", "eye": [55.0, 34.0, 95.0], "look": [-5.0, 2.0, 0.0]},
	{"name": "v05_w3_02_oasis", "world": "world_03", "eye": [3.0, 1.8, 33.0], "ground": true, "look": [27.0, 1.0, 22.0]},
	{"name": "v05_w3_03_temple", "world": "world_03", "eye": [-19.0, 2.2, -35.0], "ground": true, "look": [-30.0, 7.0, -66.0]},
	{"name": "v05_w3_04_ruins", "world": "world_03", "eye": [-35.0, 1.8, 5.0], "ground": true, "look": [-50.0, 3.0, -10.0]},
	{"name": "v05_w3_05_arch", "world": "world_03", "eye": [-68.0, 1.8, 52.0], "ground": true, "look": [-80.0, 6.0, 40.0]},
	{"name": "v05_w3_06_altar_beam", "world": "world_03", "altar": true, "eye": [-6.0, 14.0, -28.0], "look": [-30.0, 22.0, -68.0]},
	{"name": "v05_w3_07_hud", "world": "world_03", "player": [0.0, 66.0], "heading": 10.0, "pitch": -2.0},
	{"name": "v05_w3_08_world_map", "world": "world_03", "player": [0.0, 66.0], "heading": 0.0, "world_map": true},
	{"name": "play_11_oasis_fishing", "world": "world_03", "player": [7.0, 27.5], "heading": 92.0, "pitch": -12.0, "fish": true},
	{"name": "atl_01_overview", "world": "world_04", "eye": [38.0, 26.0, 36.0], "look": [-4.0, 0.0, -6.0]},
	{"name": "atl_02_street", "world": "world_04", "eye": [16.0, 1.75, 15.0], "ground": true, "look": [0.0, 4.0, -2.0]},
	{"name": "atl_03_temple_before", "world": "world_04", "unsolve": true, "eye": [5.0, 1.8, 19.5], "ground": true, "look": [0.0, 4.0, -4.0]},
	{"name": "atl_05_temple_after", "world": "world_04", "solve": true, "eye": [5.0, 1.8, 19.5], "ground": true, "look": [0.0, 6.0, -4.0]},
	{"name": "atl_12_beam", "world": "world_04", "solve": true, "eye": [-30.0, 6.0, -26.0], "look": [10.0, 2.0, -12.0]},
	{"name": "atl_04_outside", "world": "world_04", "eye": [16.0, 7.0, 98.0], "look": [0.0, 16.0, 30.0]},
	{"name": "atl_13_seabed", "world": "world_04", "eye": [-48.0, 3.0, 66.0], "look": [-64.0, 2.0, 80.0]},
	{"name": "atl_06_current", "world": "world_04", "player": [-57.0, 18.0], "heading": 90.0, "pitch": -8.0, "rail": "current", "progress": 48.0},
	{"name": "atl_07_manta", "world": "world_04", "player": [-78.0, -12.0], "heading": 0.0, "pitch": -10.0, "rail": "manta", "progress": 160.0, "third_person": true},
	{"name": "atl_10_oxygen_hud", "world": "world_04", "player": [6.0, 76.0], "y": 3.0, "heading": 0.0, "pitch": 8.0, "oxygen": 0.55},
	{"name": "atl_11_tablet", "world": "world_04", "player": [12.0, 23.4], "heading": 0.0, "pitch": -22.0},
	{"name": "atl_14_dive_rings", "world": "world_04", "player": [28.0, 60.0], "y": 2.0, "heading": 132.0, "pitch": 2.0, "course": "dive_rings"},
	{"name": "atl_08_world_map", "world": "world_04", "player": [0.0, 10.4], "heading": 0.0, "world_map": true},
	{"name": "atl_09_night", "world": "world_04", "solve": true, "hour": 22.0, "eye": [36.0, 18.0, 44.0], "look": [0.0, 4.0, 0.0]},
]


func _shoot_worlds(prefix: String) -> void:
	var world: MiniWorld = null
	var world_id := ""
	for shot: Dictionary in WORLD_SHOTS:
		if not str(shot["name"]).begins_with(prefix):
			continue
		if str(shot["world"]) != world_id:
			if world != null:
				world.queue_free()
				await _wait(2)
			if _main.is_inside_tree():
				remove_child(_main)
			world_id = str(shot["world"])
			world = (load(str(WorldRegistry.get_world(world_id)["scene"])) as PackedScene).instantiate() as MiniWorld
			add_child(world)
			await _wait(90)
		var player_view := shot.has("player")
		for layer_name in ["HUD", "Minimap", "CompassBar", "ActionBar", "JournalPanel"]:
			(world.get_node(layer_name) as CanvasLayer).visible = player_view
		var wm := world.get_node("WorldMap") as WorldMap
		if wm.open != shot.get("world_map", false):
			wm.toggle()
		if shot.get("beacons", false) and world is World02:
			for b in (world as World02).beacons:
				b.set_lit(true)
			await _wait(30)
			(world as World02).whale.position = Vector3(World02.WHALE_NEAR.x, World02.WHALE_NEAR.y, 0.0)
			(world as World02).whale_pivot.rotation.y = deg_to_rad(-40.0)
		if shot.get("altar", false) and world is World03:
			(world as World03).altar.apply_state("placed:6")
		if world is World04:
			await _stage_atlantis(world as World04, shot)
		if player_view:
			var a: Array = shot["player"]
			var py := float(shot["y"]) if shot.has("y") else world.height_at(float(a[0]), float(a[1])) + 0.1
			world.player.teleport_to(Vector3(float(a[0]), py, float(a[1])), float(shot.get("heading", 0.0)))
			world.player.head.rotation.x = deg_to_rad(float(shot.get("pitch", 0.0)))
			world.player.set_third_person(shot.get("third_person", false))
			world.player.camera.current = true
			await _wait(30)
			if world is World04:
				await _stage_rail(world as World04, shot)
			_player = world.player
			await _stage_play(shot)
			await _wait(30)
		else:
			var cam := Camera3D.new()
			cam.fov = 70.0
			cam.far = 2000.0
			cam.cull_mask = 0xFFFFF & ~FirstPersonController.BODY_LAYER & ~FirstPersonArms.FP_ARMS_LAYER
			world.add_child(cam)
			var eye := _vec(shot["eye"])
			if shot.get("ground", false):
				eye.y += world.height_at(eye.x, eye.z)
			cam.global_position = eye
			cam.look_at(_vec(shot["look"]), Vector3.UP)
			cam.current = true
			await _wait(40)
			cam.queue_free()
		var path := ProjectSettings.globalize_path("%s/%s.png" % [OUT_DIR, shot["name"]])
		get_viewport().get_texture().get_image().save_png(path)
		print("saved ", path)
		_unstage_play()
		if world is World04 and world.player.rail != null:
			world.player.rail.try_release(world.player)
			world.player.end_rail(world.player.global_position)
	if world != null:
		world.queue_free()
		await _wait(2)
	if not _main.is_inside_tree():
		add_child(_main)


func _apply_climate(c: Dictionary) -> void:
	var climate := _main.get_node("Systems") as ClimateSystem
	WorldState.time_paused = false
	if c.has("preset"):
		climate.apply_preset(str(c["preset"]))
	else:
		climate.jump_to_season(StringName(c["season"]))
		climate.set_hour(float(c["hour"]))
		climate.set_weather(StringName(c["weather"]), 0.0)
		WorldState.ground_snow = 0.0
		# 不带预设的镜头不继承上一张的雨后湿地与彩虹
		WorldState.ground_wetness = float(c.get("wetness", 0.0))
		WorldState.rain_recent = 0.0
	WorldState.time_paused = true


func _frame_character(mode: String) -> void:
	var spot := Vector3(-46.5, 0.0, 22.0)
	spot.y = WorldTerrain.height_at(spot.x, spot.z)
	_player.global_position = spot
	_player.rotation.y = deg_to_rad(-95.0)
	_player.head.rotation.x = 0.0
	_player.body.animate(0.016, 0.0, true, 0.0)
	var forward := -_player.global_basis.z
	var right := _player.global_basis.x
	match mode:
		"front":
			_camera.global_position = spot + forward * 2.6 + right * 0.4 + Vector3(0.0, 1.25, 0.0)
			_camera.look_at(spot + Vector3(0.0, 1.0, 0.0), Vector3.UP)
		"back":
			_camera.global_position = spot - forward * 3.2 + right * 0.45 + Vector3(0.0, 1.9, 0.0)
			_camera.look_at(spot + forward * 6.0 + Vector3(0.0, 1.2, 0.0), Vector3.UP)
		"lineup":
			_player.global_position = spot + Vector3(0.0, -50.0, 0.0)
			if _lineup == null:
				_lineup = Node3D.new()
				add_child(_lineup)
				for i in OUTFITS.size():
					var a := PlayerProfile.default_appearance()
					var o: Dictionary = OUTFITS[i]
					for k in o["styles"]:
						a.styles[k] = o["styles"][k]
					for k in o["colors"]:
						a.colors[k] = Color.html(o["colors"][k])
					var m := CharacterModel.new()
					m.appearance = a
					_lineup.add_child(m)
					m.position = Vector3((i - 1.5) * 1.1, 0.0, 0.0)
					m.rotation.y = deg_to_rad(18.0 * (i - 1.5))
			_lineup.global_position = spot
			_lineup.rotation.y = deg_to_rad(-60.0)
			var fwd := -_lineup.global_basis.z
			_camera.global_position = spot + fwd * 4.6 + Vector3(0.0, 1.3, 0.0)
			_camera.look_at(spot + Vector3(0.0, 0.95, 0.0), Vector3.UP)


## 背对太阳取景（彩虹在对日点周围 42°）：pitch 为抬头角度。
func _look_antisolar(pitch_deg: float) -> void:
	var env := _main.get_node("World/Environment") as EnvironmentDirector
	var away := -env.sun.global_basis.z
	away.y = 0.0
	away = away.normalized()
	var dir := away * cos(deg_to_rad(pitch_deg)) + Vector3.UP * sin(deg_to_rad(pitch_deg))
	_camera.look_at(_camera.global_position + dir, Vector3.UP)
	print("rainbow=%.2f sun_el=%.1f" % [env.rainbow, env.sun_elevation])


func _vec(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


## 对准某种动物中第一只可见的个体（第三人称取景：它的正前方偏侧 2–3 m）。
func _frame_animal(species: String) -> void:
	for a in get_tree().get_nodes_in_group("fauna"):
		var an := a as Animal
		if an.species_id != species or not an.visible:
			continue
		var p := an.global_position
		var fwd := -an.global_basis.z
		var dist := 2.2 if species in ["butterfly", "squirrel", "rabbit"] else 3.2
		var eye := p + fwd * dist + an.global_basis.x * dist * 0.5 + Vector3(0.0, 0.6, 0.0)
		eye.y = maxf(eye.y, WorldTerrain.height_at(eye.x, eye.z) + 0.4)
		if species == "duck":
			eye.y = maxf(eye.y, 0.6)
		_camera.global_position = eye
		_camera.look_at(p + Vector3(0.0, 0.15, 0.0), Vector3.UP)
		an.set_physics_process(false)
		return


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


## 聊天框机位："chat": "open" 为正在输入（显示全部记录与输入行），"recent" 为关闭后左下角浮现的最近消息。
func _stage_chat(chat: ChatBox, mode: String) -> void:
	chat.clear()
	chat.post_system(tr("欢迎来到%s。按 T 聊天，输入 /help 查看命令。") % tr(str(WorldRegistry.current().get("name", ""))))
	chat.submit("今天的晚霞真好看")
	chat.submit("/time")
	chat.submit("/weather")
	chat.submit("/me 坐在湖边看日落")
	if mode == "open":
		chat.submit("/help")
		chat.open()
		chat._field.text = "去码头那边走走"
		chat._field.caret_column = chat._field.text.length()
	await _wait(10)
## 用玩家自己的相机拍（看得到第一人称的手、HUD、小地图）："player": [x, z]，"heading"/"pitch" 度，
## "dev": true 打开开发者面板，"settings": 分页序号 打开设置菜单，"walk": true 让手按走路姿势摆。
func _setup_player_view(shot: Dictionary) -> void:
	var player_view := shot.has("player")
	var pause := _main.get_node("PauseMenu")
	if pause.is_open():
		pause._set_open(false)
	GameSettings.set_developer_mode(shot.get("dev", false))
	var table := (_main.get_node("Cabin/Generated/Life") as CabinLife).chess
	if table.panel.is_open():
		table.panel.close()
	if shot.has("chess"):
		table.panel.mode = "pvp"
		table.panel.new_game()
		for mv: String in shot["chess"]:
			table.panel.game.play_squares(ChessGame.square_from_name(mv.left(2)), ChessGame.square_from_name(mv.right(2)))
		table.sync_pieces()
	for layer_name in ["HUD", "Minimap", "ActionBar"]:
		(_main.get_node(layer_name) as CanvasLayer).visible = player_view
	var wheel := _main.get_node("ActionBar") as ActionBar
	if wheel.wheel_open:
		wheel._set_wheel(false)
	if shot.has("update"):
		Updater.latest_version = str(shot["update"])
		Updater._set_state(Updater.State.AVAILABLE, tr("发现新版本 v%s") % Updater.latest_version)
	elif Updater.state == Updater.State.AVAILABLE:
		Updater._set_state(Updater.State.IDLE, "")
	var lobby := _main.get_node_or_null("LobbyMenu") as LobbyMenu
	if lobby != null and lobby.is_open() != shot.get("lobby", false):
		if shot.get("lobby", false):
			lobby.open()
		else:
			lobby.close()
	if lobby != null and shot.has("newgame"):
		lobby.open_new_game(false)
		if str(shot["newgame"]) != "":
			lobby._apply_preset(str(shot["newgame"]))
	elif lobby != null and lobby.is_open() and lobby._page == LobbyMenu.Page.NEWGAME:
		lobby._show(LobbyMenu.Page.HOME)
	var world_map := _main.get_node("WorldMap") as WorldMap
	if world_map.open != shot.get("world_map", false):
		world_map.toggle()
	_player.set_physics_process(player_view)
	if not player_view:
		_camera.current = true
		return
	var a: Array = shot["player"]
	var x := float(a[0])
	var z := float(a[1])
	_player.set_flying(false)
	var y := float(shot["y"]) if shot.has("y") else WorldTerrain.height_at(x, z)
	_player.teleport_to(Vector3(x, y + 0.05, z), float(shot.get("heading", 0.0)))
	_player.head.rotation.x = deg_to_rad(float(shot.get("pitch", 0.0)))
	_player.set_third_person(shot.get("third_person", false))
	# "arms": {"size", "shoulder", "pose"} 调第一人称手的大小和姿势（调参用）；没有就用设置里的值
	if _player.arms != null:
		var arm_cfg: Dictionary = shot.get("arms", {})
		_player.arms.shoulder = _vec(arm_cfg["shoulder"]) if arm_cfg.has("shoulder") else FirstPersonArms.SHOULDER
		_player.arms.pose = _vec(arm_cfg["pose"]) if arm_cfg.has("pose") else FirstPersonArms.POSE
		_player.arms.set_size(float(arm_cfg.get("size", GameSettings.hand_size)))
	_player.camera.current = true
	_player.autopilot_enabled = shot.get("walk", false)
	if shot.has("canoe"):
		var canoe := _main.get_node("World/Dock/Generated/Canoe") as Canoe
		var c: Array = shot["canoe"]
		canoe.place_at(Vector2(float(c[0]), float(c[1])), float(c[2]))
		_player.board(canoe)
		_player.rotation.y = deg_to_rad(-float(shot.get("heading", c[2])))
		if shot.get("walk", false):
			var fwd := canoe.forward()
			_player.autopilot_direction = Vector3(fwd.x, 0.0, fwd.y)
	if shot.has("seat"):
		var seat := _main.find_child(str(shot["seat"]), true, false) as Seat
		if seat != null:
			_player.sit(seat)
			_player.rotation.y = deg_to_rad(-float(shot.get("heading", 0.0)))
	await _wait(30)
	if shot.has("emote"):
		_player.do_emote(str(shot["emote"]))
		_player.head.rotation.x = deg_to_rad(float(shot.get("pitch", 0.0)))
	await _wait(30)
	if shot.has("settings"):
		pause.open_settings(int(shot["settings"]))
	if shot.has("stamina"):
		GameRules.set_rule("stamina", true)
		_player.stamina = float(shot["stamina"])
		WorldState.journal["photos"] = ["cabin", "rabbit", "rainbow"]
		await _wait(4)
	if shot.get("open_chess", false):
		table.interact(_player)
		table.panel.click_square(ChessGame.square_from_name("d2"))
	if shot.get("dev", false):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if shot.has("wheel"):
		wheel._set_wheel(true)
		var dir := [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT][int(shot["wheel"])] as Vector2
		Input.warp_mouse(get_viewport().get_visible_rect().size * 0.5 + dir * 95.0)
		await _wait(5)


## 人物特写里摆动作（截图时玩家物理关着，直接设好姿势与手势，不经过 do_emote 的落地检查）。
func _force_emote(id: String) -> void:
	_player.end_emote()
	if id == "":
		return
	_player.emote = id
	if id in FirstPersonController.EMOTE_POSES:
		_player.body.pose = id
	else:
		_player.body.set_gesture(id)
		_player.body._gesture_t = 0.35
	_player._place_body()


## 小玩法机位："fish" 甩竿（鱼漂在水上等着）、"skip": [x, y, z, 朝向] 从那里打一个水漂（拍石头弹在水面上）、
## "chest": [x, z] 摆一只开着的宝箱、"course": id 开始一项计时挑战（看得到计时条）、"cooking" 打开烹饪面板、
## "trophies" 先填一份“玩了一阵子”的存档状态（收藏柜、成就、日志都有东西）。
func _stage_play(shot: Dictionary) -> void:
	var play := get_tree().get_first_node_in_group("play_activities") as PlayActivities
	if shot.get("trophies", false):
		_fill_trophies()
	if play == null:
		return
	if shot.get("fish", false):
		play.bite_wait = 1000.0
		play.cast()
		await _wait(30)
	if shot.has("skip"):
		var s: Array = shot["skip"]
		_player.teleport_to(Vector3(float(s[0]), float(s[1]), float(s[2])), float(s[3]))
		play.throw_stone(1.0, 0.0)
		await _wait(int(shot.get("skip_frames", 48)))
	if shot.has("chest"):
		var c: Array = shot["chest"]
		play._open_chest(Vector3(float(c[0]), play.ground_at(float(c[0]), float(c[1])), float(c[1])), false)
	if shot.has("course"):
		play.start_course(str(shot["course"]))
		await _wait(20)
		play.course_time = float(shot.get("course_time", 12.4))
		await _wait(2)
	if shot.get("cooking", false):
		var panel := get_tree().get_first_node_in_group("cooking_panel") as CookingPanel
		if panel != null:
			panel.open(_player if _player.is_inside_tree() else get_tree().get_first_node_in_group("local_player") as FirstPersonController)
		await _wait(5)
	await _wait(4)


func _unstage_play() -> void:
	var play := get_tree().get_first_node_in_group("play_activities") as PlayActivities
	if play != null:
		if play.fish_state != "":
			play._end_fishing()
		play.cancel_course()
		if play.chest != null:
			play.chest.queue_free()
			play.chest = null
		play.bite_wait = -1.0
	var panel := get_tree().get_first_node_in_group("cooking_panel") as CookingPanel
	if panel != null and panel.is_open():
		panel.close()


## 一份“玩了一阵子”的状态：各世界捡了些东西、钓了几种鱼、挖到宝箱、拿了奖牌、读了石板、点亮尖塔。
func _fill_trophies() -> void:
	WorldState.collections["world_02"] = ["pearl_01", "pearl_04"]
	WorldState.collections["world_03"] = ["shard_01"]
	WorldState.collections["world_04"] = ["pearl_01", "pearl_02", "shell_01", "tablet_01", "tablet_02", "tablet_06"]
	for l in ["lore_1", "lore_2", "lore_6"]:
		WorldState.journal_add("lore", l)
	for c in ["canoe", "fox", "lighthouse"]:
		WorldState.journal_add("constellations", c)
	WorldState.flags["atlantis_spire"] = true
	WorldState.flags["visited_world_04"] = true
	WorldState.treasures["dusk_lake"] = 3
	WorldState.records["skip_best"] = 7
	WorldState.records["course:lake_trail"] = 26.4
	WorldState.records["course:dive_rings"] = 51.2
	WorldState.records["dishes"] = 2
	WorldState.catches.clear()
	for f: Array in [["perch", 3, 27.5], ["trout", 2, 41.0], ["carp", 1, 63.5], ["bream", 2, 33.0], ["lanternfish", 1, 11.5]]:
		WorldState.catches[f[0]] = {"count": f[1], "best_cm": f[2]}
	WorldState.pantry = {"fish:perch": 2, "fish:trout": 1, "fish:bream": 1}
	Play.check_achievements()
	for c in get_tree().get_nodes_in_group("trophy_cabinet"):
		(c as TrophyCabinet).refresh()


## 亚特兰蒂斯机位："solve" 五尊雕像转到位（尖塔亮、门开），"unsolve" 回到开局朝向（门关），"hour" 设时刻（白天 / 夜里的光），
## "oxygen" 氧气条的量。
func _stage_atlantis(w: World04, shot: Dictionary) -> void:
	if shot.get("solve", false):
		for st in w.statues:
			st.set_dir(st.correct)
		w.set_doors(true, true)
	if shot.get("unsolve", false):
		WorldState.flags.erase("atlantis_spire")
		for s: Dictionary in w.data["statues"]:
			for st in w.statues:
				if st.uid == StringName(s["id"]):
					st.set_dir(int(s["start"]))
		w.set_doors(false, true)
	if shot.has("hour"):
		WorldState.time_minutes = float(shot["hour"]) * 60.0
	else:
		WorldState.time_minutes = 13.0 * 60.0
	w._update_lighting(true)
	if shot.has("oxygen"):
		w.oxygen = float(shot["oxygen"])
	await _wait(10)


## "rail": "current" / "manta" 让玩家坐上洋流或蝠鲼，"progress" 走到路线的第几米。
func _stage_rail(w: World04, shot: Dictionary) -> void:
	if not shot.has("rail"):
		return
	var r := w.current_ride if str(shot["rail"]) == "current" else w.manta_ride
	r.begin(w.player)
	r.progress = float(shot.get("progress", 0.0))
	r._entry_t = 1.0
	await _wait(6)
	w.player.head.rotation.x = deg_to_rad(float(shot.get("pitch", 0.0)))
	w.player.rotation.y = r.rider_yaw()
