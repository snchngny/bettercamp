# Windows PowerShell 5.1. Package retrieval never installs drivers.
function Get-BetterCampMacminiArchiveInfo {
    return [pscustomobject]@{
        Product = '041-91731'
        Version = [version]'6.1.7139'
        Uri = 'https://swcdn.apple.com/content/downloads/23/15/041-91731-A_LBI7Q8UWOG/juk1ng0hm623gxh3jv4qxt190ga1h5p0lw/BootCampESD.pkg'
        Sha256 = 'D655289AC44A00D3ABC20D01134ACF7B38AAD2AD98BB3C46C9DA4C12E1F28D85'
    }
}

function Get-BetterCampSevenZip {
    $directory = Join-Path $env:LOCALAPPDATA 'BetterCamp/tools/7zip-26.06'
    $executable = Join-Path $directory 'portable/7z.exe'
    $library = Join-Path $directory 'portable/7z.dll'
    $exeHash = 'DC0493429FE28136FCB177A0E77C9875CBB3B0BFF5F2F8EEBA4DF302E98CEF76'
    $dllHash = '500DB9EB17F3C21B729BA41DD02ECFE1823DA05028C7E4BA129084CC74CC364E'
    if (-not (Test-Path -LiteralPath $executable) -or -not (Test-Path -LiteralPath $library)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
        $bootstrap = Join-Path $directory '7zr.exe'
        $archive = Join-Path $directory '7z2606-x64.exe'
        Invoke-WebRequest -Uri 'https://github.com/ip7z/7zip/releases/download/26.06/7zr.exe' -OutFile $bootstrap -UseBasicParsing -TimeoutSec 180
        Assert-BetterCampDriverHash $bootstrap 'E80DB2DAD715A6C5ADABE292D31ED54E11F4E9B99CA349827B50573B175891BC' '7-Zip bootstrap'
        Invoke-WebRequest -Uri 'https://github.com/ip7z/7zip/releases/download/26.06/7z2606-x64.exe' -OutFile $archive -UseBasicParsing -TimeoutSec 180
        Assert-BetterCampDriverHash $archive '9B697F65ECC2D9B0152F5EE96D72DDE522A7827690349D9307935DACF40F42EC' '7-Zip archive'
        # Treat the installer as an archive; do not run it or register 7-Zip.
        $result = Invoke-BetterCampNative $bootstrap @('x', $archive, ('-o' + (Join-Path $directory 'portable')), '-y', '-bso0')
        if ($result.ExitCode -ne 0) { throw 'Could not extract the portable 7-Zip runtime.' }
    }
    Assert-BetterCampDriverHash $executable $exeHash '7-Zip executable'
    Assert-BetterCampDriverHash $library $dllHash '7-Zip library'
    return $executable
}

function Expand-BetterCampMacminiArchive([string]$Tool, [string]$Archive, [string]$Destination, [string[]]$Members = @()) {
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    $arguments = @('x', $Archive, ('-o' + $Destination), '-y', '-bso0') + $Members
    $result = Invoke-BetterCampNative $Tool $arguments
    if ($result.ExitCode -ne 0) { throw "Archive extraction failed: $Archive (exit $($result.ExitCode))." }
}

function Find-BetterCampSingleFile([string]$Root, [string]$Filter) {
    $files = @(Get-ChildItem -LiteralPath $Root -Filter $Filter -Recurse -File)
    if ($files.Count -ne 1) { throw "Expected exactly one $Filter under $Root; found $($files.Count)." }
    return $files[0].FullName
}

