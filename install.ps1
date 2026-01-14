# ============================
# WoWSidekick Addon Installer
# ============================
# Installs the WoWSidekick addon to your World of Warcraft installation.
# 
# Prerequisites:
#   - World of Warcraft installation at the path defined in $wowPath
#   - This script should be run from the plugin repository root
#
# Usage:
#   .\install.ps1
# ============================

$wowPath = "F:\spel\World of Warcraft\_anniversary_\Interface\AddOns"
$addonName = "WoWSidekick"
$addonPath = Join-Path $wowPath $addonName
$sourceFolder = "sidekick-plugin"

$files = @(
    "WoWSidekick.toc",
    "WoWSidekick.lua"
)

Write-Host "Installing WoWSidekick addon..." -ForegroundColor Cyan

# Verify WoW AddOns path exists
if (-not (Test-Path $wowPath)) {
    Write-Host "ERROR: WoW AddOns path not found:" -ForegroundColor Red
    Write-Host $wowPath
    exit 1
}

# Create addon folder if it doesn't exist
if (-not (Test-Path $addonPath)) {
    New-Item -ItemType Directory -Path $addonPath | Out-Null
    Write-Host "Created addon folder: $addonPath" -ForegroundColor Gray
}

# Copy addon files
foreach ($file in $files) {
    $sourcePath = Join-Path $sourceFolder $file
    
    if (-not (Test-Path $sourcePath)) {
        Write-Host "ERROR: Missing file: $sourcePath" -ForegroundColor Red
        exit 1
    }

    Copy-Item $sourcePath -Destination $addonPath -Force
    Write-Host "  [+] Installed $file" -ForegroundColor Green
}

Write-Host "`nWoWSidekick installed successfully!" -ForegroundColor Green
Write-Host "Restart World of Warcraft and enable the addon in the addons list." -ForegroundColor Cyan
