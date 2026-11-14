#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$BootCampPath,
    [ValidateSet('Macmini8,1', 'MacBookPro9,2')][string]$TargetModel,
    [switch]$Diagnose,
    [switch]$DownloadOnly,
    [switch]$AudioPatchOnly,
    [switch]$RepairAudio,
    [switch]$RepairBluetooth,
    [switch]$RemoveAudioPatch,
    [switch]$CleanupBootCamp,
    [switch]$SkipAudioPatch
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'scripts/BetterCamp.Common.ps1')
. (Join-Path $PSScriptRoot 'scripts/BetterCamp.Macmini.ps1')
try {
    if ([Environment]::OSVersion.Platform -ne 'Win32NT') { throw 'Run inside Windows.' }
    $machine = Get-BetterCampMachine
    Write-Host "Model: $($machine.Model) | Windows build: $($machine.Build) | Firmware: $($machine.Firmware)"
    Write-Host "Graphics: $($machine.Graphics -join ', ')"
    $operationCount = @($Diagnose, $DownloadOnly, $AudioPatchOnly, $RepairAudio, $RepairBluetooth, $RemoveAudioPatch, $CleanupBootCamp).Where({ $_ }).Count
    if ($operationCount -gt 1) { throw 'Choose only one operation mode.' }
    if ($TargetModel -and -not $DownloadOnly) { throw '-TargetModel is only allowed with -DownloadOnly; installation always uses the actual Mac model.' }
    $packageMachine = $machine
    if ($TargetModel) {
        $packageMachine = [pscustomobject]@{Model=$TargetModel;Build=$machine.Build;Is64Bit=$machine.Is64Bit}
    }
    Assert-BetterCampMachine $packageMachine
    if ($machine.Model -eq 'Macmini8,1' -and ($AudioPatchOnly -or $RepairAudio -or $RemoveAudioPatch)) {
        throw 'The 2012 MacBook Pro audio patch must not be applied to Mac mini 2018.'
    }
    if ($Diagnose) {
        if ($machine.Model -eq 'Macmini8,1') { Show-BetterCampMacminiDiagnosis }
        else { Show-BetterCampAudioDiagnosis -Root $PSScriptRoot -Machine $machine }
        Write-Host 'Target recognized. Diagnosis complete; no drivers or boot settings were changed.'
        exit 0
    }
    if ($BootCampPath) {
        if ($packageMachine.Model -eq 'Macmini8,1') { $BootCampPath = Resolve-BetterCampMacminiPath -Path $BootCampPath -Root $PSScriptRoot }
        else { $BootCampPath = Resolve-BetterCampPath -Path $BootCampPath -Root $PSScriptRoot }
    }
    if (-not $DownloadOnly -and -not $RepairBluetooth -and -not (Test-BetterCampAdministrator)) {
        $command = '$global:LASTEXITCODE = 0; & ' + (ConvertTo-BetterCampLiteral $PSCommandPath)
        if ($BootCampPath) { $command += ' -BootCampPath ' + (ConvertTo-BetterCampLiteral $BootCampPath) }
        if ($AudioPatchOnly) { $command += ' -AudioPatchOnly' }
        if ($RepairAudio) { $command += ' -RepairAudio' }
        if ($RepairBluetooth) { $command += ' -RepairBluetooth' }
        if ($RemoveAudioPatch) { $command += ' -RemoveAudioPatch' }
        if ($CleanupBootCamp) { $command += ' -CleanupBootCamp' }
        if ($SkipAudioPatch) { $command += ' -SkipAudioPatch' }
        $command += '; exit $global:LASTEXITCODE'
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
        $child = Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Verb RunAs -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encoded) -Wait -PassThru
        exit $child.ExitCode
    }
    $logRoot = Join-Path $env:LOCALAPPDATA 'BetterCamp/logs'
    New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
    $log = Join-Path $logRoot ('setup-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '.txt')
    Start-Transcript -LiteralPath $log | Out-Null
    try {
        if ($RepairBluetooth) {
            Repair-BetterCampMacminiBluetooth -Machine $machine | Out-Null
        } elseif ($RemoveAudioPatch) {
            Remove-BetterCampAudioPatch -Machine $machine -Root $PSScriptRoot
        } elseif ($CleanupBootCamp) {
            Remove-BetterCampSoftware
        } elseif ($AudioPatchOnly) {
            Install-BetterCampAudioPatch -Machine $machine -Root $PSScriptRoot | Out-Null
        } elseif ($packageMachine.Model -eq 'Macmini8,1') {
            $pack = Resolve-BetterCampMacminiPath -Path $BootCampPath -Root $PSScriptRoot
            if (-not $pack) { $pack = Get-BetterCampMacminiPackage }
            Assert-BetterCampMacminiPackage $pack
            if ($DownloadOnly) {
                Write-Host "Mac mini 2018 package verified: $pack"
                Write-Host "Copy this complete folder to USB for offline installation. On the target Mac, run: .\Start-BetterCamp.cmd -BootCampPath `"$pack`""
            } else {
                $result = Install-BetterCampMacminiDrivers -Path $pack -Machine $machine
                Write-Host "$($result.Count) driver packages processed. Windows chooses the best matching driver; existing newer drivers are not forcibly replaced. Restart Windows, then verify audio, USB, network and display."
                Show-BetterCampMacminiDiagnosis
            }
        } else {
            $pack = Resolve-BetterCampPath -Path $BootCampPath -Root $PSScriptRoot
            if (-not $pack) {
                $pack = Find-BetterCampCachedPackage
                if ($pack) { Write-Host "Using cached Apple driver package: $pack" }
            }
            if (-not $pack) {
                Write-Host 'Downloading Apple Boot Camp 5.1.5621 (about 925 MB).'
                Write-Host 'This is an archived 2012-compatible package, not the latest Boot Camp release.'
                $pack = Get-BetterCampPackage
            }
            $version = Get-BetterCampVersion $pack
            Write-Host "Boot Camp $version : $pack"
            if ($version -ne [version]'5.1.5621') { throw 'Driver-only installation currently requires the verified MacBookPro9,2 Boot Camp 5.1.5621 package.' }
            Assert-BetterCampSignature (Join-Path $pack 'setup.exe')
            if ($DownloadOnly) {
                Write-Host "Download verified. To install later: .\Start-BetterCamp.cmd -BootCampPath `"$pack`""
            } elseif ($RepairAudio) {
                Repair-BetterCampAudio -Path $pack -Machine $machine -Root $PSScriptRoot
            } else {
                if (-not $SkipAudioPatch) {
                    if ($machine.Model -eq 'MacBookPro9,2') {
                        Install-BetterCampAudioPatch -Machine $machine -Root $PSScriptRoot | Out-Null
                    } elseif ((Get-BetterCampEffectiveFirmware $machine) -eq 'UEFI') {
                        Write-Warning "The bundled audio table is not verified for $($machine.Model); the UEFI audio patch was not applied."
                    }
                }
                Write-Host 'Installing the MacBookPro9,2 device drivers individually. Boot Camp Manager, Control Panel and Apple Software Update will not be installed.'
                $result = Install-BetterCampDrivers -Path $pack -Machine $machine
                Write-Host "$($result.Count) driver packages completed. Restart Windows, then check sound, Wi-Fi, trackpad and keyboard controls."
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
