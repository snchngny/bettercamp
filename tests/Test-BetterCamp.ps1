#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'scripts/BetterCamp.Common.ps1')
$script:count = 0
function Assert-True($Condition, [string]$Label) {
    if (-not $Condition) { throw "FAIL: $Label" }
    $script:count++
}
function Assert-Throws([scriptblock]$Action, [string]$Label) {
    $threw = $false
    try { & $Action | Out-Null } catch { $threw = $true }
    Assert-True $threw $Label
}
foreach ($model in @('MacBookPro9,1', 'MacBookPro9,2', 'MacBookPro10,1', 'MacBookPro10,2')) {
    Assert-BetterCampMachine ([pscustomobject]@{Model=$model;Build=26100;Is64Bit=$true})
    $script:count++
}
Assert-Throws { Assert-BetterCampMachine ([pscustomobject]@{Model='MacBookPro8,1';Build=26100;Is64Bit=$true}) } 'wrong model'
Assert-Throws { Assert-BetterCampMachine ([pscustomobject]@{Model='MacBookPro9,2';Build=19045;Is64Bit=$true}) } 'Windows 10'
Assert-Throws { Assert-BetterCampMachine ([pscustomobject]@{Model='MacBookPro9,2';Build=26100;Is64Bit=$false}) } '32-bit OS'

