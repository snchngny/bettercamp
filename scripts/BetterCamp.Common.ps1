# Windows PowerShell 5.1 compatible. Dot-sourcing only defines functions.
Set-StrictMode -Version Latest

function ConvertTo-BetterCampLiteral([string]$Value) {
    return "'" + $Value.Replace("'", "''") + "'"
}

function Get-BetterCampMachine {
    $product = Get-CimInstance -ClassName Win32_ComputerSystemProduct
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $firmware = 'Unknown'
    try {
        $value = Get-ItemPropertyValue -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name PEFirmwareType
        if ($value -eq 1) { $firmware = 'BIOS' }
        elseif ($value -eq 2) { $firmware = 'UEFI' }
    } catch { }
    [pscustomobject]@{
        Model = ([string]$product.Name).Trim()
        Build = [int]$os.BuildNumber
        Is64Bit = [Environment]::Is64BitOperatingSystem
        Firmware = $firmware
        Graphics = @(Get-CimInstance -ClassName Win32_VideoController | Select-Object -ExpandProperty Name)
    }
}

function Assert-BetterCampMachine($Machine) {
    if ($Machine.Model -notin @('MacBookPro9,1', 'MacBookPro9,2', 'MacBookPro10,1', 'MacBookPro10,2')) {
        throw "Unsupported model: $($Machine.Model). This launcher targets the 2012 MacBook Pro family."
    }
    if (-not $Machine.Is64Bit -or $Machine.Build -lt 22000) { throw 'This launcher requires 64-bit Windows 11 (build 22000 or later).' }
}

function Test-BetterCampAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Resolve-BetterCampPath([string]$Path, [string]$Root) {
    if ($Path) {
        $candidate = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath
        foreach ($folder in @($candidate, (Join-Path $candidate 'BootCamp'))) {
            if ((Test-Path -LiteralPath (Join-Path $folder 'setup.exe') -PathType Leaf) -and
                (Test-Path -LiteralPath (Join-Path $folder 'BootCamp.xml') -PathType Leaf)) { return $folder }
        }
        throw 'The specified folder must contain setup.exe and BootCamp.xml, or a BootCamp subfolder containing both.'
    }
    $local = Join-Path $Root 'BootCamp'
    if (Test-Path -LiteralPath $local) { return Resolve-BetterCampPath -Path $local -Root $Root }
    return $null
}

function Get-BetterCampVersion([string]$Path) {
    $settings = New-Object System.Xml.XmlReaderSettings
    $settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null
    $reader = [System.Xml.XmlReader]::Create((Join-Path $Path 'BootCamp.xml'), $settings)
    try {
        $xml = New-Object System.Xml.XmlDocument
        $xml.XmlResolver = $null
        $xml.Load($reader)
        $node = $xml.SelectSingleNode("//*[local-name()='ProductVersion']")
        if ($null -eq $node) { throw 'BootCamp.xml has no ProductVersion.' }
        return [version]$node.InnerText.Trim()
    } finally { $reader.Dispose() }
}

function Assert-BetterCampSignature([string]$Path) {
    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    if ($signature.Status -ne 'Valid' -or $null -eq $signature.SignerCertificate -or
        $signature.SignerCertificate.Subject -notmatch '(?:^|,\s*)O="?Apple Inc\."?(?:,|$)') {
        throw "Apple signature verification failed: $Path ($($signature.Status)). Obtain a fresh package from Apple; check the system clock and Internet access."
    }
}

function Get-BetterCampPackage {
    $cache = Join-Path $env:LOCALAPPDATA 'BetterCamp/downloads'
    New-Item -ItemType Directory -Path $cache -Force | Out-Null
    $destination = Join-Path $cache ([guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $destination | Out-Null
    $zip = Join-Path $destination 'BootCamp5.1.5621.zip'
    $uri = 'https://download.info.apple.com/Mac_OS_X/031-3384.20140211.Xcc3e/BootCamp5.1.5621.zip'
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    Write-Host "Source: $uri"
    $oldProgress = $ProgressPreference
    try {
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $uri -OutFile $zip -UseBasicParsing -TimeoutSec 1800
        Expand-Archive -LiteralPath $zip -DestinationPath (Join-Path $destination 'expanded')
    } finally { $ProgressPreference = $oldProgress }
    $matches = @(Get-ChildItem -LiteralPath (Join-Path $destination 'expanded') -Filter BootCamp.xml -Recurse -File |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.DirectoryName 'setup.exe') -PathType Leaf })
    if ($matches.Count -ne 1) { throw "Expected one BootCamp folder in Apple's archive, found $($matches.Count)." }
    return $matches[0].DirectoryName
}

