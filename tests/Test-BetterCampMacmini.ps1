#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'scripts/BetterCamp.Common.ps1')
. (Join-Path $root 'scripts/BetterCamp.Macmini.ps1')
$script:checks = 0
function Check($Condition, [string]$Label) {
    if (-not $Condition) { throw "FAIL: $Label" }
    $script:checks++
}
function Reject([scriptblock]$Action, [string]$Label) {
    $failed = $false
    try { & $Action | Out-Null } catch { $failed = $true }
    Check $failed $Label
}
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('bettercamp-macmini-tests-' + [guid]::NewGuid().ToString('N'))
$oldLocalAppData = $env:LOCALAPPDATA
New-Item -ItemType Directory -Path $temporary | Out-Null
try {
    $env:LOCALAPPDATA = Join-Path $temporary 'state'
    $pack = Join-Path $temporary "USB [1] O'Brien/WindowsSupport"
    New-Item -ItemType Directory -Path (Join-Path $pack 'BootCamp'), (Join-Path $pack '$WinPEDriver$') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $pack 'BootCamp/BootCamp.xml') '<Root><ProductVersion>6.1.7139</ProductVersion></Root>'
    Set-Content -LiteralPath (Join-Path $pack 'BootCamp/setup.exe') 'fixture; never execute'
    Check ((Resolve-BetterCampMacminiPath $pack $temporary) -eq $pack) 'offline support root with spaces and metacharacters'
    Check ((Resolve-BetterCampMacminiPath (Join-Path $pack 'BootCamp') $temporary) -eq $pack) 'BootCamp path resolves to complete support root'
    Reject { Resolve-BetterCampMacminiPath (Join-Path $temporary 'missing') $temporary } 'missing explicit offline path is not silently downloaded'
    Reject { Assert-BetterCampMacminiPackage $pack } 'correct XML version alone cannot authenticate a package'
    $before = Get-BetterCampTreeHash (Join-Path $pack 'BootCamp')
    Add-Content -LiteralPath (Join-Path $pack 'BootCamp/setup.exe') 'modified payload'
    Check ($before -ne (Get-BetterCampTreeHash (Join-Path $pack 'BootCamp'))) 'payload modification changes package digest'
    Rename-Item -LiteralPath (Join-Path $pack 'BootCamp/setup.exe') -NewName 'renamed.exe'
    Check ($before -ne (Get-BetterCampTreeHash (Join-Path $pack 'BootCamp'))) 'renaming a file changes package digest'

    foreach ($relative in @(
        'BootCamp/Drivers/Apple/AppleUSBVHCI/AppleUSBVHCI.inf',
        '$WinPEDriver$/AppleSSD64/AppleSSD.inf',
        '$WinPEDriver$/BroadcomWirelessUDM64/wifi.inf',
        '$WinPEDriver$/Aquantia64/ethernet.inf', '$WinPEDriver$/SerialIO/uart.inf',
        '$WinPEDriver$/IntelMEI/heci.inf', '$WinPEDriver$/IntelSST/audio.inf',
        '$WinPEDriver$/IntelHDGraphics64/Graphics/gpu.inf', '$WinPEDriver$/IntelHDGraphics64/autorun.inf',
        '$WinPEDriver$/Dolby/swc/audio.inf',
        '$WinPEDriver$/BroadcomBluetoothHID64/UheSerialBus.inf',
        '$WinPEDriver$/AppleBluetoothBroadcom64/AppleBTBC.inf'
    )) {
        $file = Join-Path $pack $relative
        New-Item -ItemType Directory -Path (Split-Path $file -Parent) -Force | Out-Null
        Set-Content -LiteralPath $file 'fixture'
    }
    $files = @(Get-BetterCampMacminiDriverInfs $pack)
    Check ($files.Count -eq 9) 'select native drivers including SSD, Wi-Fi, UART and GPU'
    Check (@($files | Where-Object { $_.Name -in @('autorun.inf', 'UheSerialBus.inf', 'AppleBTBC.inf') }).Count -eq 0) 'exclude autorun and WinPE-only Bluetooth replacements'
    $script:calls = @()
    $script:code = 0
    function Assert-BetterCampMacminiPackage { param($Path); if ($script:rejectPack) { throw 'tampered package' } }
    $script:rejectPack = $false
    function Invoke-BetterCampNative {
        param($FilePath, $Arguments)
        $script:calls += [pscustomobject]@{FilePath=$FilePath;Arguments=$Arguments}
        return [pscustomobject]@{ExitCode=$script:code;Output='fixture'}
    }
    Reject { Install-BetterCampMacminiDrivers $pack ([pscustomobject]@{Model='MacBookPro9,2'}) } 'wrong model cannot install Mac mini drivers'
    Check ($script:calls.Count -eq 0) 'wrong model performs no native calls'
    $script:rejectPack = $true
    Reject { Install-BetterCampMacminiDrivers $pack ([pscustomobject]@{Model='Macmini8,1'}) } 'integrity failure aborts before driver changes'
    Check ($script:calls.Count -eq 0) 'tampered package performs no native calls'
    $script:rejectPack = $false
    $result = Install-BetterCampMacminiDrivers $pack ([pscustomobject]@{Model='Macmini8,1'})
    Check ($result.Count -eq 9 -and -not $result.RestartRequired) 'processed count and success result'
    foreach ($call in $script:calls) {
        Check ((Split-Path $call.FilePath -Leaf) -eq 'pnputil.exe' -and $call.Arguments.Count -eq 3 -and
            $call.Arguments[0] -eq '/add-driver' -and $call.Arguments[2] -eq '/install' -and
            (Test-Path -LiteralPath $call.Arguments[1])) 'standard rank, literal path, no force/delete/reboot or installer'
    }
    $script:code = 3010
    Check (Install-BetterCampMacminiDrivers $pack ([pscustomobject]@{Model='Macmini8,1'})).RestartRequired 'reboot-required exit propagated'
    $script:code = 5
    $script:calls = @()
    Reject { Install-BetterCampMacminiDrivers $pack ([pscustomobject]@{Model='Macmini8,1'}) } 'driver failure cannot report completion'
    Check ($script:calls.Count -eq 1) 'stop on first failed driver'
    function Get-CimInstance {
        param($ClassName)
        [pscustomobject]@{Name='Bluetooth';PNPDeviceID='ACPI\BCM2E7C\1';ConfigManagerErrorCode=10}
    }
    $diagnosis = Show-BetterCampMacminiDiagnosis 3>&1 | Out-String -Width 4096
    Check ($diagnosis -match 'Code 10' -and $diagnosis -match 'not an established fix') 'device failure remains visible after driver processing'

    # Exercise the entry point in a sandbox. Every native/network/elevation boundary is a stub.
    $entry = Join-Path $temporary 'entry'
    New-Item -ItemType Directory -Path (Join-Path $entry 'scripts') -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $root 'bettercamp.ps1') -Destination $entry
    Copy-Item -LiteralPath (Join-Path $root 'scripts/BetterCamp.Common.ps1') -Destination (Join-Path $entry 'scripts')
    Add-Content -LiteralPath (Join-Path $entry 'scripts/BetterCamp.Common.ps1') -Value @'
