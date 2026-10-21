# 下载项目使用的 Poly Haven（CC0）PBR 贴图：1k JPG 的漫反射 / 法线(GL) / 粗糙度。
# 用法（在仓库根目录）：pwsh -File devtools/fetch_polyhaven.ps1
# 输出：assets/imported/textures/<id>/<id>_{diff,nor_gl,rough}_1k.jpg，并写 assets/imported/textures/manifest.csv（含 md5）。
# 每个文件都与 Poly Haven API 给出的 md5 核对，不一致即报错退出。

$ErrorActionPreference = "Stop"
$ids = [ordered]@{
	"leafy_grass"         = "地表：草地"
	"forest_leaves_04"    = "地表：针叶林落叶地面"
	"rocky_trail"         = "地表：土路"
	"rock_face_03"        = "地表：陡坡岩石；岩石模型"
	"brown_mud_rocks_01"  = "地表：湖岸与湖底"
	"roof_slates_02"      = "木屋：石板瓦屋面"
	"brown_planks_05"     = "木屋：室内墙板"
	"wood_floor"          = "木屋：地板"
	"weathered_planks"    = "门廊与码头木板"
	"stained_pine"        = "木梁、窗框、书架、茶几"
	"rough_pine_door"     = "木门"
	"rustic_stone_wall"   = "木屋石基"
	"slate_floor"         = "壁炉炉台"
	"wool_boucle"         = "沙发面料"
	"poly_wool_herringbone" = "地毯"
	"pine_bark"           = "针叶树树皮"
	"concrete_floor_01"   = "水族馆地面（水磨石感）"
	"floor_tiles_02"      = "泳池馆地面与池岸石材"
	"damp_beach_sand"     = "水族箱底沙"
}
$maps = @{ "Diffuse" = "diff"; "nor_gl" = "nor_gl"; "Rough" = "rough" }
$root = Join-Path $PSScriptRoot "..\assets\imported\textures"
New-Item -ItemType Directory -Force $root | Out-Null
$rows = @("asset_id,map,file,md5,bytes,source_url,usage")
foreach ($id in $ids.Keys) {
	$files = Invoke-RestMethod "https://api.polyhaven.com/files/$id" -TimeoutSec 60
	$dir = Join-Path $root $id
	New-Item -ItemType Directory -Force $dir | Out-Null
	foreach ($key in $maps.Keys) {
		$info = $files.$key.'1k'.jpg
		$name = "${id}_$($maps[$key])_1k.jpg"
		$path = Join-Path $dir $name
		$have = (Test-Path $path) -and ((Get-FileHash $path -Algorithm MD5).Hash.ToLower() -eq $info.md5)
		if (-not $have) {
			Invoke-WebRequest $info.url -OutFile $path -TimeoutSec 120
		}
		$md5 = (Get-FileHash $path -Algorithm MD5).Hash.ToLower()
		if ($md5 -ne $info.md5) { throw "md5 mismatch: $name" }
		$rows += "$id,$($maps[$key]),textures/$id/$name,$md5,$((Get-Item $path).Length),https://polyhaven.com/a/$id,$($ids[$id])"
	}
	Write-Host "ok $id"
}
[IO.File]::WriteAllText((Join-Path $root "manifest.csv"), ($rows -join "`n") + "`n", [Text.UTF8Encoding]::new($false))