function Find-BetterCampCachedPackage {
    $cache = Join-Path $env:LOCALAPPDATA 'BetterCamp/downloads'
    if (-not (Test-Path -LiteralPath $cache -PathType Container)) { return $null }
    $matches = @(Get-ChildItem -LiteralPath $cache -Filter BootCamp.xml -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.DirectoryName 'setup.exe') -PathType Leaf } |
        Sort-Object LastWriteTimeUtc -Descending)
    if ($matches.Count -eq 0) { return $null }
    return $matches[0].DirectoryName
}

function Get-BetterCampDriverInstallers($Machine) {
    if ($Machine.Model -ne 'MacBookPro9,2') {
        throw "Driver-only installation is currently verified only for MacBookPro9,2; detected $($Machine.Model)."
    }
    return @(
        'Intel\Chipset\Setup.exe',
        'Intel\IntelMgmtEngine.exe',
        'Intel\IntelxHCISetup.exe',
        'Intel\IntelHDLegacyGraphics64.exe',
        'Cirrus\CirrusAudioCS4206x64.exe',
        'Broadcom\BroadcomWirelessWin8x64.exe',
        'Broadcom\BroadcomEthernet64.exe',
        'Broadcom\BroadcomCardReader64.exe',
        'Apple\AppleBluetoothInstaller64.exe',
        'Apple\AppleCamera64.exe',
        'Apple\AppleDisplayInstaller64.exe',
        'Apple\AppleKeyboardInstaller64.exe',
        'Apple\AppleMultiTouchTrackPadInstaller64.exe',
        'Apple\AppleODDInstaller64.exe',
        'Apple\AppleNullDriver64.exe',
        'Apple\NullSystemDevice64.exe'
    )
}

function Get-BetterCampDriverHashes {
    return @{
        'Intel\Chipset\Setup.exe' = 'E341B83C11EA306ADED5F26B849BFEFBFC9152D3B1DDCA1254BE184E858C699F'
        'Intel\IntelMgmtEngine.exe' = '5DDFFE10CEF05BFFA510B42B18CC21AC148D63DF7A382E196AD36E76F17D06D1'
        'Intel\IntelxHCISetup.exe' = '60C66E9A06D0903452CCF31B7801770E4FCACAF26D83A67786D0318D43A1971A'
        'Intel\IntelHDLegacyGraphics64.exe' = 'AE590BAC3897E51E438B86BF1899E15E56FCF9784F8F2CCC69F45E59489E6FFC'
        'Cirrus\CirrusAudioCS4206x64.exe' = 'FC7751A5302CE8764C2D4D0E6F7D51AC74FD0B3246E1500DEAD6911330E0CDFE'
        'Broadcom\BroadcomWirelessWin8x64.exe' = '4AE62D4A8219C789B51DF1B7F5EA53ABDEA9E79782F5D8F1FB97D45A6909CBE3'
        'Broadcom\BroadcomEthernet64.exe' = '51AC0B72E27E9126807AB52464760296BC64D23C2D00694DDA41DBA789D05999'
        'Broadcom\BroadcomCardReader64.exe' = '9D909BA51FF5D487A2C6DF0244EF8FFB56263C6A653731E83FADE7B7ED5BF5D4'
        'Apple\AppleBluetoothInstaller64.exe' = '0730AB8A03C3E63D58A4CF4A23D9012986CEB443A58C7E7F4379C3F0FFEFA561'
        'Apple\AppleCamera64.exe' = 'C1880ABEE6615E884731EA14AF096B92693DE77A95AACE567AD456BC7FA5D321'
        'Apple\AppleDisplayInstaller64.exe' = '9214949F7620C3324AB2175EE3DA68EB3DFFB4F69914C737403F30A2C67DC063'
        'Apple\AppleKeyboardInstaller64.exe' = 'D17B4DDE778B8F63E8A9C5D9920DEC9CCFB4FCA3764FF4BAEB529CB68F0865BA'
        'Apple\AppleMultiTouchTrackPadInstaller64.exe' = 'C71F8037A0AF37418F399B9695D9DDAFCC0F736E2DA27148DD5381E3EBEFC7EE'
        'Apple\AppleODDInstaller64.exe' = '8DE05501A84C7A505EBF1C72A04EA2E1A35C8AF43501D5E6BCA8FBBC5CFD1F26'
        'Apple\AppleNullDriver64.exe' = 'DD028EA463CC28BFF7F85DC648748E1289E1A6D775F4C88C64037AD435B689BF'
        'Apple\NullSystemDevice64.exe' = 'B2984F788525338CFE8EC7EF2A926C53F7900041129A87920E08890A3DD76224'
    }
}

function Assert-BetterCampDriverHash([string]$Path, [string]$ExpectedHash, [string]$Label) {
    if ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -ne $ExpectedHash) {
        throw "Driver verification failed: $Label"
    }
}

