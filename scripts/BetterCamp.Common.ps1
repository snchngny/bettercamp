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

function Install-BetterCampPackage([string]$Path) {
    $process = Start-Process -FilePath (Join-Path $Path 'setup.exe') -WorkingDirectory $Path -Wait -PassThru
    if ($process.ExitCode -notin @(0, 1641, 3010)) { throw "Apple installer returned exit code $($process.ExitCode). See the installer message and log." }
    return $process.ExitCode
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

function Get-BetterCampAudioPatchPaths([string]$Root) {
    $directory = Join-Path $Root 'Audio_2011_2012'
    [pscustomobject]@{
        Tool = Join-Path $directory 'asl.exe'
        Table = Join-Path $directory 'dsdt_2012.aml'
        State = Join-Path $env:LOCALAPPDATA 'BetterCamp/audio-patch.json'
    }
}

function Install-BetterCampAudioPatch($Machine, [string]$Root) {
    if ($Machine.Model -ne 'MacBookPro9,2') {
        throw "The bundled 2012 audio table is verified only for MacBookPro9,2; detected $($Machine.Model)."
    }
    if ($Machine.Firmware -ne 'UEFI') {
        Write-Host 'Legacy BIOS boot detected; the UEFI audio patch is not required.'
        return $false
    }
    $secureBootEnabled = $false
    try { $secureBootEnabled = [bool](Confirm-SecureBootUEFI) }
    catch { Write-Verbose 'Secure Boot state is unavailable; older Macs normally do not implement Windows Secure Boot.' }
    if ($secureBootEnabled) { throw 'Secure Boot must be disabled before Windows can load an overridden ACPI table.' }

    $paths = Get-BetterCampAudioPatchPaths $Root
    Assert-BetterCampFileHash $paths.Tool '279AE784566DBB344539E6495CF12CC96C95BD75B189026A5488E6E4EE8A31BB'
    Assert-BetterCampFileHash $paths.Table '9C16ADF17E7F4F6462A8E598616D81E37E4CEA8B436DD92B535F543C4AF36F87'

    $current = Invoke-BetterCampNative 'bcdedit.exe' @('/enum', '{current}')
    if ($current.ExitCode -ne 0) { throw 'Could not read the current Windows boot configuration.' }
    $testSigningMatch = [regex]::Match($current.Output, '(?im)^testsigning\s+(.+?)\s*$')
    if (-not $testSigningMatch.Success) { $testSigningWasEnabled = $false }
    elseif ($testSigningMatch.Groups[1].Value -match '^(Yes|On|true|1)$') { $testSigningWasEnabled = $true }
    elseif ($testSigningMatch.Groups[1].Value -match '^(No|Off|false|0)$') { $testSigningWasEnabled = $false }
    else { $testSigningWasEnabled = $null }
    if ($testSigningWasEnabled -ne $true) {
        $enabled = Invoke-BetterCampNative 'bcdedit.exe' @('/set', '{current}', 'testsigning', 'on')
        if ($enabled.ExitCode -ne 0) { throw 'Could not enable Windows test-signing mode. Secure Boot or BitLocker policy may be blocking the change.' }
    }

    $loaded = Invoke-BetterCampNative $paths.Tool @('/loadtable', '-v', $paths.Table)
    if ($loaded.ExitCode -ne 0) {
        if ($testSigningWasEnabled -eq $false) { Invoke-BetterCampNative 'bcdedit.exe' @('/set', '{current}', 'testsigning', 'off') | Out-Null }
        throw 'The MacBookPro9,2 ACPI audio table could not be loaded; the test-signing change was rolled back when possible.'
    }

    try {
        $stateDirectory = Split-Path $paths.State -Parent
        New-Item -ItemType Directory -Path $stateDirectory -Force | Out-Null
        [pscustomobject]@{
            Model = $Machine.Model
            AppliedAt = (Get-Date).ToString('o')
            TestSigningWasEnabled = $testSigningWasEnabled
            ToolSha256 = '279AE784566DBB344539E6495CF12CC96C95BD75B189026A5488E6E4EE8A31BB'
            TableSha256 = '9C16ADF17E7F4F6462A8E598616D81E37E4CEA8B436DD92B535F543C4AF36F87'
        } | ConvertTo-Json | Set-Content -LiteralPath $paths.State -Encoding UTF8
    } catch {
        $stateError = $_.Exception.Message
        $tableRollback = Invoke-BetterCampNative $paths.Tool @('/loadtable', '-v', '-d', $paths.Table)
        $signingRollback = $null
        if ($testSigningWasEnabled -eq $false) {
            $signingRollback = Invoke-BetterCampNative 'bcdedit.exe' @('/set', '{current}', 'testsigning', 'off')
        }
        if (Test-Path -LiteralPath $paths.State) { Remove-Item -LiteralPath $paths.State -Force }
        $rollbackStatus = "table=$($tableRollback.ExitCode)"
        if ($null -ne $signingRollback) { $rollbackStatus += ", testsigning=$($signingRollback.ExitCode)" }
        throw "Could not save the audio patch recovery state ($stateError). Changes were rolled back where possible ($rollbackStatus)."
    }
    Write-Host 'MacBookPro9,2 UEFI audio patch installed. It becomes active after Windows restarts.'
    return $true
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
            $state.TableSha256 -ne '9C16ADF17E7F4F6462A8E598616D81E37E4CEA8B436DD92B535F543C4AF36F87') {
            throw 'The BetterCamp audio patch state does not match this patch. No settings were changed.'
        }
    }
    if ($null -eq $state) {
        Write-Warning 'No BetterCamp state file was found, so test-signing mode was left unchanged.'
    } elseif ($state.TestSigningWasEnabled -eq $false) {
        $disabled = Invoke-BetterCampNative 'bcdedit.exe' @('/set', '{current}', 'testsigning', 'off')
        if ($disabled.ExitCode -ne 0) { throw 'Windows test-signing mode could not be restored; the ACPI table was left unchanged.' }
    }
    $removed = Invoke-BetterCampNative $paths.Tool @('/loadtable', '-v', '-d', $paths.Table)
    if ($removed.ExitCode -ne 0) { throw 'Test-signing mode was restored when applicable, but the ACPI audio table could not be removed.' }
    if ($null -ne $state) { Remove-Item -LiteralPath $paths.State -Force }
    Write-Host 'UEFI audio patch removed. Restart Windows to finish reverting it.'
}