$temporary = Join-Path ([IO.Path]::GetTempPath()) ('bettercamp-tests-' + [guid]::NewGuid().ToString('N'))
$pack = Join-Path $temporary "USB drive [1] & O'Brien/BootCamp"
New-Item -ItemType Directory -Path $pack -Force | Out-Null
try {
    Set-Content -LiteralPath (Join-Path $pack 'setup.exe') -Value 'test fixture, never execute'
    Set-Content -LiteralPath (Join-Path $pack 'BootCamp.xml') -Value '<Root><ProductVersion>5.1.5621</ProductVersion></Root>'
    Assert-True ((Resolve-BetterCampPath -Path $pack -Root $temporary) -eq $pack) 'literal path with metacharacters'
    Assert-True ((Resolve-BetterCampPath -Path (Split-Path $pack -Parent) -Root $temporary) -eq $pack) 'parent folder'
    Assert-True ((Resolve-BetterCampPath -Root $temporary) -eq $null) 'missing default folder'
    Assert-Throws { Resolve-BetterCampPath -Path (Join-Path $temporary 'missing') -Root $temporary } 'explicit missing path fails'
    Assert-True ((Get-BetterCampVersion $pack) -eq [version]'5.1.5621') 'version independent of line number'
    Set-Content -LiteralPath (Join-Path $pack 'BootCamp.xml') -Value '<Root xmlns="urn:test"><ProductVersion>6.1.9999</ProductVersion></Root>'
    Assert-True ((Get-BetterCampVersion $pack) -eq [version]'6.1.9999') 'namespace and modern version'
    Set-Content -LiteralPath (Join-Path $pack 'BootCamp.xml') -Value '<Root />'
    Assert-Throws { Get-BetterCampVersion $pack } 'missing version'
    Set-Content -LiteralPath (Join-Path $pack 'BootCamp.xml') -Value '<!DOCTYPE Root [<!ENTITY data SYSTEM "file:///missing">]><Root><ProductVersion>&data;</ProductVersion></Root>'
    Assert-Throws { Get-BetterCampVersion $pack } 'DTD not allowed'

    $literal = ConvertTo-BetterCampLiteral $pack
    Assert-True ((& ([scriptblock]::Create($literal))) -eq $pack) 'elevation quoting round trip'
    function Get-AuthenticodeSignature {
        param($LiteralPath)
        return $script:signature
    }
    $script:signature = [pscustomobject]@{Status='Valid';SignerCertificate=[pscustomobject]@{Subject='CN=Apple Inc., O=Apple Inc., C=US'}}
    Assert-BetterCampSignature (Join-Path $pack 'setup.exe')
    $script:count++
    $script:signature.Status = 'HashMismatch'
    Assert-Throws { Assert-BetterCampSignature 'tampered.exe' } 'tampered installer'
    $script:signature = [pscustomobject]@{Status='Valid';SignerCertificate=[pscustomobject]@{Subject='CN=Apple Inc., O=Other Vendor, C=US'}}
    Assert-Throws { Assert-BetterCampSignature 'other.exe' } 'wrong publisher'
    $script:signature = [pscustomobject]@{Status='NotSigned';SignerCertificate=$null}
    Assert-Throws { Assert-BetterCampSignature 'unsigned.exe' } 'unsigned installer'

    $driverPaths = @(Get-BetterCampDriverInstallers ([pscustomobject]@{Model='MacBookPro9,2'}))
    Assert-True ($driverPaths.Count -eq 16) 'MacBookPro9,2 driver-only package count'
    Assert-True ('Apple\BootCamp.msi' -notin $driverPaths) 'Boot Camp Manager package excluded'
    Assert-True ('Apple\AppleSoftwareUpdate.msi' -notin $driverPaths) 'Apple Software Update package excluded'
    Assert-Throws { Get-BetterCampDriverInstallers ([pscustomobject]@{Model='MacBookPro9,1'}) } 'unverified model blocked from driver-only install'
    foreach ($relativePath in $driverPaths) {
        $fixture = Join-Path (Join-Path $pack 'Drivers') $relativePath
        New-Item -ItemType Directory -Path (Split-Path $fixture -Parent) -Force | Out-Null
        Set-Content -LiteralPath $fixture -Value 'driver fixture, never execute'
    }
    function Assert-BetterCampDriverHash { param($Path, $ExpectedHash, $Label) }
    $script:driverCalls = @()
    function Start-Process {
        param($FilePath, $WorkingDirectory, [switch]$Wait, [switch]$PassThru)
        $script:driverCalls += $FilePath
        Assert-True ($WorkingDirectory -eq (Split-Path $FilePath -Parent) -and $Wait -and $PassThru) 'driver wait and working directory'
        return [pscustomobject]@{ExitCode=$script:installerCode}
    }
    $script:installerCode = 0
    $driverResult = Install-BetterCampDrivers -Path $pack -Machine ([pscustomobject]@{Model='MacBookPro9,2'})
    Assert-True ($driverResult.Count -eq 16 -and $script:driverCalls.Count -eq 16) 'all individual driver packages executed'
    Assert-True (-not $driverResult.RestartRequired) 'driver exit zero needs normal restart only'
    $script:installerCode = 3010
    $driverResult = Install-BetterCampDrivers -Path $pack -Machine ([pscustomobject]@{Model='MacBookPro9,2'})
    Assert-True $driverResult.RestartRequired 'driver restart exit propagated'
    $script:installerCode = 1603
    Assert-Throws { Install-BetterCampDrivers -Path $pack -Machine ([pscustomobject]@{Model='MacBookPro9,2'}) } 'individual driver failure propagated'

    $script:removedProducts = @()
    function Get-BetterCampInstalledSoftware {
        return @(
            [pscustomobject]@{DisplayName='Boot Camp Services';PSChildName='{FA2B2C2A-EA41-495A-9308-60726125D562}'},
            [pscustomobject]@{DisplayName='Apple Software Update';PSChildName='{12345678-1234-1234-1234-123456789ABC}'}
        )
    }
    function Invoke-BetterCampNative {
        param($FilePath, $Arguments)
        $script:removedProducts += ($Arguments -join ' ')
        return [pscustomobject]@{ExitCode=0;Output='ok'}
    }
    Remove-BetterCampSoftware
    Assert-True ($script:removedProducts.Count -eq 2) 'Boot Camp software cleanup removes two MSI products'
    Assert-True (@($script:removedProducts | Where-Object { $_ -match '/x \{FA2B2C2A-' }).Count -eq 1) 'Boot Camp Services removed by product code'
    Assert-True ($script:driverCalls.Count -eq 33) 'software cleanup does not remove device drivers'

    # MacBookPro9,2 UEFI audio patch: enable, load, record state, and fully revert.
    $oldAudioLocalAppData = $env:LOCALAPPDATA
    $env:LOCALAPPDATA = Join-Path $temporary 'audio state'
    $audioMachine = [pscustomobject]@{Model='MacBookPro9,2';Firmware='UEFI'}
    $script:nativeCalls = @()
    function Confirm-SecureBootUEFI { return $false }
    function Invoke-BetterCampNative {
        param($FilePath, $Arguments)
        $script:nativeCalls += [pscustomobject]@{FilePath=$FilePath;Arguments=($Arguments -join ' ')}
        if ($Arguments[0] -eq '/enum') { return [pscustomobject]@{ExitCode=0;Output="testsigning    No"} }
        return [pscustomobject]@{ExitCode=0;Output='ok'}
    }
    Assert-True (Install-BetterCampAudioPatch -Machine $audioMachine -Root $root) 'audio patch applied'
    $audioState = Get-BetterCampAudioPatchPaths $root
    Assert-True (Test-Path -LiteralPath $audioState.State) 'audio patch state recorded'
    Assert-True ((Get-FileHash -LiteralPath $audioState.OverrideTable -Algorithm SHA256).Hash -eq '9AD7A614D2CDB7A67A47C0959B00B0CA188811623753DB229F3E56D71B13990D') 'higher-revision DSDT generated deterministically'
    $overrideBytes = [IO.File]::ReadAllBytes($audioState.OverrideTable)
    Assert-True ([BitConverter]::ToUInt32($overrideBytes, 24) -eq 0x7FFFFFFF) 'DSDT OEM revision is higher than firmware table'
    Assert-True (((($overrideBytes | Measure-Object -Sum).Sum) -band 0xFF) -eq 0) 'generated DSDT checksum valid'
    Assert-True (@($script:nativeCalls | Where-Object { $_.Arguments -eq '/set {current} testsigning on' }).Count -eq 1) 'test signing enabled'
    Assert-True (@($script:nativeCalls | Where-Object { $_.Arguments -like '/loadtable -v *dsdt_2012_override.aml' }).Count -eq 1) 'higher-revision DSDT loaded'
    Remove-BetterCampAudioPatch -Machine $audioMachine -Root $root
    Assert-True (-not (Test-Path -LiteralPath $audioState.State)) 'audio patch state removed'
    Assert-True (@($script:nativeCalls | Where-Object { $_.Arguments -like '/loadtable -v -d *dsdt_2012_override.aml' }).Count -eq 1) 'DSDT override removed'
    Assert-True (-not (Test-Path -LiteralPath $audioState.OverrideTable)) 'generated DSDT file removed'
    Assert-True (@($script:nativeCalls | Where-Object { $_.Arguments -eq '/set {current} testsigning off' }).Count -eq 1) 'test signing restored'

    New-Item -ItemType Directory -Path (Split-Path $audioState.State -Parent) -Force | Out-Null
    Set-Content -LiteralPath $audioState.State -Value '{broken json'
    $script:nativeCalls = @()
    Assert-Throws { Remove-BetterCampAudioPatch -Machine $audioMachine -Root $root } 'damaged state blocks removal'
    Assert-True ($script:nativeCalls.Count -eq 0) 'damaged state changes no boot or ACPI settings'
    Remove-Item -LiteralPath $audioState.State -Force

    $stateBlocker = Join-Path $temporary 'local-app-data-is-a-file'
    Set-Content -LiteralPath $stateBlocker -Value 'blocks state directory creation'
    $env:LOCALAPPDATA = $stateBlocker
    $script:nativeCalls = @()
    Assert-Throws { Install-BetterCampAudioPatch -Machine $audioMachine -Root $root } 'state write failure reported'
    Assert-True ($script:nativeCalls.Count -eq 0) 'table generation failure changes no boot or ACPI settings'
    $env:LOCALAPPDATA = Join-Path $temporary 'audio state'

    Assert-Throws { Install-BetterCampAudioPatch -Machine ([pscustomobject]@{Model='MacBookPro9,1';Firmware='UEFI'}) -Root $root } 'audio table blocked on unverified model'
    $script:nativeCalls = @()
    Assert-True (-not (Install-BetterCampAudioPatch -Machine ([pscustomobject]@{Model='MacBookPro9,2';Firmware='BIOS'}) -Root $root)) 'legacy BIOS skips UEFI patch'
    Assert-True ($script:nativeCalls.Count -eq 0) 'legacy BIOS changes nothing'
    function Confirm-SecureBootUEFI { return $true }
    Assert-Throws { Install-BetterCampAudioPatch -Machine $audioMachine -Root $root } 'Secure Boot blocks audio patch'

    $tamperedRoot = Join-Path $temporary 'tampered audio'
    $tamperedAudio = Join-Path $tamperedRoot 'Audio_2011_2012'
    New-Item -ItemType Directory -Path $tamperedAudio -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $root 'Audio_2011_2012/asl.exe') -Destination $tamperedAudio
    Set-Content -LiteralPath (Join-Path $tamperedAudio 'dsdt_2012.aml') -Value 'tampered'
    function Confirm-SecureBootUEFI { return $false }
    Assert-Throws { Install-BetterCampAudioPatch -Machine $audioMachine -Root $tamperedRoot } 'tampered audio table blocked'

    $script:nativeCalls = @()
    function Invoke-BetterCampNative {
        param($FilePath, $Arguments)
        $script:nativeCalls += [pscustomobject]@{FilePath=$FilePath;Arguments=($Arguments -join ' ')}
        if ($Arguments[0] -eq '/enum') { return [pscustomobject]@{ExitCode=0;Output="testsigning    No"} }
        if ($FilePath -like '*asl.exe') { return [pscustomobject]@{ExitCode=5;Output='load failed'} }
        return [pscustomobject]@{ExitCode=0;Output='ok'}
    }
    Assert-Throws { Install-BetterCampAudioPatch -Machine $audioMachine -Root $root } 'failed DSDT load is reported'
    Assert-True (@($script:nativeCalls | Where-Object { $_.Arguments -eq '/set {current} testsigning off' }).Count -eq 1) 'failed load rolls back test signing'
    $env:LOCALAPPDATA = $oldAudioLocalAppData

    # CLI integration: no elevation, network or installation may occur during diagnosis.
    function Get-CimInstance {
        param($ClassName)
        switch ($ClassName) {
            'Win32_ComputerSystemProduct' { [pscustomobject]@{Name='MacBookPro9,2'} }
            'Win32_OperatingSystem' { [pscustomobject]@{BuildNumber='26100'} }
            'Win32_VideoController' { [pscustomobject]@{Name='Intel HD Graphics 4000'} }
            'Win32_PnPEntity' { [pscustomobject]@{Name='High Definition Audio Controller';PNPDeviceID='PCI\VEN_8086&DEV_1E20';ConfigManagerErrorCode=10} }
            default { throw "Unexpected CIM query: $ClassName" }
        }
    }
    function Get-ItemPropertyValue { param($LiteralPath,$Name); return 2 }
    function Start-Process { throw 'Diagnosis must not launch a process' }
    function Invoke-WebRequest { throw 'Diagnosis must not access network' }
    & (Join-Path $root 'bettercamp.ps1') -Diagnose
    Assert-True ($LASTEXITCODE -eq 0) 'diagnose target machine'

    # Exercise the real archive/extraction and download-only entry point with a local ZIP.
    Set-Content -LiteralPath (Join-Path $pack 'BootCamp.xml') -Value '<Root><ProductVersion>5.1.5621</ProductVersion></Root>'
    $fixtureZip = Join-Path $temporary 'fixture.zip'
    Compress-Archive -LiteralPath $pack -DestinationPath $fixtureZip
    $oldLocalAppData = $env:LOCALAPPDATA
    try {
        $env:LOCALAPPDATA = Join-Path $temporary 'local app data'
        function Invoke-WebRequest {
            param($Uri, $OutFile, [switch]$UseBasicParsing, $TimeoutSec)
            if ($Uri -ne 'https://download.info.apple.com/Mac_OS_X/031-3384.20140211.Xcc3e/BootCamp5.1.5621.zip') { throw 'Wrong download URL' }
            Copy-Item -LiteralPath $fixtureZip -Destination $OutFile
        }
        function Get-AuthenticodeSignature {
            param($LiteralPath)
            return [pscustomobject]@{Status='Valid';SignerCertificate=[pscustomobject]@{Subject='CN=Apple Inc., O=Apple Inc., C=US'}}
        }
        & (Join-Path $root 'bettercamp.ps1') -DownloadOnly
        Assert-True ($LASTEXITCODE -eq 0) 'download-only extracts without elevation or installer'
        $downloaded = @(Get-ChildItem -LiteralPath $env:LOCALAPPDATA -Filter BootCamp.xml -Recurse)
        Assert-True ($downloaded.Count -eq 1) 'one extracted package'
        Assert-True ((Find-BetterCampCachedPackage) -eq $downloaded[0].DirectoryName) 'cached package found for repair reuse'
        Remove-Item -LiteralPath (Join-Path $env:LOCALAPPDATA 'BetterCamp/downloads') -Recurse -Force
        function Invoke-WebRequest { throw 'Simulated network failure' }
        & (Join-Path $root 'bettercamp.ps1') -DownloadOnly
        Assert-True ($LASTEXITCODE -eq 1) 'network failure propagated'
        $failureLog = Get-ChildItem -LiteralPath (Join-Path $env:LOCALAPPDATA 'BetterCamp/logs') -File | Sort-Object Name | Select-Object -Last 1
        Assert-True ((Get-Content -LiteralPath $failureLog.FullName -Raw) -match 'Simulated network failure') 'error saved in log'
        & (Join-Path $root 'bettercamp.ps1') -DownloadOnly -BootCampPath $pack
        Assert-True ($LASTEXITCODE -eq 0) 'offline pack avoids network'
    } finally { $env:LOCALAPPDATA = $oldLocalAppData }

    function Get-CimInstance {
        param($ClassName)
        switch ($ClassName) {
            'Win32_ComputerSystemProduct' { [pscustomobject]@{Name='PC'} }
            'Win32_OperatingSystem' { [pscustomobject]@{BuildNumber='26100'} }
            'Win32_VideoController' { [pscustomobject]@{Name='Other GPU'} }
        }
    }
    & (Join-Path $root 'bettercamp.ps1') -Diagnose
    Assert-True ($LASTEXITCODE -eq 1) 'reject non-target machine'

    # Bootstrap stages the launcher without requiring a repository ZIP download.
    Remove-Item Function:Start-Process
    & (Join-Path $root 'run.ps1') -LauncherSourceDirectory $root -StageOnly
    Assert-True ($LASTEXITCODE -eq 0) 'one-line bootstrap verifies all staged launcher files'
    $tamperedLauncher = Join-Path $temporary 'tampered launcher'
    New-Item -ItemType Directory -Path (Join-Path $tamperedLauncher 'scripts'),(Join-Path $tamperedLauncher 'Audio_2011_2012') -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $root 'bettercamp.ps1') -Destination $tamperedLauncher
    Copy-Item -LiteralPath (Join-Path $root 'scripts/BetterCamp.Common.ps1') -Destination (Join-Path $tamperedLauncher 'scripts')
    Copy-Item -LiteralPath (Join-Path $root 'Audio_2011_2012/asl.exe'),(Join-Path $root 'Audio_2011_2012/dsdt_2012.aml') -Destination (Join-Path $tamperedLauncher 'Audio_2011_2012')
    Add-Content -LiteralPath (Join-Path $tamperedLauncher 'bettercamp.ps1') -Value '# tampered'
    Assert-Throws { & (Join-Path $root 'run.ps1') -LauncherSourceDirectory $tamperedLauncher -StageOnly } 'bootstrap rejects modified launcher files'
} finally {
    # Only delete this test's newly created directory directly under the OS temporary directory.
    $resolved = [IO.Path]::GetFullPath($temporary)
    $expectedParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/')
    if ((Split-Path $resolved -Parent) -eq $expectedParent -and (Split-Path $resolved -Leaf) -like 'bettercamp-tests-*') {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
Write-Host "PASS: $script:count checks (no real drivers installed)"
# CI propagates LASTEXITCODE; the final rejection case intentionally sets it to 1.
exit 0