function Install-BetterCampDrivers([string]$Path, $Machine) {
    $driversRoot = Join-Path $Path 'Drivers'
    $installers = @(Get-BetterCampDriverInstallers $Machine)
    $hashes = Get-BetterCampDriverHashes
    foreach ($relativePath in $installers) {
        $installer = Join-Path $driversRoot $relativePath
        if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) {
            throw "Required MacBookPro9,2 driver installer not found: $relativePath"
        }
        Assert-BetterCampDriverHash -Path $installer -ExpectedHash $hashes[$relativePath] -Label $relativePath
    }
    $restartRequired = $false
    foreach ($relativePath in $installers) {
        $installer = Join-Path $driversRoot $relativePath
        Write-Host "Installing driver: $relativePath"
        $process = Start-Process -FilePath $installer -WorkingDirectory (Split-Path $installer -Parent) -Wait -PassThru
        if ($process.ExitCode -notin @(0, 1641, 3010)) {
            throw "Driver installer failed: $relativePath (exit $($process.ExitCode))."
        }
        if ($process.ExitCode -in @(1641, 3010)) { $restartRequired = $true }
    }
    return [pscustomobject]@{ Count = $installers.Count; RestartRequired = $restartRequired }
}

function Get-BetterCampInstalledSoftware([string[]]$Names) {
    $roots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    return @(Get-ItemProperty -Path $roots -ErrorAction SilentlyContinue |
        Where-Object {
            $displayName = $_.PSObject.Properties['DisplayName']
            $productCode = $_.PSObject.Properties['PSChildName']
            $null -ne $displayName -and $null -ne $productCode -and
                $displayName.Value -in $Names -and
                $productCode.Value -match '^\{[0-9A-Fa-f-]{36}\}$'
        } |
        Sort-Object PSChildName -Unique)
}

function Remove-BetterCampSoftware {
    Get-Process -Name 'Bootcamp', 'AppleOSSMgr', 'AppleTimeSrv' -ErrorAction SilentlyContinue |
        Stop-Process -Force -ErrorAction SilentlyContinue
    $logRoot = Join-Path $env:LOCALAPPDATA 'BetterCamp/logs'
    New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
    $successCodes = @(0, 1605, 1614, 1641, 3010)
    $bootCampProducts = @(Get-BetterCampInstalledSoftware @('Boot Camp', 'Boot Camp Services'))
    if ($bootCampProducts.Count -eq 0) {
        Write-Host 'Boot Camp Manager is not registered as installed; it may already have been removed.'
    } else {
        $cached = Find-BetterCampCachedPackage
        $bootCampMsi = if ($cached) { Join-Path $cached 'Drivers\Apple\BootCamp.msi' } else { $null }
        foreach ($product in $bootCampProducts) {
            $target = $product.PSChildName
            if ($bootCampMsi -and (Test-Path -LiteralPath $bootCampMsi -PathType Leaf)) { $target = $bootCampMsi }
            $msiLog = Join-Path $logRoot ('cleanup-bootcamp-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '.log')
            Write-Host "Removing software while preserving device drivers: $($product.DisplayName)"
            $result = Invoke-BetterCampNative 'msiexec.exe' @('/x', $target, '/passive', '/norestart', '/L*v', $msiLog)
            if ($result.ExitCode -notin $successCodes) {
                throw "Could not remove $($product.DisplayName) (MSI exit $($result.ExitCode)). Installer log: $msiLog"
            }
        }
    }
    $updateProducts = @(Get-BetterCampInstalledSoftware @('Apple Software Update'))
    foreach ($product in $updateProducts) {
        $msiLog = Join-Path $logRoot ('cleanup-apple-update-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '.log')
        Write-Host "Removing optional software: $($product.DisplayName)"
        $result = Invoke-BetterCampNative 'msiexec.exe' @('/x', $product.PSChildName, '/passive', '/norestart', '/L*v', $msiLog)
        if ($result.ExitCode -notin $successCodes) {
            Write-Warning "Apple Software Update could not be removed (MSI exit $($result.ExitCode)). Boot Camp Manager cleanup can still succeed. Log: $msiLog"
        }
    }
    Write-Host 'Boot Camp Manager and Control Panel cleanup completed. Device drivers were preserved.'
}

function Assert-BetterCampFileHash([string]$Path, [string]$ExpectedHash) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Required audio patch file not found: $Path" }
    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if ($actual -ne $ExpectedHash) { throw "Audio patch file verification failed: $Path" }
}

function Invoke-BetterCampNative([string]$FilePath, [string[]]$Arguments) {
    $previousPreference = $ErrorActionPreference
    $output = @()
    $exitCode = 1
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& $FilePath @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previousPreference }
    foreach ($line in $output) { Write-Host $line }
    return [pscustomobject]@{ ExitCode = $exitCode; Output = ($output -join [Environment]::NewLine) }
}

