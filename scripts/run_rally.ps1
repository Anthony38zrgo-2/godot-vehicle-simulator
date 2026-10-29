[CmdletBinding()]
param(
    [string]$GodotPath,
    [switch]$Smoke,
    [switch]$ValidateRuntimeOnly,
    [switch]$ExportWindows,
    [switch]$ProvingGround,
    [ValidateRange(0, 100000)][int]$QuitAfterFrames = 0
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$gameRoot = Join-Path $repositoryRoot 'game'
$hostAppData = $env:APPDATA
$hostLocalAppData = $env:LOCALAPPDATA
$rallyScene = if ($ProvingGround) {
    'res://scenes/rally/rally_proving_ground.tscn'
} else {
    'res://scenes/rally/russia_stage1_ford_escort_rs2000.tscn'
}
$fordManifestPath = Join-Path $gameRoot 'assets\rally\ford_escort_rs2000_1971\manifest.json'
$stageManifestPath = Join-Path $gameRoot 'assets\rally\russia_stage1\manifest.json'
$vehicleProfilePath = Join-Path $gameRoot 'data\vehicles\ford-escort-rs2000\vehicle.json'
$profileDirectory = Join-Path $gameRoot 'data\vehicles\ford-escort-rs2000'
$provenancePath = Join-Path $profileDirectory 'OPEN_FORMULA_PROVENANCE.json'
$projectPath = Join-Path $gameRoot 'project.godot'

function Resolve-Godot([string]$ExplicitPath) {
    if ($ExplicitPath -and (Test-Path -LiteralPath $ExplicitPath -PathType Leaf)) {
        return (Resolve-Path -LiteralPath $ExplicitPath).Path
    }
    if ($env:GODOT_BIN -and (Test-Path -LiteralPath $env:GODOT_BIN -PathType Leaf)) {
        return (Resolve-Path -LiteralPath $env:GODOT_BIN).Path
    }
    # The desktop app may predate a global per-user installation. Read its
    # persisted setting too, without requiring the user to restart the app.
    $userGodotBin = [Environment]::GetEnvironmentVariable('GODOT_BIN', 'User')
    if ($userGodotBin -and (Test-Path -LiteralPath $userGodotBin -PathType Leaf)) {
        return (Resolve-Path -LiteralPath $userGodotBin).Path
    }
    $neighboringFormula90sTools = Join-Path (Split-Path -Parent $repositoryRoot) 'Formula90s\.tools\godot'
    foreach ($candidate in @(
        (Join-Path $repositoryRoot '.tools\godot\Godot_v4.7.1-stable_win64_console.exe'),
        (Join-Path $repositoryRoot '.tools\godot\Godot_v4.7.1-stable_win64.exe'),
        (Join-Path $repositoryRoot '.tools\godot\godot.exe'),
        (Join-Path $neighboringFormula90sTools 'Godot_v4.7.1-stable_win64_console.exe'),
        (Join-Path $neighboringFormula90sTools 'Godot_v4.7.1-stable_win64.exe'),
        (Join-Path $neighboringFormula90sTools 'godot.exe')
    )) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    foreach ($commandName in @('godot4.exe', 'godot.exe')) {
        $command = Get-Command $commandName -ErrorAction SilentlyContinue
        if ($command) {
            return $command.Source
        }
    }
    throw 'Godot no encontrado en GODOT_BIN (sesion o usuario), las herramientas locales ni PATH. Use -GodotPath o defina GODOT_BIN.'
}

function Assert-File([string]$Path, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Label faltante: $Path"
    }
}

