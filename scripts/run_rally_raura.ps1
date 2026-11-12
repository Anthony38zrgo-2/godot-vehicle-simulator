[CmdletBinding()]
param(
    [string]$GodotPath,
    [switch]$Import,
    [switch]$PilotOsqp,
    [switch]$PilotRelieve,
    [switch]$PilotInicio,
    [switch]$PilotEarth,
    [switch]$StageCompleto,
    [switch]$StageSr,
    [switch]$Headless,
    [ValidateRange(0, 100000)][int]$QuitAfterFrames = 0
)

$ErrorActionPreference = 'Stop'
$gameRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'game'
if (@($PilotOsqp, $PilotRelieve, $PilotInicio, $PilotEarth, $StageCompleto, $StageSr).Where({ $_ }).Count -gt 1) { throw 'Elige una sola variante de Raura.' }
$track = if ($StageSr) { 'raurasr_stage2' } elseif ($StageCompleto) { 'raura_stage2' } elseif ($PilotEarth) { 'rauraearth_stage2' } elseif ($PilotRelieve) { 'raurarelief_stage2' } elseif ($PilotOsqp) { 'raurapilot_stage2' } elseif ($PilotInicio) { 'raurastart_stage2' } else { 'raurasr_stage2' }
$scene = 'res://scenes/rally/' + $track + '.tscn'

if (-not $GodotPath) {
    $GodotPath = $env:GODOT_BIN
}
if (-not $GodotPath) {
    $GodotPath = [Environment]::GetEnvironmentVariable('GODOT_BIN', 'User')
}
if (-not $GodotPath) {
    $command = Get-Command godot, godot4 -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) {
        $GodotPath = $command.Source
    }
}
if (-not $GodotPath -or -not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw 'No encontré Godot. Indica el ejecutable con -GodotPath o configura GODOT_BIN.'
}
$godot = (Resolve-Path -LiteralPath $GodotPath).Path

foreach ($kind in @('visual', 'collision')) {
    $asset = Join-Path $gameRoot "assets/rally/$track/${track}_$kind.glb"
    if (-not (Test-Path -LiteralPath $asset -PathType Leaf)) {
        throw "Falta $asset. Genera el Stage 2 con generar_stage2.py."
    }
    $importFile = "$asset.import"
    if (-not (Test-Path -LiteralPath $importFile -PathType Leaf)) {
        $Import = $true
        continue
    }
    $remap = Select-String -LiteralPath $importFile -Pattern '^path="res://([^"]+)"$' | Select-Object -First 1
    if (-not $remap) {
        $Import = $true
        continue
    }
    $cache = Get-Item -LiteralPath (Join-Path $gameRoot $remap.Matches[0].Groups[1].Value) -ErrorAction SilentlyContinue
    if (-not $cache -or $cache.LastWriteTimeUtc -lt (Get-Item -LiteralPath $asset).LastWriteTimeUtc) {
        $Import = $true
    }
}
if ($Import) {
    & $godot --headless --path $gameRoot --import
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

$arguments = @('--path', $gameRoot)
if ($Headless) { $arguments += '--headless' }
if ($QuitAfterFrames -gt 0) { $arguments += @('--quit-after', $QuitAfterFrames) }
& $godot @arguments $scene
exit $LASTEXITCODE