function Get-BetterCampCurrentBcdOutput {
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& "$env:SystemRoot\System32\bcdedit.exe" /enum '{current}' 2>&1)
        if ($LASTEXITCODE -ne 0) { return '' }
        return ($output -join [Environment]::NewLine)
    } finally { $ErrorActionPreference = $previousPreference }
}

function Get-BetterCampEffectiveFirmware($Machine) {
    $loader = Get-BetterCampWindowsLoaderInfo (Get-BetterCampCurrentBcdOutput)
    if ($null -eq $loader) { return $Machine.Firmware }
    if ($Machine.Firmware -ne 'Unknown' -and $Machine.Firmware -ne $loader.Firmware) {
        Write-Warning "Firmware indicators disagree: PEFirmwareType reports $($Machine.Firmware), but the current BCD entry uses $($loader.Path). BetterCamp will use the active Windows loader mode $($loader.Firmware)."
    }
    return $loader.Firmware
}

function Get-BetterCampAudioPatchPaths([string]$Root) {
    $directory = Join-Path $Root 'Audio_2011_2012'
    $systemRootOverride = Get-Variable -Name BetterCampSystemRootOverride -Scope Script -ValueOnly -ErrorAction SilentlyContinue
    $systemRoot = if ($systemRootOverride) { [string]$systemRootOverride } else { $env:SystemRoot }
    [pscustomobject]@{
        Tool = Join-Path $directory 'asl.exe'
        Table = Join-Path $directory 'dsdt_2012.aml'
        OverrideTable = Join-Path $env:LOCALAPPDATA 'BetterCamp/audio/dsdt_2012_override.aml'
        SystemTable = Join-Path $systemRoot 'System32/acpitabl.dat'
        State = Join-Path $env:LOCALAPPDATA 'BetterCamp/audio-patch.json'
    }
}