# A deterministic digest covers names and bytes, including every INF dependency.
# Checking only the INF or setup.exe signature would leave SYS/DLL payloads unchecked.
function Get-BetterCampTreeHash([string]$Path) {
    $root = (Get-Item -LiteralPath $Path -Force)
    if (-not $root.PSIsContainer -or ($root.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "Expected an ordinary directory: $Path"
    }
    $entries = @(Get-ChildItem -LiteralPath $root.FullName -Recurse -Force)
    if (@($entries | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count -gt 0) {
        throw 'Driver packages must not contain symbolic links or junctions.'
    }
    $records = @($entries | Where-Object { -not $_.PSIsContainer } | ForEach-Object {
        $relative = $_.FullName.Substring($root.FullName.TrimEnd('\').Length + 1).Replace('\', '/').ToLowerInvariant()
        $relative + ':' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToUpperInvariant()
    })
    [Array]::Sort($records, [StringComparer]::Ordinal)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes(($records -join "`n"))))).Replace('-', '') }
    finally { $sha.Dispose() }
}

function Assert-BetterCampMacminiPackage([string]$Path) {
    $bootcamp = Join-Path $Path 'BootCamp'
    if ((Get-BetterCampVersion $bootcamp) -ne (Get-BetterCampMacminiArchiveInfo).Version) {
        throw 'Mac mini 2018 requires the verified Apple 041-91731 / Boot Camp 6.1.7139 package.'
    }
    foreach ($tree in @(
        @{Name='BootCamp';Hash='51BEF3C8917721D6A2076F68A7849B5C85C3E8559E945E5A8B161ED463BD63FC'},
        @{Name='$WinPEDriver$';Hash='B7AA0DCF327E9827AC3CE64CB86A215D1FA1C31FEF27F16EAD36DADE8F7E22D7'}
    )) {
        if ((Get-BetterCampTreeHash (Join-Path $Path $tree.Name)) -ne $tree.Hash) {
            throw "Mac mini package contents failed verification: $($tree.Name). Obtain the complete unmodified 041-91731 package with -DownloadOnly."
        }
    }
    Assert-BetterCampSignature (Join-Path $bootcamp 'setup.exe')
}

function Resolve-BetterCampMacminiPath([string]$Path, [string]$Root) {
    if (-not $Path) {
        $local = Join-Path $Root 'WindowsSupport'
        if (Test-Path -LiteralPath $local -PathType Container) { $Path = $local }
        else { return $null }
    }
    $candidate = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath
    if ((Split-Path $candidate -Leaf) -eq 'BootCamp') { $candidate = Split-Path $candidate -Parent }
    if (-not (Test-Path -LiteralPath (Join-Path $candidate 'BootCamp/BootCamp.xml') -PathType Leaf) -or
        -not (Test-Path -LiteralPath (Join-Path $candidate '$WinPEDriver$') -PathType Container)) {
        throw 'Mac mini requires the complete WindowsSupport folder containing BootCamp and $WinPEDriver$.'
    }
    return $candidate
}

