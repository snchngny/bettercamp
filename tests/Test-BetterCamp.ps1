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

    function Start-Process {
        param($FilePath, $WorkingDirectory, [switch]$Wait, [switch]$PassThru)
        Assert-True ($FilePath -eq (Join-Path $pack 'setup.exe')) 'installer path preserved'
        Assert-True ($WorkingDirectory -eq $pack -and $Wait -and $PassThru) 'wait and working directory'
        return [pscustomobject]@{ExitCode=$script:installerCode}
    }
    foreach ($code in @(0, 1641, 3010)) {
        $script:installerCode = $code
        Assert-True ((Install-BetterCampPackage $pack) -eq $code) "installer exit $code"
    }
    $script:installerCode = 1603
    Assert-Throws { Install-BetterCampPackage $pack } 'installer failure propagated'

    # CLI integration: no elevation, network or installation may occur during diagnosis.
    function Get-CimInstance {
        param($ClassName)
        switch ($ClassName) {
            'Win32_ComputerSystemProduct' { [pscustomobject]@{Name='MacBookPro9,2'} }
            'Win32_OperatingSystem' { [pscustomobject]@{BuildNumber='26100'} }
            'Win32_VideoController' { [pscustomobject]@{Name='Intel HD Graphics 4000'} }
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
} finally {
    # Only delete this test's newly created directory directly under the OS temporary directory.
    $resolved = [IO.Path]::GetFullPath($temporary)
    $expectedParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/')
    if ((Split-Path $resolved -Parent) -eq $expectedParent -and (Split-Path $resolved -Leaf) -like 'bettercamp-tests-*') {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
Write-Host "PASS: $script:count checks (no real drivers installed)"