function New-BetterCampAudioOverrideTable([string]$Source, [string]$Destination) {
    $bytes = [IO.File]::ReadAllBytes($Source)
    if ($bytes.Length -lt 36 -or [Text.Encoding]::ASCII.GetString($bytes, 0, 4) -ne 'DSDT') {
        throw 'The bundled audio table has an invalid ACPI header.'
    }
    $tableLength = [BitConverter]::ToUInt32($bytes, 4)
    if ($tableLength -ne $bytes.Length) { throw 'The bundled audio table length is invalid.' }
    # Windows loads an ACPI registry override only when its OEM revision is higher than firmware.
    [Array]::Copy([BitConverter]::GetBytes([uint32]0x7FFFFFFF), 0, $bytes, 24, 4)
    $bytes[9] = 0
    $sum = 0
    foreach ($value in $bytes) { $sum = ($sum + $value) -band 0xFF }
    $bytes[9] = [byte]((256 - $sum) -band 0xFF)
    New-Item -ItemType Directory -Path (Split-Path $Destination -Parent) -Force | Out-Null
    [IO.File]::WriteAllBytes($Destination, $bytes)
    return (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash
}

function Install-BetterCampAudioPatch($Machine, [string]$Root) {
    if ($Machine.Model -ne 'MacBookPro9,2') {
        throw "The bundled 2012 audio table is verified only for MacBookPro9,2; detected $($Machine.Model)."
    }
    $effectiveFirmware = Get-BetterCampEffectiveFirmware $Machine
    if ($effectiveFirmware -ne 'UEFI') {
        Write-Host 'Legacy BIOS boot detected; the UEFI audio patch is not required.'
        return $false
    }
    $secureBootEnabled = $false
    try { $secureBootEnabled = [bool](Confirm-SecureBootUEFI) }
    catch { Write-Verbose 'Secure Boot state is unavailable; older Macs normally do not implement Windows Secure Boot.' }
    if ($secureBootEnabled) { throw 'Secure Boot must be disabled before Windows can load an overridden ACPI table.' }

    $paths = Get-BetterCampAudioPatchPaths $Root
    Assert-BetterCampFileHash $paths.Table '9C16ADF17E7F4F6462A8E598616D81E37E4CEA8B436DD92B535F543C4AF36F87'
    $overrideHash = New-BetterCampAudioOverrideTable -Source $paths.Table -Destination $paths.OverrideTable
    if ($overrideHash -ne '9AD7A614D2CDB7A67A47C0959B00B0CA188811623753DB229F3E56D71B13990D') {
        throw 'The generated audio table did not match the verified repair revision.'
    }
    $priorState = $null
    if (Test-Path -LiteralPath $paths.State -PathType Leaf) {
        try { $priorState = Get-Content -LiteralPath $paths.State -Raw | ConvertFrom-Json } catch { }
        if ($null -ne $priorState -and $priorState.Model -ne 'MacBookPro9,2') { $priorState = $null }
    }
    $systemTableOwnedBefore = $null -ne $priorState -and
        'SystemTableCreatedByBetterCamp' -in $priorState.PSObject.Properties.Name -and
        [bool]$priorState.SystemTableCreatedByBetterCamp
    $systemTableExisted = Test-Path -LiteralPath $paths.SystemTable -PathType Leaf
    if ($systemTableExisted) {
        $existingSystemHash = (Get-FileHash -LiteralPath $paths.SystemTable -Algorithm SHA256).Hash
        if ($existingSystemHash -ne $overrideHash) {
            throw "Windows already has a different ACPI override at $($paths.SystemTable). It was not overwritten."
        }
    }

    $current = Invoke-BetterCampNative 'bcdedit.exe' @('/enum', '{current}')
    if ($current.ExitCode -ne 0) { throw 'Could not read the current Windows boot configuration.' }
    $testSigningMatch = [regex]::Match($current.Output, '(?im)^testsigning\s+(.+?)\s*$')
    if (-not $testSigningMatch.Success) { $testSigningWasEnabled = $false }
    elseif ($testSigningMatch.Groups[1].Value -match '^(Yes|On|true|1)$') { $testSigningWasEnabled = $true }
    elseif ($testSigningMatch.Groups[1].Value -match '^(No|Off|false|0)$') { $testSigningWasEnabled = $false }
    else { $testSigningWasEnabled = $null }
    $testSigningBeforeThisRun = $testSigningWasEnabled
    $testSigningForRecovery = $testSigningBeforeThisRun
    if ($null -ne $priorState -and 'TestSigningWasEnabled' -in $priorState.PSObject.Properties.Name) {
        $testSigningForRecovery = [bool]$priorState.TestSigningWasEnabled
    }
    if ($testSigningBeforeThisRun -ne $true) {
        $enabled = Invoke-BetterCampNative 'bcdedit.exe' @('/set', '{current}', 'testsigning', 'on')
        if ($enabled.ExitCode -ne 0) { throw 'Could not enable Windows test-signing mode. Secure Boot or BitLocker policy may be blocking the change.' }
    }

    try {
        if (-not $systemTableExisted) { Copy-Item -LiteralPath $paths.OverrideTable -Destination $paths.SystemTable }
        Assert-BetterCampFileHash $paths.SystemTable $overrideHash
    } catch {
        if (-not $systemTableExisted -and (Test-Path -LiteralPath $paths.SystemTable)) { Remove-Item -LiteralPath $paths.SystemTable -Force }
        if ($testSigningBeforeThisRun -eq $false) { Invoke-BetterCampNative 'bcdedit.exe' @('/set', '{current}', 'testsigning', 'off') | Out-Null }
        throw "Could not install the Windows ACPI boot override: $($_.Exception.Message)"
    }

    try {
        $stateDirectory = Split-Path $paths.State -Parent
        New-Item -ItemType Directory -Path $stateDirectory -Force | Out-Null
        [pscustomobject]@{
            Model = $Machine.Model
            AppliedAt = (Get-Date).ToString('o')
            TestSigningWasEnabled = $testSigningForRecovery
            ToolSha256 = '279AE784566DBB344539E6495CF12CC96C95BD75B189026A5488E6E4EE8A31BB'
            SourceTableSha256 = '9C16ADF17E7F4F6462A8E598616D81E37E4CEA8B436DD92B535F543C4AF36F87'
            TableSha256 = $overrideHash
            TablePath = $paths.OverrideTable
            SystemTablePath = $paths.SystemTable
            SystemTableCreatedByBetterCamp = ($systemTableOwnedBefore -or (-not $systemTableExisted))
            RegistryTableLoaded = $false
            OemRevision = '0x7FFFFFFF'
        } | ConvertTo-Json | Set-Content -LiteralPath $paths.State -Encoding UTF8
    } catch {
        $stateError = $_.Exception.Message
        if (-not $systemTableExisted -and (Test-Path -LiteralPath $paths.SystemTable)) { Remove-Item -LiteralPath $paths.SystemTable -Force }
        $signingRollback = $null
        if ($testSigningBeforeThisRun -eq $false) {
            $signingRollback = Invoke-BetterCampNative 'bcdedit.exe' @('/set', '{current}', 'testsigning', 'off')
        }
        if (Test-Path -LiteralPath $paths.State) { Remove-Item -LiteralPath $paths.State -Force }
        $rollbackStatus = 'boot-table=removed'
        if ($null -ne $signingRollback) { $rollbackStatus += ", testsigning=$($signingRollback.ExitCode)" }
        throw "Could not save the audio patch recovery state ($stateError). Changes were rolled back where possible ($rollbackStatus)."
    }
    Write-Host 'MacBookPro9,2 UEFI audio patch installed. It becomes active after Windows restarts.'
    return $true
}

function Repair-BetterCampAudio([string]$Path, $Machine, [string]$Root) {
    $effectiveFirmware = Get-BetterCampEffectiveFirmware $Machine
    Install-BetterCampAudioPatch -Machine $Machine -Root $Root | Out-Null
    $cirrus = Join-Path $Path 'Drivers\Cirrus\CirrusAudioCS4206x64.exe'
    if (-not (Test-Path -LiteralPath $cirrus -PathType Leaf)) { throw 'The Cirrus CS4206 driver installer is missing.' }
    $cirrusHash = (Get-BetterCampDriverHashes)['Cirrus\CirrusAudioCS4206x64.exe']
    Assert-BetterCampDriverHash -Path $cirrus -ExpectedHash $cirrusHash -Label 'Cirrus\CirrusAudioCS4206x64.exe'
    if ($effectiveFirmware -eq 'BIOS') {
        $legacyControllers = @(Get-CimInstance -ClassName Win32_PnPEntity | Where-Object {
            $_.ConfigManagerErrorCode -eq 10 -and $_.PNPDeviceID -match '^PCI\\VEN_8086&DEV_(1C20|1E20)(?:&|\\|$)'
        })
        foreach ($controller in $legacyControllers) {
            Write-Host "Removing failed Legacy BIOS audio controller for redetection: $($controller.PNPDeviceID)"
            $removed = Invoke-BetterCampNative 'pnputil.exe' @('/remove-device', $controller.PNPDeviceID)
            if ($removed.ExitCode -ne 0) { Write-Warning "Windows could not remove the failed audio controller (exit $($removed.ExitCode)); continuing with driver reinstall." }
        }
    }
    Write-Host 'Reinstalling the MacBookPro9,2 Cirrus CS4206 audio driver.'
    $process = Start-Process -FilePath $cirrus -WorkingDirectory (Split-Path $cirrus -Parent) -Wait -PassThru
    if ($process.ExitCode -notin @(0, 1641, 3010)) { throw "Cirrus audio driver installation failed (exit $($process.ExitCode))." }
    $scan = Invoke-BetterCampNative 'pnputil.exe' @('/scan-devices')
    if ($scan.ExitCode -ne 0) { Write-Warning 'Windows device rescan failed; the reboot will still perform hardware discovery.' }
    $problems = @(Get-CimInstance -ClassName Win32_PnPEntity | Where-Object {
        $_.ConfigManagerErrorCode -ne 0 -and (Test-BetterCampAudioDevice $_)
    })
    foreach ($device in $problems) {
        Write-Host "Pending device: $($device.Name) | Code $($device.ConfigManagerErrorCode) | $($device.PNPDeviceID)"
    }
    if ($effectiveFirmware -eq 'BIOS') {
        Write-Host 'Legacy BIOS audio repair completed. Shut Windows down fully, wait 20 seconds, then power the MacBook on before judging Code 10.'
    } else {
        Write-Host 'Audio repair staged with a higher ACPI table revision. Restart Windows before judging Code 10.'
    }
}

function Test-BetterCampAudioDevice($Device) {
    $nameProperty = $Device.PSObject.Properties['Name']
    $idProperty = $Device.PSObject.Properties['PNPDeviceID']
    $name = if ($null -ne $nameProperty) { [string]$nameProperty.Value } else { '' }
    $id = if ($null -ne $idProperty) { [string]$idProperty.Value } else { '' }
    return $name -match 'Audio|Cirrus|High Definition' -or
        $id -match '^HDAUDIO\\' -or
        $id -match '^PCI\\VEN_8086&DEV_(1C20|1E20)(?:&|\\|$)'
}

function Get-BetterCampActiveDsdtInfo {
    $registryRoot = 'Registry::HKEY_LOCAL_MACHINE\HARDWARE\ACPI\DSDT'
    $tables = @()
    foreach ($key in @(Get-ChildItem -LiteralPath $registryRoot -Recurse -ErrorAction SilentlyContinue)) {
        $revisionProperty = $key.PSObject.Properties['PSChildName']
        if ($null -eq $revisionProperty -or [string]$revisionProperty.Value -notmatch '^[0-9A-Fa-f]{8}$') { continue }
        try { $values = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction Stop } catch { continue }
        $binaryProperty = $values.PSObject.Properties['00000000']
        if ($null -eq $binaryProperty -or $binaryProperty.Value -isnot [byte[]]) { continue }
        $bytes = [byte[]]$binaryProperty.Value
        if ($bytes.Length -lt 36 -or [Text.Encoding]::ASCII.GetString($bytes, 0, 4) -ne 'DSDT') { continue }
        $sha = [Security.Cryptography.SHA256]::Create()
        try { $hash = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '') }
        finally { $sha.Dispose() }
        $tables += [pscustomobject]@{
            Revision = '0x' + ([string]$revisionProperty.Value).ToUpperInvariant()
            OemId = [Text.Encoding]::ASCII.GetString($bytes, 10, 6).Trim()
            OemTableId = [Text.Encoding]::ASCII.GetString($bytes, 16, 8).Trim()
            Sha256 = $hash
        }
    }
    return @($tables | Sort-Object Revision -Unique)
}

