# Install (or reinstall) the Mezon native app for the current user.
# This install channel supports in-app auto-update (user-writable folder).
# usage: powershell -ExecutionPolicy Bypass -File install-windows.ps1
#        $env:MEZON_UPDATE_URL = "https://github.com/<org>/mezon-desktop/releases/latest/download/"; .\install-windows.ps1
$ErrorActionPreference = "Stop"

$BaseUrl = if ($env:MEZON_UPDATE_URL) { $env:MEZON_UPDATE_URL } else { "https://cdn.mezon.ai/release/" }
if (-not $BaseUrl.EndsWith("/")) { $BaseUrl += "/" }

$arch = switch ($env:PROCESSOR_ARCHITECTURE) {
    "AMD64" { "x86_64" }
    "ARM64" { "aarch64" }
    default { throw "unsupported architecture: $($env:PROCESSOR_ARCHITECTURE)" }
}

$manifestUrl = "${BaseUrl}latest-native-windows-${arch}.yml"
Write-Host "==> Fetching manifest $manifestUrl"
$manifest = (Invoke-WebRequest -UseBasicParsing -Uri $manifestUrl).Content

function Get-ManifestField([string]$body, [string]$key) {
    foreach ($line in $body -split "`n") {
        $trimmed = $line.Trim()
        if ($trimmed.StartsWith("${key}:")) {
            return $trimmed.Substring($key.Length + 1).Trim().Trim("'").Trim('"')
        }
    }
    return $null
}

$version = Get-ManifestField $manifest "version"
$path = Get-ManifestField $manifest "path"
$sha512 = Get-ManifestField $manifest "sha512"
if (-not $version -or -not $path -or -not $sha512) {
    throw "malformed manifest at $manifestUrl"
}

$tmp = Join-Path $env:TEMP "mezon-install-$PID"
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
try {
    $zip = Join-Path $tmp (Split-Path $path -Leaf)
    Write-Host "==> Downloading Mezon $version"
    Invoke-WebRequest -UseBasicParsing -Uri "${BaseUrl}${path}" -OutFile $zip

    Write-Host "==> Verifying checksum"
    $hashHex = (Get-FileHash -Path $zip -Algorithm SHA512).Hash
    $hashBytes = [byte[]]::new($hashHex.Length / 2)
    for ($i = 0; $i -lt $hashBytes.Length; $i++) {
        $hashBytes[$i] = [Convert]::ToByte($hashHex.Substring($i * 2, 2), 16)
    }
    $actual = [Convert]::ToBase64String($hashBytes)
    if ($actual -ne $sha512) {
        throw "checksum mismatch: expected $sha512, got $actual"
    }

    $extract = Join-Path $tmp "extract"
    Expand-Archive -Path $zip -DestinationPath $extract -Force
    $newExe = Get-ChildItem -Path $extract -Filter "mezon.exe" -Recurse | Select-Object -First 1
    if (-not $newExe) {
        throw "archive does not contain mezon.exe"
    }

    $installDir = Join-Path $env:LOCALAPPDATA "Programs\Mezon"
    New-Item -ItemType Directory -Force -Path $installDir | Out-Null
    $target = Join-Path $installDir "mezon.exe"
    if (Test-Path $target) {
        $retired = Join-Path $installDir "mezon-old-$PID.exe"
        Remove-Item -Force -ErrorAction SilentlyContinue $retired
        Move-Item -Force $target $retired
    }
    Move-Item -Force $newExe.FullName $target
    Unblock-File -Path $target -ErrorAction SilentlyContinue

    $startMenu = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs"
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut((Join-Path $startMenu "Mezon.lnk"))
    $shortcut.TargetPath = $target
    $shortcut.WorkingDirectory = $installDir
    $shortcut.Description = "Mezon desktop client"
    $shortcut.Save()

    Write-Host "==> Installed Mezon $version to $target"
    Write-Host "Launch it from the Start Menu (Mezon) or run: $target"
}
finally {
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $tmp
}
