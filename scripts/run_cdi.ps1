[CmdletBinding()]
param(
    [string]$GodotPath,
    [switch]$Import,
    [switch]$Headless,
    [ValidateRange(0, 100000)][int]$QuitAfterFrames = 0
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$gameRoot = Join-Path $repositoryRoot 'game'
$scene = 'res://scenes/rally/rally_maniac_menu.tscn'

if (-not $GodotPath) { $GodotPath = $env:GODOT_BIN }
if (-not $GodotPath) { $GodotPath = [Environment]::GetEnvironmentVariable('GODOT_BIN', 'User') }
if (-not $GodotPath) {
    $command = Get-Command godot, godot4 -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { $GodotPath = $command.Source }
}
if (-not $GodotPath -or -not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw 'No se encontro Godot. Indica -GodotPath o configura GODOT_BIN.'
}
$godot = (Resolve-Path -LiteralPath $GodotPath).Path
$assetPaths = foreach ($track in @('cdi_stage1', 'cdi_stage2', 'cdi_stage3', 'cdi_stage4')) {
    $assetsRoot = Join-Path $gameRoot "assets/rally/$track"
    $sectorRoot = Join-Path $assetsRoot 'sectores'
    $sectorIndexPath = Join-Path $sectorRoot 'index.json'
    if (-not (Test-Path -LiteralPath $sectorIndexPath -PathType Leaf)) {
        throw "Falta el indice de sectores de $track. Consulta PLAN_SS01.md para regenerarlo."
    }
    $sectorIndex = Get-Content -LiteralPath $sectorIndexPath -Raw | ConvertFrom-Json
    Join-Path $assetsRoot "${track}_visual.glb"
    Join-Path $assetsRoot "${track}_collision.glb"
    foreach ($sector in $sectorIndex.sectors) { Join-Path $sectorRoot $sector.file }
    Join-Path $assetsRoot 'puna_seca/pastizal_gis.png'
    if ($track -eq 'cdi_stage4') {
        Join-Path $assetsRoot 'puna_seca/nieve_gis.png'
        Join-Path $assetsRoot 'cuneta_v.png'
    }
}
$assetPaths += @(Get-ChildItem -LiteralPath (Join-Path $gameRoot 'assets/rally/cdi_stage1/puna_seca') -Filter '*.png' -File |
    ForEach-Object { $_.FullName })

$assetPaths += @(Get-ChildItem -LiteralPath (Join-Path $gameRoot 'assets/rally/CDI/asfalto_estepa') -Filter '*.png' -File |
    ForEach-Object { $_.FullName })
$assetPaths += @(Get-ChildItem -LiteralPath (Join-Path $gameRoot 'assets/rally/CDI/nieve_ticlio') -Filter '*.png' -File |
    ForEach-Object { $_.FullName })
$assetPaths += @(Get-ChildItem -LiteralPath (Join-Path $gameRoot 'assets/weather/tropospheric') -Filter '*.png' -File |
    ForEach-Object { $_.FullName })
$assetPaths += @(Get-ChildItem -LiteralPath (Join-Path $gameRoot 'assets/rally/cdi_stage4/parked') -Filter '*.glb' -File |
    ForEach-Object { $_.FullName })
$assetPaths += @(Get-ChildItem -LiteralPath (Join-Path $gameRoot 'assets/rally/CDI/senaletica/caras_mtc') -Filter '*.png' -File |
    ForEach-Object { $_.FullName })
$assetPaths += @(Get-ChildItem -LiteralPath (Join-Path $gameRoot 'assets/rally/cdi_stage4/monumentos') -Filter '*.glb' -File |
    ForEach-Object { $_.FullName })
$assetPaths += @(Get-ChildItem -LiteralPath (Join-Path $gameRoot 'assets/rally/cdi_stage4/construcciones') -Filter '*.glb' -File |
    ForEach-Object { $_.FullName })
$assetPaths += @(Get-ChildItem -LiteralPath (Join-Path $gameRoot 'assets/rally/cdi_stage1/ichu') -Filter '*.glb' -File |
    ForEach-Object { $_.FullName })
$assetPaths += @(Get-ChildItem -LiteralPath (Join-Path $gameRoot 'assets/rally/rt/rt-alpine-a110') -Filter '*.glb' -File |
    ForEach-Object { $_.FullName })
$assetPaths += @(Get-ChildItem -LiteralPath (Join-Path $gameRoot 'assets/rally/rt/rt-mini-cooper-s') -Filter '*.glb' -File |
    ForEach-Object { $_.FullName })
$assetPaths += @(Get-ChildItem -LiteralPath (Join-Path $gameRoot 'assets/rally/rt/rt-lancia-stratos') -Filter '*.glb' -File |
    ForEach-Object { $_.FullName })
$assetPaths += @(Get-ChildItem -LiteralPath (Join-Path $gameRoot 'assets/rally/rt/rt-porsche-356b-2000gs') -Filter '*.glb' -File |
    ForEach-Object { $_.FullName })
$assetPaths += @(Get-ChildItem -LiteralPath (Join-Path $gameRoot 'assets/rally/ford_f100_1970') -Filter '*.glb' -File |
    ForEach-Object { $_.FullName })
$assetPaths += @(Get-ChildItem -LiteralPath (Join-Path $gameRoot 'assets/rally/ford_mustang_1967_289_2v') -Filter '*.glb' -File |
    ForEach-Object { $_.FullName })
$assetPaths += @(Get-ChildItem -LiteralPath (Join-Path $gameRoot 'assets/rally/porsche_911_24s') -Filter '*.glb' -File |
    ForEach-Object { $_.FullName })
$assetPaths += @(Get-ChildItem -LiteralPath (Join-Path $gameRoot 'assets/rally/lancia_fulvia') -Filter '*.glb' -File |
    ForEach-Object { $_.FullName })
$assetPaths += @(Get-ChildItem -LiteralPath (Join-Path $gameRoot 'assets/rally/fiat_131_abarth') -Filter '*.glb' -File |
    ForEach-Object { $_.FullName })
$assetPaths += @(Get-ChildItem -LiteralPath (Join-Path $gameRoot 'assets/rally/vw_golf_mk1') -Filter '*.glb' -File |
    ForEach-Object { $_.FullName })
$assetPaths += @(Get-ChildItem -LiteralPath (Join-Path $gameRoot 'assets/rally/ford_escort_rs2000_1971') -Filter '*.glb' -File |
    ForEach-Object { $_.FullName })
$assetPaths += @(Get-ChildItem -LiteralPath (Join-Path $gameRoot 'assets/rally/gaz_24_24_volga') -Filter '*.glb' -File |
    ForEach-Object { $_.FullName })
$assetPaths += @(Get-ChildItem -LiteralPath (Join-Path $gameRoot 'assets/rally/liveries') -Filter '*.png' -File |
    ForEach-Object { $_.FullName })
foreach ($assetPath in $assetPaths) {
    $asset = Get-Item -LiteralPath $assetPath -ErrorAction SilentlyContinue
    if (-not $asset) { throw "Falta la malla $assetPath. Consulta PLAN_SS01.md para regenerarla." }
    $sidecar = "$($asset.FullName).import"
    $remap = if (Test-Path -LiteralPath $sidecar) {
        Select-String -LiteralPath $sidecar -Pattern '^path="res://([^"]+)"$' | Select-Object -First 1
    }
    $cache = if ($remap) {
        Get-Item -LiteralPath (Join-Path $gameRoot $remap.Matches[0].Groups[1].Value) -ErrorAction SilentlyContinue
    }
    if (-not $cache -or $cache.LastWriteTimeUtc -lt $asset.LastWriteTimeUtc) { $Import = $true }
}
if ($Import) {
    & $godot --headless --path $gameRoot --import
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

$arguments = @('--path', $gameRoot)
if ($Headless) { $arguments += '--headless' }
if ($QuitAfterFrames -gt 0) { $arguments += @('--quit-after', $QuitAfterFrames) }
& $godot @arguments $scene -- --rally-cdi
exit $LASTEXITCODE