function Get-BetterCampWindowsLoaderInfo([string]$BcdOutput) {
    $match = [regex]::Match($BcdOutput, '(?i)\\Windows\\system32\\winload\.(efi|exe)')
    if (-not $match.Success) { return $null }
    return [pscustomobject]@{
        Path = $match.Value
        Firmware = if ($match.Groups[1].Value -ieq 'efi') { 'UEFI' } else { 'BIOS' }
    }
}

function Show-BetterCampAudioDiagnosis([string]$Root, $Machine) {
    $paths = Get-BetterCampAudioPatchPaths $Root
    if (Test-Path -LiteralPath $paths.State) {
        try {
            $state = Get-Content -LiteralPath $paths.State -Raw | ConvertFrom-Json
            Write-Host "Audio patch state: applied $($state.AppliedAt), table revision $($state.OemRevision)"
        } catch { Write-Warning 'Audio patch state exists but cannot be read.' }
    } else { Write-Host 'Audio patch state: not installed by this BetterCamp version' }
    $expectedOverrideHash = '9AD7A614D2CDB7A67A47C0959B00B0CA188811623753DB229F3E56D71B13990D'
    if (Test-Path -LiteralPath $paths.SystemTable -PathType Leaf) {
        $systemTableHash = (Get-FileHash -LiteralPath $paths.SystemTable -Algorithm SHA256).Hash
        $systemTableStatus = if ($systemTableHash -eq $expectedOverrideHash) { 'verified BetterCamp table' } else { 'different table' }
        Write-Host "Windows ACPI boot file: $systemTableStatus | $systemTableHash"
    } else {
        Write-Host 'Windows ACPI boot file: missing'
    }
    $activeTables = @(Get-BetterCampActiveDsdtInfo)
    if ($activeTables.Count -eq 0) {
        Write-Warning 'Windows did not expose an active DSDT through the ACPI registry.'
    } else {
        foreach ($table in $activeTables) {
            $activeStatus = if ($table.Sha256 -eq $expectedOverrideHash) { 'active BetterCamp override' } else { 'firmware or other table' }
            Write-Host "Active DSDT: $activeStatus | revision $($table.Revision) | $($table.OemId)/$($table.OemTableId) | $($table.Sha256)"
        }
    }
    $boot = Invoke-BetterCampNative 'bcdedit.exe' @('/enum', '{current}')
    $loader = Get-BetterCampWindowsLoaderInfo $boot.Output
    if ($null -ne $loader) {
        Write-Host "Windows boot loader: $($loader.Path) ($($loader.Firmware))"
        if ($null -ne $Machine -and $Machine.Firmware -ne 'Unknown' -and $Machine.Firmware -ne $loader.Firmware) {
            Write-Warning "Firmware indicators disagree: PEFirmwareType reports $($Machine.Firmware), but the current BCD entry uses $($loader.Path). BetterCamp will use the active Windows loader mode $($loader.Firmware) for audio repair."
        }
    } else {
        Write-Host 'Windows boot loader: not shown in the current boot entry'
    }
    $testSigning = [regex]::Match($boot.Output, '(?im)^testsigning\s+(.+?)\s*$')
    if ($testSigning.Success) { Write-Host "Windows test signing: $($testSigning.Groups[1].Value)" }
    else { Write-Host 'Windows test signing: not shown in the current boot entry' }
    $devices = @(Get-CimInstance -ClassName Win32_PnPEntity | Where-Object {
        Test-BetterCampAudioDevice $_
    })
    foreach ($device in $devices) {
        Write-Host "Audio device: $($device.Name) | Code $($device.ConfigManagerErrorCode) | $($device.PNPDeviceID)"
    }
}

