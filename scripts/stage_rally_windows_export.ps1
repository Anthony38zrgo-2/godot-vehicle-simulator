[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$RepositoryRoot,
    [Parameter(Mandatory = $true)][string]$GodotPath,
    [switch]$StageOnly
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$gameRoot = Join-Path $repositoryRoot 'game'
$buildRoot = Join-Path $repositoryRoot 'build'
$distributionRoot = Join-Path $repositoryRoot 'dist'
$scratchRoot = Join-Path $repositoryRoot 'scratch'
$stageRoot = Join-Path $buildRoot 'rally_export_project'
$outputDirectory = Join-Path $distributionRoot 'rally_windows'
$mediumOutputDirectory = Join-Path $scratchRoot 'rally_release'
$executablePath = Join-Path $outputDirectory 'FordEscortRS2000Rally.exe'
$mediumExecutablePath = Join-Path $mediumOutputDirectory 'FordEscortRS2000Rally.exe'
$manifestPath = Join-Path $outputDirectory 'rally_export_manifest.json'

$expectedStageRoot = [System.IO.Path]::GetFullPath($stageRoot)
if (-not $expectedStageRoot.StartsWith(([System.IO.Path]::GetFullPath($buildRoot) + [System.IO.Path]::DirectorySeparatorChar), [StringComparison]::OrdinalIgnoreCase)) {
    throw "Ruta de staging inesperada: $expectedStageRoot"
}
if (Test-Path -LiteralPath $stageRoot) {
    Remove-Item -LiteralPath $stageRoot -Recurse -Force
}
$expectedOutputDirectory = [System.IO.Path]::GetFullPath($outputDirectory)
if (-not $expectedOutputDirectory.StartsWith(([System.IO.Path]::GetFullPath($distributionRoot) + [System.IO.Path]::DirectorySeparatorChar), [StringComparison]::OrdinalIgnoreCase)) {
    throw "Ruta de salida inesperada: $expectedOutputDirectory"
}
if (Test-Path -LiteralPath $outputDirectory) {
    Remove-Item -LiteralPath $outputDirectory -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $stageRoot, $outputDirectory, $mediumOutputDirectory | Out-Null

function Copy-SourceDirectory([string]$Source, [string]$Destination) {
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    Copy-Item -Path (Join-Path $Source '*') -Destination $Destination -Recurse -Force
}

Copy-SourceDirectory (Join-Path $gameRoot 'assets\rally') (Join-Path $stageRoot 'assets\rally')
New-Item -ItemType Directory -Force -Path (Join-Path $stageRoot 'scenes\rally') | Out-Null
foreach ($sceneName in @('ford_escort_rs2000_1971.tscn', 'ford_escort_castrol.tscn', 'rally_proving_ground.tscn', 'rally_f1_head_up_display.tscn', 'russia_stage1_ford_escort_rs2000.tscn', 'rally_garage_panel.tscn')) {
    $sourceScene = Join-Path $gameRoot ('scenes\rally\' + $sceneName)
    if (-not (Test-Path -LiteralPath $sourceScene -PathType Leaf)) {
        throw "Escena Rally necesaria para el staging faltante: $sourceScene"
    }
    Copy-Item -LiteralPath $sourceScene -Destination (Join-Path $stageRoot ('scenes\rally\' + $sceneName)) -Force
}
New-Item -ItemType Directory -Force -Path (Join-Path $stageRoot 'scripts\rally') | Out-Null
foreach ($rallyScript in @('rally_escort_vehicle.gd', 'rally_vehicle_input_controller.gd', 'rally_chase_camera_rig.gd', 'rally_cockpit_animation.gd', 'rally_f1_head_up_display.gd', 'rally_proving_ground_session.gd', 'rally_russia_stage_session.gd', 'rally_track_collision_builder.gd', 'rally_stage_visual_material_adjuster.gd', 'rally_telemetry_recorder.gd', 'rally_vehicle_audio.gd', 'formula_hud_panels.gd', 'rally_stage_progress.gd', 'rally_garage_panel.gd', 'rally_setup_database.gd', 'rally_setup_catalog.gd', 'rally_competition.gd', 'rally_competition_panel.gd', 'rally_start_sequence.gd', 'rally_start_lights.gd')) {
    Copy-Item -LiteralPath (Join-Path $gameRoot ('scripts\rally\' + $rallyScript)) -Destination (Join-Path $stageRoot ('scripts\rally\' + $rallyScript)) -Force
}
Copy-SourceDirectory (Join-Path $gameRoot 'scripts\physics') (Join-Path $stageRoot 'scripts\physics')
Copy-SourceDirectory (Join-Path $gameRoot 'addons\godot-sqlite') (Join-Path $stageRoot 'addons\godot-sqlite')
Copy-SourceDirectory (Join-Path $gameRoot 'data\vehicles\ford-escort-rs2000') (Join-Path $stageRoot 'data\vehicles\ford-escort-rs2000')
Copy-SourceDirectory (Join-Path $gameRoot 'data\rally') (Join-Path $stageRoot 'data\rally')
Copy-SourceDirectory (Join-Path $gameRoot 'data\competition') (Join-Path $stageRoot 'data\competition')
Copy-SourceDirectory (Join-Path $gameRoot 'data\input') (Join-Path $stageRoot 'data\input')
Copy-SourceDirectory (Join-Path $gameRoot 'sounds\banks\EscortRS1600') (Join-Path $stageRoot 'sounds\banks\EscortRS1600')
Copy-SourceDirectory (Join-Path $gameRoot 'sounds\rally_start') (Join-Path $stageRoot 'sounds\rally_start')
Copy-SourceDirectory (Join-Path $gameRoot 'sounds\banks\commons') (Join-Path $stageRoot 'sounds\banks\commons')
Copy-SourceDirectory (Join-Path $gameRoot 'sounds\banks\surfaces') (Join-Path $stageRoot 'sounds\banks\surfaces')
# Preserve RIFF bytes for SeamlessVehicleLoop without replacing the imported
# AudioStreamWAV resources used by event sounds.
foreach ($wave in Get-ChildItem -LiteralPath (Join-Path $stageRoot 'sounds') -Filter '*.wav' -Recurse -File) {
    Copy-Item -LiteralPath $wave.FullName -Destination ($wave.FullName + '.pcm') -Force
}
Copy-SourceDirectory (Join-Path $gameRoot 'scripts\audio') (Join-Path $stageRoot 'scripts\audio')
New-Item -ItemType Directory -Force -Path (Join-Path $stageRoot 'scripts\input') | Out-Null
Copy-Item -LiteralPath (Join-Path $gameRoot 'scripts\input\input_bindings.gd') -Destination (Join-Path $stageRoot 'scripts\input\input_bindings.gd') -Force
Copy-Item -LiteralPath (Join-Path $gameRoot 'scripts\input\input_profile.gd') -Destination (Join-Path $stageRoot 'scripts\input\input_profile.gd') -Force
New-Item -ItemType Directory -Force -Path (Join-Path $stageRoot 'features\retro_hud\scenes'), (Join-Path $stageRoot 'features\retro_hud\scripts'), (Join-Path $stageRoot 'features\retro_hud\config'), (Join-Path $stageRoot 'features\retro_hud\assets') | Out-Null
Copy-Item -LiteralPath (Join-Path $gameRoot 'features\retro_hud\scenes\retro_hud_display.tscn') -Destination (Join-Path $stageRoot 'features\retro_hud\scenes\retro_hud_display.tscn') -Force
foreach ($retroScript in @('retro_hud_display.gd', 'retro_hud_config.gd', 'retro_hud_state.gd')) {
    Copy-Item -LiteralPath (Join-Path $gameRoot ('features\retro_hud\scripts\' + $retroScript)) -Destination (Join-Path $stageRoot ('features\retro_hud\scripts\' + $retroScript)) -Force
}
Copy-Item -LiteralPath (Join-Path $gameRoot 'features\retro_hud\config\retro_hud.json') -Destination (Join-Path $stageRoot 'features\retro_hud\config\retro_hud.json') -Force
Copy-Item -Path (Join-Path $gameRoot 'features\retro_hud\assets\*') -Destination (Join-Path $stageRoot 'features\retro_hud\assets') -Force
New-Item -ItemType Directory -Force -Path (Join-Path $stageRoot 'scripts\hud') | Out-Null
Copy-Item -LiteralPath (Join-Path $gameRoot 'scripts\hud\driving_controls_panel.gd') -Destination (Join-Path $stageRoot 'scripts\hud\driving_controls_panel.gd') -Force
Copy-SourceDirectory (Join-Path $gameRoot 'fonts') (Join-Path $stageRoot 'fonts')
Copy-SourceDirectory (Join-Path $gameRoot 'docs\rally') (Join-Path $stageRoot 'docs\rally')
Copy-Item -LiteralPath (Join-Path $gameRoot 'docs\rally\README.md') -Destination (Join-Path $stageRoot 'README_RALLY_MODEL.md') -Force

$projectConfiguration = @'
[application]

config/name="Formula 90s Rally - Ford Escort RS2000"
run/main_scene="res://scenes/rally/russia_stage1_ford_escort_rs2000.tscn"
config/features=PackedStringArray("4.7")

[filesystem]
import/blender/enabled=false

[autoload]

InputBindings="*res://scripts/input/input_bindings.gd"
VehicleAudioBus="*res://scripts/audio/ensure_vehicle_bus.gd"

[display]

window/size/viewport_width=1920
window/size/viewport_height=1080
window/stretch/mode="canvas_items"

[physics]

common/physics_ticks_per_second=120
3d/physics_engine="Jolt Physics"

[audio]

driver/output_latency=40

[rendering]

renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
textures/default_filters/anisotropic_filtering_level=4
'@
$projectConfiguration | Set-Content -LiteralPath (Join-Path $stageRoot 'project.godot') -Encoding ascii

$exportPreset = @'
[preset.0]

name="Windows Desktop"
platform="Windows Desktop"
runnable=true
dedicated_server=false
custom_features=""
export_filter="all_resources"
include_filter="*.json,*.md,*.txt,*.sql,*.pcm"
exclude_filter="*.blend,*.blend1"
export_path="FordEscortRS2000Rally.exe"
encryption_include_filters=""
encryption_exclude_filters=""
encrypt_pck=false
encrypt_directory=false

[preset.0.options]

custom_template/debug=""
custom_template/release=""
debug/export_console_wrapper=0
binary_format/embed_pck=true
texture_format/s3tc_bptc=true
texture_format/etc2_astc=false
binary_format/architecture="x86_64"
codesign/enable=false
codesign/identity=""
codesign/password=""
codesign/timestamp=false
codesign/timestamp_server_url=""
codesign/digest_algorithm=1
codesign/description=""
codesign/custom_options=PackedStringArray()
application/icon=""
application/console_wrapper_icon=""
application/icon_interpolation=4
application/file_version=""
application/product_version=""
application/company_name="Formula 90s"
application/product_name="Ford Escort Rally Simulator"
application/file_description="Ford Escort rally simulation using GDScript and Godot Jolt"
application/copyright="Open Formula assets used through their licenses"
application/trademarks=""
application/export_angle=0
application/export_d3d12=0
application/d3d12_agility_sdk_multiarch=true
ssh_remote_deploy/enabled=false
ssh_remote_deploy/host="user@host_ip"
ssh_remote_deploy/port="22"
ssh_remote_deploy/extra_args_ssh=""
ssh_remote_deploy/extra_args_scp=""
ssh_remote_deploy/run_script="#!/usr/bin/env bash\nexport DISPLAY=:0\n\"{temp_dir}/{exe_name}\" {cmd_args}"
ssh_remote_deploy/cleanup_script="#!/usr/bin/env bash\nkill $(pgrep -x -f \"{temp_dir}/{exe_name} {cmd_args}\")\nrm -rf \"{temp_dir}\""
'@
$exportPreset | Set-Content -LiteralPath (Join-Path $stageRoot 'export_presets.cfg') -Encoding ascii

Write-Host 'Importando proyecto de exportacion rally aislado...' -ForegroundColor Cyan
$previousErrorAction = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
& $GodotPath --headless --single-threaded-scene --path $stageRoot --import 2>&1 | Tee-Object -Variable importOutput | Write-Host
$importExitCode = $LASTEXITCODE
if ($importExitCode -eq -1073741819) {
    Write-Host 'Godot crashed while importing; retrying once with the partial import cache.' -ForegroundColor Yellow
    & $GodotPath --headless --single-threaded-scene --path $stageRoot --import 2>&1 | Tee-Object -Variable importOutput | Write-Host
    $importExitCode = $LASTEXITCODE
}
$ErrorActionPreference = $previousErrorAction
if ($importExitCode -ne 0 -or ($importOutput -join "`n") -match "SCRIPT ERROR|Parse Error") {
    throw "La importacion del proyecto de exportacion rally fallo ($importExitCode)."
}

if ($StageOnly) {
    Write-Host "Rally staging imported: $stageRoot" -ForegroundColor Green
    return
}

Write-Host 'Exportando ejecutable Windows debug autonomo...' -ForegroundColor Cyan
$previousErrorAction = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
& $GodotPath --headless --path $stageRoot --export-debug 'Windows Desktop' $mediumExecutablePath 2>&1 | Write-Host
$exportExitCode = $LASTEXITCODE
$ErrorActionPreference = $previousErrorAction
if ($exportExitCode -ne 0) {
    throw "La exportacion Windows fallo ($exportExitCode)."
}
if (-not (Test-Path -LiteralPath $mediumExecutablePath -PathType Leaf)) {
    throw "El ejecutable exportado intermedio no existe: $mediumExecutablePath"
}
if (Test-Path -LiteralPath $executablePath) {
    Remove-Item -LiteralPath $executablePath -Force
}
New-Item -ItemType HardLink -Path $executablePath -Target $mediumExecutablePath | Out-Null
if (-not (Test-Path -LiteralPath $executablePath -PathType Leaf)) {
    throw "El enlace del ejecutable exportado no existe: $executablePath"
}
Remove-Item -LiteralPath $mediumExecutablePath -Force

# Exported GDExtension DLLs must accompany the final executable, too.
foreach ($dependency in Get-ChildItem -LiteralPath $mediumOutputDirectory -Filter '*.dll' -File) {
    Copy-Item -LiteralPath $dependency.FullName -Destination $outputDirectory -Force
}

$head = (& git -C $repositoryRoot rev-parse HEAD).Trim()
$branch = (& git -C $repositoryRoot branch --show-current).Trim()
$sourceFiles = Get-ChildItem -LiteralPath $stageRoot -Recurse -File | Where-Object {
    $_.Extension -notin @('.import', '.uid') -and $_.FullName -notlike '*\.godot\*'
} | ForEach-Object {
    [ordered]@{
        path = $_.FullName.Substring($stageRoot.Length + 1).Replace('\', '/')
        sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
        size_bytes = $_.Length
    }
}
$manifest = [ordered]@{
    contract_version = 1
    created_at = (Get-Date).ToString('o')
    repository_root = $repositoryRoot
    branch = $branch
    head = $head
    scene = 'res://scenes/rally/russia_stage1_ford_escort_rs2000.tscn'
    physics_engine = 'Jolt Physics'
    export_mode = 'debug'
    executable = $executablePath
    executable_sha256 = (Get-FileHash -LiteralPath $executablePath -Algorithm SHA256).Hash
    executable_size_bytes = (Get-Item -LiteralPath $executablePath).Length
    staged_project = $stageRoot
    staged_files = $sourceFiles
    native_extension = 'godot-sqlite for saved setups; vehicle physics uses GDScript and built-in Godot Jolt'
    built_from_source = 'the isolated GDScript Rally project and local Open Formula asset manifests'
}
$manifestJson = $manifest | ConvertTo-Json -Depth 5
[System.IO.File]::WriteAllText($manifestPath, $manifestJson, (New-Object System.Text.UTF8Encoding($false)))
Write-Host ("Rally export ready: {0} ({1:N0} bytes)" -f $executablePath, (Get-Item -LiteralPath $executablePath).Length) -ForegroundColor Green
Write-Host "Rally export manifest: $manifestPath" -ForegroundColor Green
