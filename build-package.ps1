# Build script for companion-module-bpm2osc
# Workaround for zx/PowerShell ACCESS DENIED on Windows when running from OneDrive
# Equivalent to: npm run package (companion-module-build)

Set-Location $PSScriptRoot
$ErrorActionPreference = 'Stop'

$moduleDir  = $PSScriptRoot
$toolsDir   = "$moduleDir\node_modules\@companion-module\tools"
$webpack    = "$moduleDir\node_modules\.bin\webpack-cli.cmd"
$webpackCfg = "$toolsDir\webpack.config.cjs"

# ── 1. Clean pkg/ (best-effort — skip if locked by Companion) ─────────────────
if (Test-Path "$moduleDir\pkg") {
    Remove-Item "$moduleDir\pkg" -Recurse -Force -ErrorAction SilentlyContinue
}
if (-not (Test-Path "$moduleDir\pkg")) {
    New-Item "$moduleDir\pkg" -ItemType Directory | Out-Null
}
New-Item "$moduleDir\pkg\companion" -ItemType Directory -Force | Out-Null

# ── 2. Webpack bundle ──────────────────────────────────────────────────────────
Write-Host "Running webpack..."
& $webpack -c $webpackCfg --env "ROOT=$moduleDir" --env "MODULETYPE=connection"
if ($LASTEXITCODE -ne 0) { Write-Error "Webpack failed"; exit 1 }

# ── 3. Copy companion/ metadata ────────────────────────────────────────────────
Copy-Item "$moduleDir\companion" "$moduleDir\pkg\companion" -Recurse -Force

# ── 4. Patch manifest.json via Node.js (preserves UTF-8 correctly) ────────────
Write-Host "Patching manifest..."
$patchScript = "$moduleDir\_patch_manifest.mjs"
$srcPkg  = Get-Content "$moduleDir\package.json"  | ConvertFrom-Json
$basePkg = Get-Content "$moduleDir\node_modules\@companion-module\base\package.json" | ConvertFrom-Json

Set-Content $patchScript -Encoding utf8 -Value @"
import { readFileSync, writeFileSync } from 'fs'
const m = JSON.parse(readFileSync('./companion/manifest.json', 'utf8'))
m.runtime.entrypoint  = '../main.js'
m.runtime.api         = 'nodejs-ipc'
m.runtime.apiVersion  = '$($basePkg.version)'
m.version             = '$($srcPkg.version)'
m.isPrerelease        = false
writeFileSync('./pkg/companion/manifest.json', JSON.stringify(m, null, 2), 'utf8')
"@

node $patchScript
Remove-Item $patchScript

# ── 5. Write minimal package.json ─────────────────────────────────────────────
$manifest = Get-Content "$moduleDir\pkg\companion\manifest.json" | ConvertFrom-Json
$minPkg = @{
    name         = $manifest.name
    version      = $manifest.version
    license      = $manifest.license
    type         = 'commonjs'
    dependencies = @{}
} | ConvertTo-Json

$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText("$moduleDir\pkg\package.json", $minPkg, $utf8NoBom)

# ── 6. Create .tgz ────────────────────────────────────────────────────────────
$tgzName = "$($manifest.manufacturer)-$($manifest.name)-v$($manifest.version).tgz"
if (Test-Path "$moduleDir\$tgzName") { Remove-Item "$moduleDir\$tgzName" -Force }
tar -czf $tgzName pkg

$size = [math]::Round((Get-Item "$moduleDir\$tgzName").Length / 1KB, 1)
Write-Host ""
Write-Host "Package ready: $tgzName ($size KB)"
