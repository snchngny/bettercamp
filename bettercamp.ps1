#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$BootCampPath,
    [switch]$Diagnose,
    [switch]$DownloadOnly,
    [switch]$AudioPatchOnly,
    [switch]$RemoveAudioPatch,
    [switch]$SkipAudioPatch
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'scripts/BetterCamp.Common.ps1')
try {
    if ([Environment]::OSVersion.Platform -ne 'Win32NT') { throw 'Run inside Windows on your MacBook Pro.' }
    $machine = Get-BetterCampMachine
    Write-Host "Model: $($machine.Model) | Windows build: $($machine.Build) | Firmware: $($machine.Firmware)"
    Write-Host "Graphics: $($machine.Graphics -join ', ')"
    Assert-BetterCampMachine $machine
    $operationCount = @($Diagnose, $DownloadOnly, $AudioPatchOnly, $RemoveAudioPatch).Where({ $_ }).Count
    if ($operationCount -gt 1) { throw 'Choose only one of -Diagnose, -DownloadOnly, -AudioPatchOnly or -RemoveAudioPatch.' }
    if ($Diagnose) {
        Write-Host 'Target recognized. Diagnosis complete; no drivers or boot settings were changed.'
        exit 0
    }
    if ($BootCampPath) { $BootCampPath = Resolve-BetterCampPath -Path $BootCampPath -Root $PSScriptRoot }
    if (-not $DownloadOnly -and -not (Test-BetterCampAdministrator)) {
        $command = '& ' + (ConvertTo-BetterCampLiteral $PSCommandPath)
        if ($BootCampPath) { $command += ' -BootCampPath ' + (ConvertTo-BetterCampLiteral $BootCampPath) }
        if ($AudioPatchOnly) { $command += ' -AudioPatchOnly' }
        if ($RemoveAudioPatch) { $command += ' -RemoveAudioPatch' }
        if ($SkipAudioPatch) { $command += ' -SkipAudioPatch' }
        $command += '; exit $LASTEXITCODE'
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
        $child = Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Verb RunAs -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encoded) -Wait -PassThru
        exit $child.ExitCode
    }
    $logRoot = Join-Path $env:LOCALAPPDATA 'BetterCamp/logs'
    New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
    $log = Join-Path $logRoot ('setup-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '.txt')
    Start-Transcript -LiteralPath $log | Out-Null
    try {
        if ($RemoveAudioPatch) {
            Remove-BetterCampAudioPatch -Machine $machine -Root $PSScriptRoot
        } elseif ($AudioPatchOnly) {
            Install-BetterCampAudioPatch -Machine $machine -Root $PSScriptRoot | Out-Null
        } else {
            $pack = Resolve-BetterCampPath -Path $BootCampPath -Root $PSScriptRoot
            if (-not $pack) {
                Write-Host 'Downloading Apple Boot Camp 5.1.5621 (about 925 MB).'
                Write-Host 'This is an archived 2012-compatible package, not the latest Boot Camp release.'
                $pack = Get-BetterCampPackage
            }
            $version = Get-BetterCampVersion $pack
            Write-Host "Boot Camp $version : $pack"
            if ($version -lt [version]'5.1') { throw 'Use Boot Camp 5.1.5621 or newer support software for this Mac from Boot Camp Assistant.' }
            Assert-BetterCampSignature (Join-Path $pack 'setup.exe')
            if ($DownloadOnly) {
                Write-Host "Download verified. To install later: .\Start-BetterCamp.cmd -BootCampPath `"$pack`""
            } else {
                if (-not $SkipAudioPatch -and $machine.Firmware -eq 'UEFI') {
                    if ($machine.Model -eq 'MacBookPro9,2') {
                        Install-BetterCampAudioPatch -Machine $machine -Root $PSScriptRoot | Out-Null
                    } else {
                        Write-Warning "The bundled audio table is not verified for $($machine.Model); the UEFI audio patch was not applied."
                    }
                }
                Write-Host 'The Apple installer will open. Follow its prompts. Windows 11 is not officially supported by Apple on this Mac.'
                $code = Install-BetterCampPackage $pack
                if ($code -in @(1641, 3010)) { Write-Host 'Installation succeeded; restart Windows when ready.' }
                else { Write-Host 'Installer completed. Restart Windows, then check sound, Wi-Fi and keyboard controls.' }
            }
        }
    } catch {
        Write-Host ("Error: " + $_.Exception.Message) -ForegroundColor Red
        throw
    } finally {
        Stop-Transcript | Out-Null
        Write-Host "Log: $log"
    }
    exit 0
} catch {
    Write-Host ("BetterCamp failed: " + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
