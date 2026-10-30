# Actualiza los SHA-256 del perfil local en OPEN_FORMULA_PROVENANCE.json.
# Uso: powershell -ExecutionPolicy Bypass -File .\update_hashes.ps1
$ErrorActionPreference = 'Stop'
$profileDirectory = $PSScriptRoot
$provenancePath = Join-Path $profileDirectory 'OPEN_FORMULA_PROVENANCE.json'
$text = [System.IO.File]::ReadAllText($provenancePath)
$provenance = $text | ConvertFrom-Json
$manifest = Get-Content -LiteralPath (Join-Path $profileDirectory 'vehicle.json') -Raw | ConvertFrom-Json

# Validar todos los archivos antes de modificar el registro.
$hashes = @{}
foreach ($property in $provenance.profile_json_sha256.PSObject.Properties) {
    $name = $property.Name
    if ([System.IO.Path]::GetFileName($name) -ne $name -or -not $name.EndsWith('.json')) {
        throw "Nombre de archivo de perfil no valido: $name"
    }
    $path = Join-Path $profileDirectory $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Falta el archivo: $path" }
    $null = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    $hashes[$name] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
}
foreach ($domain in $manifest.domains.PSObject.Properties) {
    if (-not $hashes.ContainsKey([string]$domain.Value)) {
        throw "El dominio $($domain.Name) no tiene entrada en profile_json_sha256: $($domain.Value)"
    }
}
if (-not $hashes.ContainsKey('vehicle.json')) { throw 'Falta vehicle.json en profile_json_sha256.' }

# Sustituir solo el bloque local, conservando el formato y los hashes de referencia.
$blockPattern = '(?s)("profile_json_sha256"\s*:\s*\{)(.*?)(\})'
$match = [regex]::Match($text, $blockPattern)
if (-not $match.Success) { throw 'No se encontro el bloque profile_json_sha256.' }
$block = $match.Groups[2].Value
foreach ($name in $hashes.Keys) {
    $entryPattern = '("' + [regex]::Escape($name) + '"\s*:\s*")[0-9a-fA-F]{64}(")'
    if ([regex]::Matches($block, $entryPattern).Count -ne 1) { throw "Entrada de hash invalida o duplicada: $name" }
    $newHash = $hashes[$name]
    $block = [regex]::Replace($block, $entryPattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $m.Groups[1].Value + $newHash + $m.Groups[2].Value })
}
$updated = $text.Substring(0, $match.Groups[2].Index) + $block + $text.Substring($match.Groups[2].Index + $match.Groups[2].Length)
if ($updated -ne $text) {
    [System.IO.File]::WriteAllText($provenancePath, $updated, [System.Text.UTF8Encoding]::new($false))
}
Write-Host "Hashes SHA-256 actualizados: $($hashes.Count) archivos de perfil."
