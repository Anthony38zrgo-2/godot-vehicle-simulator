[CmdletBinding()]
param(
    [string]$GodotPath,
    [switch]$ImportOnly
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$gameRoot = Join-Path $repositoryRoot 'game'
$originalAppData = $env:APPDATA
$originalLocalAppData = $env:LOCALAPPDATA
$buildLogs = Join-Path $repositoryRoot 'build\logs'
New-Item -ItemType Directory -Force -Path $buildLogs | Out-Null
$buildLog = Join-Path $buildLogs ('build_' + (Get-Date -Format 'yyyyMMdd_HHmmss_fff') + '.log')

function Resolve-BuildGodot {
    if ($GodotPath) {
        if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
            throw "GodotPath no existe: $GodotPath"
        }
        return (Resolve-Path -LiteralPath $GodotPath).Path
    }
    foreach ($candidate in @(
        $env:GODOT_BIN,
        [Environment]::GetEnvironmentVariable('GODOT_BIN', 'User'),
        (Join-Path $repositoryRoot '.tools\godot\Godot_v4.7.1-stable_win64_console.exe'),
        (Join-Path $originalLocalAppData 'Programs\Godot\4.7.1\Godot_v4.7.1-stable_win64_console.exe')
    )) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    foreach ($name in @('godot4.exe', 'godot.exe')) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if ($command) { return $command.Source }
    }
    throw 'Godot no encontrado. Configure GODOT_BIN o use -GodotPath.'
}

function Invoke-BuildGodot([string[]]$Arguments) {
    # Godot can report GDScript failures while still returning exit code zero.
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& $script:godot @Arguments 2>&1)
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
    }
    $output | Add-Content -LiteralPath $buildLog -Encoding utf8
    $failures = @($output | Where-Object { "$_" -match 'SCRIPT ERROR|Parse Error|Compile Error|^ERROR:' })
    if ($code -ne 0 -or $failures.Count -gt 0) {
        $output | ForEach-Object { Write-Host "$_" }
        throw "Godot fallo (codigo $code). Log: $buildLog"
    }
}

try {
    $script:godot = Resolve-BuildGodot
    $version = (& $script:godot --version | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $version -notmatch '^(4\.7\.\d+\.stable)') {
        throw "Se requiere Godot 4.7 estable. Version encontrada: $version"
    }
    $templateVersion = $Matches[1]
    if (-not $ImportOnly) {
        $template = Join-Path $originalAppData "Godot\export_templates\$templateVersion\windows_debug_x86_64.exe"
        if (-not (Test-Path -LiteralPath $template -PathType Leaf)) {
            throw "Falta la plantilla Windows de Godot $templateVersion`: $template. Instalela desde Godot o use -ImportOnly."
        }
    }
    Write-Host "Godot: $version" -ForegroundColor Cyan
    Write-Host "Log de compilacion: $buildLog" -ForegroundColor Cyan
    Write-Host '[1/4] Importando todos los recursos del proyecto...'
    Invoke-BuildGodot @('--headless', '--path', $gameRoot, '--editor', '--import', '--quit')

    Write-Host '[2/4] Comprobando compilacion de todos los scripts GDScript...'
    $scripts = @(Get-ChildItem -LiteralPath $gameRoot -Filter '*.gd' -Recurse -File |
        Where-Object { $_.FullName -notlike '*\.godot\*' } | Sort-Object FullName)
    foreach ($source in $scripts) {
        $relative = $source.FullName.Substring($gameRoot.Length + 1).Replace('\', '/')
        Invoke-BuildGodot @('--headless', '--path', $gameRoot, '--check-only', '--script', "res://$relative")
    }
    Write-Host ("Scripts compilados: {0}" -f $scripts.Count)

    Write-Host '[3/4] Validando perfiles, hashes y dependencias del lanzador...'
    & (Join-Path $PSScriptRoot 'run_rally.ps1') -GodotPath $script:godot -ValidateRuntimeOnly
    if ($LASTEXITCODE -ne 0) { throw 'Fallo la validacion del lanzador Rally.' }
    # The launcher isolates APPDATA for play sessions; exports need real templates.
    $env:APPDATA = $originalAppData
    $env:LOCALAPPDATA = $originalLocalAppData

    if (-not $ImportOnly) {
        Write-Host '[4/4] Compilando y empaquetando la distribucion Windows...'
        & (Join-Path $PSScriptRoot 'stage_rally_windows_export.ps1') -RepositoryRoot $repositoryRoot -GodotPath $script:godot
        $exe = Join-Path $repositoryRoot 'dist\rally_windows\FordEscortRS2000Rally.exe'
        $sqlite = Join-Path $repositoryRoot 'dist\rally_windows\libgdsqlite.windows.template_debug.x86_64.dll'
        foreach ($artifact in @($exe, $sqlite)) {
            if (-not (Test-Path -LiteralPath $artifact -PathType Leaf)) { throw "Build incompleto: $artifact" }
        }
        Write-Host "Juego listo: $exe" -ForegroundColor Green
    } else {
        Write-Host '[4/4] Exportacion omitida por -ImportOnly.'
    }
    Write-Host 'Build completado. Puede ejecutar scripts\run_rally.ps1.' -ForegroundColor Green
} finally {
    $env:APPDATA = $originalAppData
    $env:LOCALAPPDATA = $originalLocalAppData
}
