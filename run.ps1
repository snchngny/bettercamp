#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$BootCampPath,
    [switch]$Diagnose,
    [switch]$DownloadOnly,
    [string]$LauncherSourceDirectory
)

$ErrorActionPreference = 'Stop'
$launcherBase = Join-Path $env:LOCALAPPDATA 'BetterCamp/launcher'
$launcherRoot = Join-Path $launcherBase ([guid]::NewGuid().ToString('N'))
$commonDirectory = Join-Path $launcherRoot 'scripts'

try {
    New-Item -ItemType Directory -Path $commonDirectory -Force | Out-Null
    $files = @(
        @{ Name = 'bettercamp.ps1'; Destination = (Join-Path $launcherRoot 'bettercamp.ps1') },
        @{ Name = 'scripts/BetterCamp.Common.ps1'; Destination = (Join-Path $commonDirectory 'BetterCamp.Common.ps1') }
    )

    foreach ($file in $files) {
        if ($LauncherSourceDirectory) {
            Copy-Item -LiteralPath (Join-Path $LauncherSourceDirectory $file.Name) -Destination $file.Destination
        } else {
            $uri = 'https://raw.githubusercontent.com/snchngny/bettercamp/main/' + $file.Name
            Invoke-WebRequest -Uri $uri -OutFile $file.Destination -UseBasicParsing
        }
    }

    function ConvertTo-Literal([string]$Value) { return "'" + $Value.Replace("'", "''") + "'" }
    $command = '& ' + (ConvertTo-Literal (Join-Path $launcherRoot 'bettercamp.ps1'))
    if ($BootCampPath) { $command += ' -BootCampPath ' + (ConvertTo-Literal $BootCampPath) }
    if ($Diagnose) { $command += ' -Diagnose' }
    if ($DownloadOnly) { $command += ' -DownloadOnly' }
    $command += '; exit $LASTEXITCODE'
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))

    $process = Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encoded) -Wait -PassThru
    if ($process.ExitCode -ne 0) { throw "BetterCamp stopped with exit code $($process.ExitCode)." }
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