function Get-BetterCampMachine { [pscustomobject]@{Model=$global:fixtureModel;Build=26100;Is64Bit=$true;Firmware='UEFI';Graphics=@('fixture')} }
function Test-BetterCampAdministrator { $true }
function Install-BetterCampAudioPatch { throw 'Audio patch must never run in these scenarios' }
function Invoke-BetterCampNative { throw 'No actual native call is allowed' }
function Get-BetterCampPackage { throw '2012 download must never run for Mac mini' }
'@
    Set-Content -LiteralPath (Join-Path $entry 'scripts/BetterCamp.Macmini.ps1') -Value @'
function Get-BetterCampMacminiPackage { $global:entryCalls += 'download'; 'fixture-package' }
function Resolve-BetterCampMacminiPath { param($Path,$Root); if ($Path) { $global:entryCalls += 'offline'; return $Path }; $null }
function Assert-BetterCampMacminiPackage { param($Path); $global:entryCalls += 'verify' }
function Install-BetterCampMacminiDrivers { param($Path,$Machine); $global:entryCalls += 'install'; [pscustomobject]@{Count=39;RestartRequired=$true} }
function Show-BetterCampMacminiDiagnosis { $global:entryCalls += 'diagnose' }
'@
    $global:fixtureModel = 'Macmini8,1'
    $global:entryCalls = @()
    & (Join-Path $entry 'bettercamp.ps1') -DownloadOnly
    Check ($LASTEXITCODE -eq 0 -and 'download' -in $global:entryCalls -and 'install' -notin $global:entryCalls) 'Mac mini download-only never installs'
    $global:entryCalls = @()
    & (Join-Path $entry 'bettercamp.ps1') -BootCampPath $pack
    Check ($LASTEXITCODE -eq 0 -and 'install' -in $global:entryCalls -and 'download' -notin $global:entryCalls) 'offline normal entry dispatches to Mac mini installer'
    foreach ($flag in @('AudioPatchOnly', 'RepairAudio', 'RemoveAudioPatch')) {
        $global:entryCalls = @()
        $arguments = @{$flag=$true}
        & (Join-Path $entry 'bettercamp.ps1') @arguments
        Check ($LASTEXITCODE -eq 1 -and $global:entryCalls.Count -eq 0) '2012 audio modes rejected before any download or install'
    }
    $global:fixtureModel = 'PC'
    $global:entryCalls = @()
    & (Join-Path $entry 'bettercamp.ps1') -DownloadOnly -TargetModel 'Macmini8,1'
    Check ($LASTEXITCODE -eq 0 -and 'download' -in $global:entryCalls -and 'install' -notin $global:entryCalls) 'another PC may prepare the Mac mini package'
    $global:entryCalls = @()
    & (Join-Path $entry 'bettercamp.ps1') -TargetModel 'Macmini8,1'
    Check ($LASTEXITCODE -eq 1 -and $global:entryCalls.Count -eq 0) 'target override cannot authorize installation on another model'
    & (Join-Path $entry 'bettercamp.ps1') -DownloadOnly
    Check ($LASTEXITCODE -eq 1) 'unknown PC without explicit download target rejected'
    $global:fixtureModel = 'Macmini8,1'
    $global:entryCalls = @()
    & (Join-Path $entry 'bettercamp.ps1') -Diagnose
    Check ($LASTEXITCODE -eq 0 -and ($global:entryCalls -join ',') -eq 'diagnose') 'Mac mini diagnosis performs no download, elevation or install'

    # Download/runtime failures must stop before any native command or installation.
    $runtime = Join-Path $env:LOCALAPPDATA 'BetterCamp/tools/7zip-26.06/portable'
    New-Item -ItemType Directory -Path $runtime -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $runtime '7z.exe') 'tampered runtime'
    Set-Content -LiteralPath (Join-Path $runtime '7z.dll') 'tampered runtime'
    function Invoke-WebRequest { throw 'network unavailable' }
    $script:calls = @()
    Reject { Get-BetterCampSevenZip } 'tampered cached extractor is never executed'
    Check ($script:calls.Count -eq 0) 'runtime integrity failure performs no native calls'
    $cache = Join-Path $env:LOCALAPPDATA 'BetterCamp/downloads/Macmini8,1-041-91731'
    Reject { Get-BetterCampMacminiPackage } 'network error is propagated without installation'
    Check (@(Get-ChildItem -LiteralPath $cache -Directory).Count -eq 0) 'failed download removes its own partial extraction directory'
    Set-Content -LiteralPath (Join-Path $cache 'BootCampESD.pkg') 'corrupt cached archive'
    Reject { Get-BetterCampMacminiPackage } 'corrupt cached archive fails closed'
    Check ($script:calls.Count -eq 0) 'bad archive is not passed to extractor'
} finally {
    $env:LOCALAPPDATA = $oldLocalAppData
    Remove-Variable fixtureModel,entryCalls -Scope Global -ErrorAction SilentlyContinue
    $resolved = [IO.Path]::GetFullPath($temporary)
    if ((Split-Path $resolved -Parent) -eq [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') -and
        (Split-Path $resolved -Leaf) -like 'bettercamp-macmini-tests-*') {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
Write-Host "PASS: $script:checks Mac mini checks (no real drivers installed)"
exit 0