function Assert-ManifestArtifact([string]$BaseDirectory, [string]$RelativePath, [string]$ExpectedHash, [string]$Label) {
    $absolutePath = Join-Path $BaseDirectory ($RelativePath.Replace('/', '\'))
    Assert-File $absolutePath $Label
    $actualHash = (Get-FileHash -LiteralPath $absolutePath -Algorithm SHA256).Hash
    if (-not $actualHash.Equals($ExpectedHash, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Hash inesperado para $Label`: $RelativePath"
    }
}

function Get-ProjectSetting([string]$Path, [string]$SettingName) {
    $content = Get-Content -LiteralPath $Path -Raw
    $pattern = '(?m)^' + [regex]::Escape($SettingName) + '=(.+)$'
    $match = [regex]::Match($content, $pattern)
    if (-not $match.Success) {
        return $null
    }
    return $match.Groups[1].Value.Trim().Trim('"')
}

function Write-LauncherLog([string]$Path, [string[]]$Lines) {
    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        New-Item -ItemType Directory -Force -Path $directory | Out-Null
    }
    $Lines | Set-Content -LiteralPath $Path -Encoding utf8
}

if (-not (Test-Path -LiteralPath $projectPath -PathType Leaf)) {
    throw "Proyecto Godot faltante: $projectPath"
}
if ((Get-ProjectSetting $projectPath '3d/physics_engine') -ne 'Jolt Physics') {
    throw 'La sesion rally exige 3d/physics_engine="Jolt Physics" en game/project.godot.'
}
Assert-File $vehicleProfilePath 'Manifiesto de dominios del Ford'
Assert-File $provenancePath 'Hashes de procedencia Open Formula'
Assert-File $fordManifestPath 'Manifest del Ford'
Assert-File $stageManifestPath 'Manifest de Rusia Stage 1'
foreach ($physicsModule in @('profile_loader.gd', 'mass_model.gd', 'suspension_model.gd', 'tire_model.gd', 'powertrain_model.gd', 'brake_model.gd', 'aerodynamic_model.gd', 'thermal_model.gd', 'vehicle_simulation.gd')) {
    Assert-File (Join-Path $gameRoot ('scripts\physics\' + $physicsModule)) ('Modulo de fisicas ' + $physicsModule)
}
Assert-File (Join-Path $gameRoot 'scripts\rally\rally_escort_vehicle.gd') 'Controlador GDScript del Ford'
Assert-File (Join-Path $gameRoot 'docs\rally\README.md') 'Documentacion del modelo Rally'
Assert-File (Join-Path $gameRoot 'data\input\input_profile.json') 'Perfil de entrada'
Assert-File (Join-Path $gameRoot 'fonts\D-DINCondensed-Bold.ttf') 'Fuente del HUD'
Assert-File (Join-Path $gameRoot 'scenes\rally\rally_f1_head_up_display.tscn') 'HUD F1 para rally'
Assert-File (Join-Path $gameRoot 'features\retro_hud\scenes\retro_hud_display.tscn') 'Escena RetroHud F1'
Assert-File (Join-Path $gameRoot 'features\retro_hud\scripts\retro_hud_display.gd') 'Script RetroHud F1'
Assert-File (Join-Path $gameRoot 'scripts\hud\driving_controls_panel.gd') 'Panel de controles F1'

$vehicleManifest = Get-Content -LiteralPath $vehicleProfilePath -Raw | ConvertFrom-Json
if ([int]$vehicleManifest.schema_version -lt 1 -or [string]$vehicleManifest.units -ne 'SI' -or [string]$vehicleManifest.vehicle_identifier -ne 'ford_escort_rs2000_1971') {
    throw 'El manifiesto de dominios del Ford no cumple el contrato de unidades e identificador.'
}
$provenance = Get-Content -LiteralPath $provenancePath -Raw | ConvertFrom-Json
$manifestHashProperty = $provenance.profile_json_sha256.PSObject.Properties['vehicle.json']
if ($null -eq $manifestHashProperty -or -not (Get-FileHash -LiteralPath $vehicleProfilePath -Algorithm SHA256).Hash.Equals([string]$manifestHashProperty.Value, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Hash de procedencia inesperado para vehicle.json.'
}
foreach ($domainProperty in $vehicleManifest.domains.PSObject.Properties) {
    $domainPath = Join-Path $profileDirectory ([string]$domainProperty.Value)
    Assert-File $domainPath ('Dominio del perfil ' + $domainProperty.Name)
    $domainJson = Get-Content -LiteralPath $domainPath -Raw | ConvertFrom-Json
    if ($null -eq $domainJson) {
        throw "El dominio del perfil no es JSON valido: $($domainProperty.Name)"
    }
    $hashProperty = $provenance.profile_json_sha256.PSObject.Properties[[string]$domainProperty.Value]
    $expectedDomainHash = if ($hashProperty) { [string]$hashProperty.Value } else { '' }
    if ($expectedDomainHash) {
        $actualDomainHash = (Get-FileHash -LiteralPath $domainPath -Algorithm SHA256).Hash
        if (-not $actualDomainHash.Equals($expectedDomainHash, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Hash de procedencia inesperado para el dominio $($domainProperty.Name)."
        }
    }
}

$fordManifest = Get-Content -LiteralPath $fordManifestPath -Raw | ConvertFrom-Json
if ([int]$fordManifest.contract_version -ne 1 -or [string]$fordManifest.vehicle_id -ne 'ford_escort_rs2000_1971') {
    throw 'El manifest del Ford no cumple el contrato rally.'
}
$fordDirectory = Split-Path -Parent $fordManifestPath
Assert-ManifestArtifact $fordDirectory ([string]$fordManifest.chassis.path) ([string]$fordManifest.chassis.sha256) 'Chassis del Ford'
foreach ($wheelProperty in $fordManifest.wheels.PSObject.Properties) {
    Assert-ManifestArtifact $fordDirectory ([string]$wheelProperty.Value.path) ([string]$wheelProperty.Value.sha256) ("Rueda " + $wheelProperty.Name)
}
Assert-ManifestArtifact $fordDirectory ([string]$fordManifest.collision.path) ([string]$fordManifest.collision.sha256) 'Colision del Ford'

$stageManifest = Get-Content -LiteralPath $stageManifestPath -Raw | ConvertFrom-Json
if ([int]$stageManifest.contract_version -ne 1 -or [string]$stageManifest.track_id -ne 'russia_stage1') {
    throw 'El manifest de Rusia Stage 1 no cumple el contrato rally.'
}
$stageDirectory = Split-Path -Parent $stageManifestPath
Assert-ManifestArtifact $stageDirectory ([string]$stageManifest.visual.path) ([string]$stageManifest.visual.sha256) 'Visual de Rusia Stage 1'
Assert-ManifestArtifact $stageDirectory ([string]$stageManifest.collision.path) ([string]$stageManifest.collision.sha256) 'Colision de Rusia Stage 1'

$vehicleSceneText = Get-Content -LiteralPath (Join-Path $gameRoot 'scenes\rally\ford_escort_rs2000_1971.tscn') -Raw
$vehicleScriptText = Get-Content -LiteralPath (Join-Path $gameRoot 'scripts\rally\rally_escort_vehicle.gd') -Raw
if ($vehicleSceneText -match 'RayCast3D' -or $vehicleSceneText -match 'rally_escort_wheel.gd' -or $vehicleScriptText -notmatch 'extends RigidBody3D') {
    throw 'La escena activa del Ford no cumple el contrato de un cuerpo Jolt y rayos administrados por GDScript.'
}
if (-not $vehicleManifest.domains.suspension) {
    throw 'vehicle.json no resuelve el dominio de suspensión.'
}

$godot = Resolve-Godot $GodotPath
$godotVersion = (& $godot --version).Trim()
if ($godotVersion -notmatch '^4\.') {
    throw "Godot incompatible: $godotVersion. Se requiere Godot 4.x."
}

$runIdentifier = Get-Date -Format 'yyyyMMdd_HHmmss'
$logDirectory = Join-Path $gameRoot 'logs\rally'
$launcherLogPath = Join-Path $logDirectory ("rally_launcher_" + $runIdentifier + ".log")
$godotLogPath = Join-Path $logDirectory ("rally_godot_" + $runIdentifier + ".log")
$telemetryPath = Join-Path $logDirectory ("rally_telemetry_" + $runIdentifier + ".csv")
New-Item -ItemType Directory -Force -Path $logDirectory | Out-Null

$branch = (& git -C $repositoryRoot branch --show-current).Trim()
$head = (& git -C $repositoryRoot rev-parse HEAD).Trim()
$status = @(& git -C $repositoryRoot status --short)
$buildSourcePath = Join-Path $gameRoot 'BUILD_SOURCE'
$buildSource = if (Test-Path -LiteralPath $buildSourcePath -PathType Leaf) { (Get-Content -LiteralPath $buildSourcePath -Raw).Trim() } else { 'missing' }
$metadata = [ordered]@{
    run_identifier = $runIdentifier
    created_at = (Get-Date).ToString('o')
    repository_root = $repositoryRoot
    branch = $branch
    head = $head
    pending_change_count = $status.Count
    build_source = $buildSource
    build_source_matches_head = ($buildSource -eq $head)
    godot = $godotVersion
    scene = $rallyScene
    physics_engine = (Get-ProjectSetting $projectPath '3d/physics_engine')
    physics_ticks_per_second = (Get-ProjectSetting $projectPath 'common/physics_ticks_per_second')
    vehicle_id = 'ford_escort_rs2000_1971'
    track_id = 'russia_stage1'
    ford_manifest_sha256 = (Get-FileHash -LiteralPath $fordManifestPath -Algorithm SHA256).Hash
    stage_manifest_sha256 = (Get-FileHash -LiteralPath $stageManifestPath -Algorithm SHA256).Hash
    vehicle_manifest_sha256 = (Get-FileHash -LiteralPath $vehicleProfilePath -Algorithm SHA256).Hash
    vehicle_profile_domains = $vehicleManifest.domains.PSObject.Properties.Count
    active_vehicle = 'GDScript RigidBody3D + Godot Jolt'
}
$metadataJson = $metadata | ConvertTo-Json -Depth 4
$launcherLines = @(
    'FORMULA 90s RALLY SESSION',
    '========================',
    $metadataJson,
    '',
    'Rally launcher validated the Ford domain profile, Russia Stage 1, GDScript physics modules, Jolt and input resources.',
    'The active vehicle uses no Rust vehicle-physics bridge and no Open Formula source was modified.'
)
Write-LauncherLog $launcherLogPath $launcherLines
Write-Host "Rally log: $launcherLogPath" -ForegroundColor Cyan
Write-Host "Godot log: $godotLogPath" -ForegroundColor Cyan
Write-Host "Telemetry: $telemetryPath" -ForegroundColor Cyan

$runtimeAppData = Join-Path $repositoryRoot '.tools\appdata'
$runtimeLocalAppData = Join-Path $repositoryRoot '.tools\localappdata'
New-Item -ItemType Directory -Force -Path $runtimeAppData, $runtimeLocalAppData | Out-Null
$env:APPDATA = (Resolve-Path -LiteralPath $runtimeAppData).Path
$env:LOCALAPPDATA = (Resolve-Path -LiteralPath $runtimeLocalAppData).Path

$importMarker = Join-Path $gameRoot '.godot\imported'
$needsImport = -not (Test-Path -LiteralPath $importMarker -PathType Container)
foreach ($artifact in @(
    (Join-Path $gameRoot 'assets\rally\ford_escort_rs2000_1971\ford_escort_rs2000_1971_chassis.glb'),
    (Join-Path $gameRoot 'assets\rally\ford_escort_rs2000_1971\ford_escort_rs2000_1971_wheel_front_left.glb'),
    (Join-Path $gameRoot 'assets\rally\ford_escort_rs2000_1971\ford_escort_rs2000_1971_wheel_front_right.glb'),
    (Join-Path $gameRoot 'assets\rally\ford_escort_rs2000_1971\ford_escort_rs2000_1971_wheel_rear_left.glb'),
    (Join-Path $gameRoot 'assets\rally\ford_escort_rs2000_1971\ford_escort_rs2000_1971_wheel_rear_right.glb'),
    (Join-Path $gameRoot 'assets\rally\russia_stage1\russia_stage1_visual.glb'),
    (Join-Path $gameRoot 'assets\rally\russia_stage1\russia_stage1_collision.glb')
)) {
    if (-not (Test-Path -LiteralPath ($artifact + '.import') -PathType Leaf)) {
        $needsImport = $true
    }
}
foreach ($audioFile in Get-ChildItem -LiteralPath (Join-Path $gameRoot 'sounds\banks\ford_escort_rs2000_rally') -Filter '*.wav' -File) {
    if (-not (Test-Path -LiteralPath ($audioFile.FullName + '.import') -PathType Leaf)) {
        $needsImport = $true
    }
}
if ($needsImport) {
    Write-Host 'Importando recursos Godot del experimento rally...' -ForegroundColor Yellow
    & $godot --headless --path $gameRoot --import
    if ($LASTEXITCODE -ne 0) {
        throw "Godot no pudo importar los recursos rally ($LASTEXITCODE)."
    }
}

if ($Smoke) {
	$acceptanceLog = Join-Path $logDirectory ("rally_gdscript_smoke_" + $runIdentifier + ".log")
	Write-Host 'Comprobando controles, contactos y evolución térmica del Ford en el campo de pruebas...' -ForegroundColor Cyan
    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
	$smokeOutput = & $godot --headless --path $gameRoot --log-file $acceptanceLog --quit-after 900 'res://scenes/rally/rally_proving_ground.tscn' -- --rally-smoke 2>&1
    $acceptanceExitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousErrorAction
	$smokeOutput | Write-Host
	$smokeLogText = if (Test-Path -LiteralPath $acceptanceLog) { Get-Content -LiteralPath $acceptanceLog -Raw } else { '' }
	if ($acceptanceExitCode -ne 0 -or -not (($smokeOutput -join "`n") + $smokeLogText).Contains('RALLY_GDSCRIPT_SMOKE')) {
		throw "La comprobación GDScript del Ford falló o no emitió evidencia. Log: $acceptanceLog"
	}
    $evidenceMatch = [regex]::Match(($smokeOutput -join "`n") + $smokeLogText, 'RALLY_GDSCRIPT_SMOKE (\{[^\r\n]+\})')
    if (-not $evidenceMatch.Success -or -not ($evidenceMatch.Groups[1].Value | ConvertFrom-Json).passed -or (($smokeOutput -join "`n") -match 'SCRIPT ERROR|Parse Error')) {
        throw "Smoke contains errors or failed evidence: $acceptanceLog"
    }

	Write-Host "Comprobación GDScript completada. Log: $acceptanceLog" -ForegroundColor Green
    exit 0
}

if ($ValidateRuntimeOnly) {
	Write-Host 'Comprobando escaneo de scripts y recursos del proyecto Godot...' -ForegroundColor Cyan
	& $godot --headless --path $gameRoot --editor --quit
	if ($LASTEXITCODE -ne 0) {
		throw "El escaneo del proyecto Godot falló ($LASTEXITCODE)."
	}
	Write-Host 'Proyecto GDScript/Jolt importado sin abrir la sesión.' -ForegroundColor Green
    exit 0
}

if ($ExportWindows) {
    $env:APPDATA = $hostAppData
    $env:LOCALAPPDATA = $hostLocalAppData
    $templateRoot = Join-Path $hostAppData 'Godot\export_templates\4.7.1.stable'
    $debugTemplate = Join-Path $templateRoot 'windows_debug_x86_64.exe'
    if (-not (Test-Path -LiteralPath $debugTemplate -PathType Leaf)) {
        throw "Plantilla de exportacion Windows faltante: $debugTemplate"
    }
	$exportScript = Join-Path $PSScriptRoot 'stage_rally_windows_export.ps1'
    Assert-File $exportScript 'Script de staging del ejecutable rally'
    Write-Host 'Preparando proyecto de exportacion rally aislado (sin extension nativa F1)...' -ForegroundColor Cyan
    & $exportScript -RepositoryRoot $repositoryRoot -GodotPath $godot
    if ($LASTEXITCODE -ne 0) {
        throw "La exportacion Windows rally fallo ($LASTEXITCODE)."
    }
    exit 0
}

Write-Host "Iniciando Rusia Stage 1 con Ford Escort RS2000 1971" -ForegroundColor Green
$previousErrorAction = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$runArguments = @('--path', $gameRoot, '--log-file', $godotLogPath)
if ($QuitAfterFrames -gt 0) {
    $runArguments += @('--quit-after', [string]$QuitAfterFrames)
}
$runArguments += @($rallyScene, '--', "--rally-run-id=$runIdentifier", "--rally-telemetry=$telemetryPath", "--rally-log=$launcherLogPath")
& $godot @runArguments
$rallyExitCode = $LASTEXITCODE
$ErrorActionPreference = $previousErrorAction
exit $rallyExitCode
