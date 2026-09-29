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