function Get-BetterCampMacminiPackage {
    $info = Get-BetterCampMacminiArchiveInfo
    $cache = Join-Path $env:LOCALAPPDATA ('BetterCamp/downloads/Macmini8,1-' + $info.Product)
    $ready = Join-Path $cache 'WindowsSupport'
    if (Test-Path -LiteralPath $ready -PathType Container) {
        Assert-BetterCampMacminiPackage $ready
        return $ready
    }
    New-Item -ItemType Directory -Path $cache -Force | Out-Null
    # Every extraction has a unique directory; a partial extraction is never reused.
    $work = Join-Path $cache ([guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $work | Out-Null
    try {
        $pkg = Join-Path $cache 'BootCampESD.pkg'
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        if (-not (Test-Path -LiteralPath $pkg -PathType Leaf)) {
            Write-Host "Downloading Mac mini 2018 Apple $($info.Product) (about 548 MB): $($info.Uri)"
            $previousProgress = $ProgressPreference
            try {
                $ProgressPreference = 'SilentlyContinue'
                $partial = Join-Path $work 'BootCampESD.pkg.partial'
                Invoke-WebRequest -Uri $info.Uri -OutFile $partial -UseBasicParsing -TimeoutSec 1800
                Assert-BetterCampDriverHash $partial $info.Sha256 'Mac mini 2018 Apple archive'
                Move-Item -LiteralPath $partial -Destination $pkg
            } finally { $ProgressPreference = $previousProgress }
        }
        Assert-BetterCampDriverHash $pkg $info.Sha256 'Mac mini 2018 Apple archive'
        $tool = Get-BetterCampSevenZip
        $xar = Join-Path $work 'xar'
        $cpio = Join-Path $work 'cpio'
        $image = Join-Path $work 'image'
        $support = Join-Path $work 'WindowsSupport'
        Expand-BetterCampMacminiArchive $tool $pkg $xar @('Payload~')
        Expand-BetterCampMacminiArchive $tool (Find-BetterCampSingleFile $xar 'Payload~') $cpio
        Expand-BetterCampMacminiArchive $tool (Find-BetterCampSingleFile $cpio '*.dmg') $image @('-tDmg')
        Expand-BetterCampMacminiArchive $tool (Find-BetterCampSingleFile $image '*.iso') $support @('BootCamp', '$WinPEDriver$')
        Assert-BetterCampMacminiPackage $support
        Move-Item -LiteralPath $support -Destination $ready
        return $ready
    } finally {
        $resolvedWork = [IO.Path]::GetFullPath($work)
        if ((Split-Path $resolvedWork -Parent) -eq [IO.Path]::GetFullPath($cache) -and
            (Split-Path $resolvedWork -Leaf) -match '^[0-9a-f]{32}$' -and (Test-Path -LiteralPath $resolvedWork)) {
            Remove-Item -LiteralPath $resolvedWork -Recurse -Force
        }
    }
}

function Get-BetterCampMacminiDriverInfs([string]$Path) {
    # WinPE Bluetooth/UHE substitutes must not replace the real Bluetooth radio driver.
    $directories = @('BootCamp/Drivers') + @(
        'AppleSSD64', 'BroadcomWirelessUDM64', 'Aquantia64', 'SerialIO',
        'IntelMEI', 'IntelSST', 'IntelHDGraphics64', 'Dolby'
    ).ForEach({ '$WinPEDriver$/' + $_ })
    $files = @($directories | ForEach-Object {
        Get-ChildItem -LiteralPath (Join-Path $Path $_) -Filter '*.inf' -Recurse -File |
            Where-Object { $_.Name -ne 'autorun.inf' }
    } | Sort-Object FullName)
    if ($files.Count -eq 0) { throw 'No Mac mini driver INF files were found.' }
    return $files
}

function Install-BetterCampMacminiDrivers([string]$Path, $Machine) {
    if ($Machine.Model -ne 'Macmini8,1') { throw 'Mac mini driver installation requires the actual model Macmini8,1.' }
    Assert-BetterCampMacminiPackage $Path
    $files = @(Get-BetterCampMacminiDriverInfs $Path)
    $restartRequired = $false
    foreach ($file in $files) {
        Write-Host "Processing driver: $($file.FullName)"
        $result = Invoke-BetterCampNative (Join-Path $env:SystemRoot 'System32/pnputil.exe') @('/add-driver', $file.FullName, '/install')
        if ($result.ExitCode -notin @(0, 3010)) {
            throw "Driver package failed: $($file.Name) (exit $($result.ExitCode)). Earlier packages may already be installed; see the log."
        }
        if ($result.ExitCode -eq 3010) { $restartRequired = $true }
    }
    return [pscustomobject]@{Count=$files.Count;RestartRequired=$restartRequired}
}

function Show-BetterCampMacminiDiagnosis {
    $errors = @(Get-CimInstance -ClassName Win32_PnPEntity | Where-Object { $_.ConfigManagerErrorCode -ne 0 })
    foreach ($device in $errors) {
        Write-Warning "Device still needs attention: $($device.Name) | Code $($device.ConfigManagerErrorCode) | $($device.PNPDeviceID)"
    }
    if ($errors.Count -eq 0) { Write-Host 'No Plug and Play device errors reported. Verify actual sound, display, USB and network operation after restarting.' }
    else { Write-Warning 'Driver processing is not proof that these devices work. Restart and diagnose remaining errors. This is not an established fix for Bluetooth Code 10.' }
}
