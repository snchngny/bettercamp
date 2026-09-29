#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$BootCampPath,
    [switch]$Diagnose,
    [switch]$DownloadOnly,
    [switch]$AudioPatchOnly,
    [switch]$RepairAudio,
    [switch]$RemoveAudioPatch,
    [switch]$CleanupBootCamp,
    [switch]$SkipAudioPatch,
    [string]$LauncherSourceDirectory,
    [switch]$StageOnly
)

$ErrorActionPreference = 'Stop'
$launcherBase = Join-Path $env:LOCALAPPDATA 'BetterCamp/launcher'
$launcherRoot = Join-Path $launcherBase ([guid]::NewGuid().ToString('N'))
$commonDirectory = Join-Path $launcherRoot 'scripts'
$audioDirectory = Join-Path $launcherRoot 'Audio_2011_2012'
$launcherRevision = '5c9092bbacd01a93ddfecce0385bfe4c5488b70a'

try {
    function Get-LauncherHash([string]$Path) {
        if ([IO.Path]::GetExtension($Path) -eq '.ps1') {
            $text = [IO.File]::ReadAllText($Path).Replace("`r`n", "`n")
            $sha = [Security.Cryptography.SHA256]::Create()
            try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($text)))).Replace('-', '') }
            finally { $sha.Dispose() }
        }
        return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    }
    New-Item -ItemType Directory -Path $commonDirectory -Force | Out-Null
    New-Item -ItemType Directory -Path $audioDirectory -Force | Out-Null
    $files = @(
        @{ Name = 'bettercamp.ps1'; Destination = (Join-Path $launcherRoot 'bettercamp.ps1'); Sha256 = '220D3099CDB435F343DA27BE2F7C6EB42D23A19EC13B4509994C45705B54DF37' },
        @{ Name = 'scripts/BetterCamp.Common.ps1'; Destination = (Join-Path $commonDirectory 'BetterCamp.Common.ps1'); Sha256 = '67103F72B7F55F02D9E481B3B1D916FAB6EB90066E2A03A18A5D16461A12068A' },
        @{ Name = 'Audio_2011_2012/asl.exe'; Destination = (Join-Path $audioDirectory 'asl.exe'); Sha256 = '279AE784566DBB344539E6495CF12CC96C95BD75B189026A5488E6E4EE8A31BB' },
        @{ Name = 'Audio_2011_2012/dsdt_2012.aml'; Destination = (Join-Path $audioDirectory 'dsdt_2012.aml'); Sha256 = '9C16ADF17E7F4F6462A8E598616D81E37E4CEA8B436DD92B535F543C4AF36F87' }
    )

    foreach ($file in $files) {
        if ($LauncherSourceDirectory) {
            Copy-Item -LiteralPath (Join-Path $LauncherSourceDirectory $file.Name) -Destination $file.Destination
        } else {
            $uri = "https://raw.githubusercontent.com/snchngny/bettercamp/$launcherRevision/" + $file.Name
            Invoke-WebRequest -Uri $uri -OutFile $file.Destination -UseBasicParsing
        }
        $actualHash = Get-LauncherHash $file.Destination
        if ($actualHash -ne $file.Sha256) { throw "Launcher file verification failed: $($file.Name)" }
    }

    if ($StageOnly) { $global:LASTEXITCODE = 0; return }

    function ConvertTo-Literal([string]$Value) { return "'" + $Value.Replace("'", "''") + "'" }
    $command = '$global:LASTEXITCODE = 0; & ' + (ConvertTo-Literal (Join-Path $launcherRoot 'bettercamp.ps1'))
    if ($BootCampPath) { $command += ' -BootCampPath ' + (ConvertTo-Literal $BootCampPath) }
    if ($Diagnose) { $command += ' -Diagnose' }
    if ($DownloadOnly) { $command += ' -DownloadOnly' }
    if ($AudioPatchOnly) { $command += ' -AudioPatchOnly' }
    if ($RepairAudio) { $command += ' -RepairAudio' }
    if ($RemoveAudioPatch) { $command += ' -RemoveAudioPatch' }
    if ($CleanupBootCamp) { $command += ' -CleanupBootCamp' }
    if ($SkipAudioPatch) { $command += ' -SkipAudioPatch' }
    $command += '; exit $global:LASTEXITCODE'
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))

    & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded
    $childExitCode = $LASTEXITCODE
    if ($childExitCode -ne 0) { throw "BetterCamp stopped with exit code $childExitCode." }
    $global:LASTEXITCODE = 0
} finally {
    $resolvedBase = [IO.Path]::GetFullPath($launcherBase).TrimEnd('\') + '\'
    $resolvedRoot = [IO.Path]::GetFullPath($launcherRoot)
    if ($resolvedRoot.StartsWith($resolvedBase, [StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path $resolvedRoot -Leaf) -match '^[0-9a-f]{32}$' -and
        (Test-Path -LiteralPath $resolvedRoot)) {
        Remove-Item -LiteralPath $resolvedRoot -Recurse -Force
    }
}