function Remove-BetterCampAudioPatch($Machine, [string]$Root) {
    if ($Machine.Model -ne 'MacBookPro9,2') { throw "Audio patch removal is limited to MacBookPro9,2; detected $($Machine.Model)." }
    $paths = Get-BetterCampAudioPatchPaths $Root
    Assert-BetterCampFileHash $paths.Tool '279AE784566DBB344539E6495CF12CC96C95BD75B189026A5488E6E4EE8A31BB'
    Assert-BetterCampFileHash $paths.Table '9C16ADF17E7F4F6462A8E598616D81E37E4CEA8B436DD92B535F543C4AF36F87'
    $state = $null
    if (Test-Path -LiteralPath $paths.State) {
        try { $state = Get-Content -LiteralPath $paths.State -Raw | ConvertFrom-Json }
        catch { throw 'The BetterCamp audio patch state is damaged. No boot or ACPI settings were changed.' }
        $required = @('Model', 'TestSigningWasEnabled', 'ToolSha256', 'TableSha256')
        foreach ($name in $required) {
            if ($name -notin $state.PSObject.Properties.Name) { throw "The BetterCamp audio patch state is missing $name. No settings were changed." }
        }
        if ($state.Model -ne 'MacBookPro9,2' -or
            $state.ToolSha256 -ne '279AE784566DBB344539E6495CF12CC96C95BD75B189026A5488E6E4EE8A31BB' -or
            $state.TableSha256 -notin @('9C16ADF17E7F4F6462A8E598616D81E37E4CEA8B436DD92B535F543C4AF36F87', '9AD7A614D2CDB7A67A47C0959B00B0CA188811623753DB229F3E56D71B13990D')) {
            throw 'The BetterCamp audio patch state does not match this patch. No settings were changed.'
        }
    }
    $tableToRemove = $paths.Table
    if ($null -ne $state -and 'TablePath' -in $state.PSObject.Properties.Name) {
        if ([IO.Path]::GetFullPath([string]$state.TablePath) -ne [IO.Path]::GetFullPath($paths.OverrideTable)) {
            throw 'The BetterCamp audio patch state contains an unexpected table path. No settings were changed.'
        }
        Assert-BetterCampFileHash $paths.OverrideTable ([string]$state.TableSha256)
        $tableToRemove = $paths.OverrideTable
    } elseif ($null -ne $state -and $state.TableSha256 -ne '9C16ADF17E7F4F6462A8E598616D81E37E4CEA8B436DD92B535F543C4AF36F87') {
        throw 'The BetterCamp audio patch state does not match the legacy table. No settings were changed.'
    }
    $removeSystemTable = $false
    if ($null -ne $state -and 'SystemTableCreatedByBetterCamp' -in $state.PSObject.Properties.Name -and $state.SystemTableCreatedByBetterCamp) {
        if ('SystemTablePath' -notin $state.PSObject.Properties.Name -or
            [IO.Path]::GetFullPath([string]$state.SystemTablePath) -ne [IO.Path]::GetFullPath($paths.SystemTable)) {
            throw 'The BetterCamp audio patch state contains an unexpected system table path. No settings were changed.'
        }
        Assert-BetterCampFileHash $paths.SystemTable '9AD7A614D2CDB7A67A47C0959B00B0CA188811623753DB229F3E56D71B13990D'
        $removeSystemTable = $true
    }
    if ($null -eq $state) {
        Write-Warning 'No BetterCamp state file was found, so test-signing mode was left unchanged.'
    } elseif ($state.TestSigningWasEnabled -eq $false) {
        $disabled = Invoke-BetterCampNative 'bcdedit.exe' @('/set', '{current}', 'testsigning', 'off')
        if ($disabled.ExitCode -ne 0) { throw 'Windows test-signing mode could not be restored; the ACPI table was left unchanged.' }
    }
    $registryTableLoaded = $null -ne $state -and
        ('RegistryTableLoaded' -notin $state.PSObject.Properties.Name -or [bool]$state.RegistryTableLoaded)
    if ($registryTableLoaded) {
        $removed = Invoke-BetterCampNative $paths.Tool @('/loadtable', '-v', '-d', $tableToRemove)
        if ($removed.ExitCode -ne 0) { throw 'Test-signing mode was restored when applicable, but the legacy registry ACPI table could not be removed.' }
        if ($tableToRemove -ne $paths.Table) { Invoke-BetterCampNative $paths.Tool @('/loadtable', '-v', '-d', $paths.Table) | Out-Null }
    }
    if ($removeSystemTable) { Remove-Item -LiteralPath $paths.SystemTable -Force }
    if ($null -ne $state) { Remove-Item -LiteralPath $paths.State -Force }
    if (Test-Path -LiteralPath $paths.OverrideTable) { Remove-Item -LiteralPath $paths.OverrideTable -Force }
    Write-Host 'UEFI audio patch removed. Restart Windows to finish reverting it.'
}
