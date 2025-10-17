<#
Fixed installer script: TLS enforced, syntax error fixed, better diagnostics for asset selection,
and an elevation check. Inspect before running. Requires Administrator to install and write to ProgramData.
#>

# Self-elevation snippet 
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host 'Not elevated — restarting as Administrator...'
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell.exe'
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"" + $MyInvocation.MyCommand.Definition + "`""
    $psi.Verb = 'runas'
    try { [System.Diagnostics.Process]::Start($psi) | Out-Null; exit } catch { throw 'Elevation canceled or failed.' }
}

[CmdletBinding()]
param(
    [Parameter()] [string] $GithubApiUrl = 'https://api.github.com/repos/rustdesk/rustdesk/releases/latest',
    # more permissive pattern: match common windows/x64 exe names
    [Parameter()] [string] $AssetNamePattern = '.*(windows|win).*?(x86_64|x64|amd64).*?\.exe$'
)

# where credentials will be saved (requires admin)
$CredentialOutputPath = 'C:\ProgramData\RustDesk\rustdesk-credentials.txt'

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Ensure elevated
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script must be run elevated (Run PowerShell as Administrator)."
    exit 1
}

# Force TLS1.2 for GitHub
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Get-LatestRustDeskInstallerUrl {
    param(
        [Parameter(Mandatory)] [string] $ApiUrl,
        [Parameter(Mandatory)] [string] $NamePattern
    )
    Write-Verbose "Querying GitHub release metadata from $ApiUrl"
    $release = Invoke-RestMethod -Uri $ApiUrl -Headers @{ 'User-Agent' = 'PowerShell' } -ErrorAction Stop

    if (-not $release.assets) {
        throw 'Unable to locate any downloadable assets in the latest RustDesk release metadata.'
    }

    # show assets for debugging
    Write-Verbose "Available assets:"
    foreach ($a in $release.assets) { Write-Verbose (" - {0}" -f $a.name) }

    $asset = $release.assets | Where-Object { $_.name -match $NamePattern } | Select-Object -First 1
    if (-not $asset) {
        # fallback: pick the first .exe asset and inform user
        $exeAsset = $release.assets | Where-Object { $_.name -match '\.exe$' } | Select-Object -First 1
        if ($exeAsset) {
            Write-Warning "No asset matched pattern '$NamePattern' — falling back to first .exe asset: $($exeAsset.name)"
            return $exeAsset.browser_download_url
        }
        throw "Could not find a release asset matching pattern '$NamePattern' and no .exe assets found."
    }

    return $asset.browser_download_url
}

function Invoke-SilentInstaller {
    param([Parameter(Mandatory)] [string] $InstallerPath)
    Write-Verbose "Starting silent installation using $InstallerPath"
    $arguments = @('/verysilent', '/norestart')  # may need change depending on installer
    $process = Start-Process -FilePath $InstallerPath -ArgumentList $arguments -PassThru -Wait
    if ($process.ExitCode -ne 0) {
        throw "RustDesk installer exited with code $($process.ExitCode)."
    }
}

function Get-RustDeskExecutablePath {
    $candidatePaths = @(
        (Join-Path -Path ${env:ProgramFiles} -ChildPath 'RustDesk\rustdesk.exe'),
        (Join-Path -Path ${env:ProgramFiles(x86)} -ChildPath 'RustDesk\rustdesk.exe')
    )

    foreach ($path in $candidatePaths) {
        if ($path -and (Test-Path -Path $path)) {
            return $path
        }
    }

    throw 'RustDesk executable not found after installation.'
}

function Ensure-RustDeskServiceReady {
    param([Parameter(Mandatory)] [string] $ExecutablePath)

    # Try to find service by display name or common names; if not present, attempt to run exe to generate config
    $service = Get-Service -Name 'RustDesk' -ErrorAction SilentlyContinue
    if (-not $service) {
        Write-Verbose 'RustDesk service not found; attempting to start rustdesk.exe once to allow it to register or generate config.'
        Start-Process -FilePath $ExecutablePath -ArgumentList '--start' -NoNewWindow
        Start-Sleep -Seconds 5
        $service = Get-Service -Name 'RustDesk' -ErrorAction SilentlyContinue
    }

    if ($service -and $service.Status -ne 'Running') {
        Write-Verbose 'Starting RustDesk service.'
        Start-Service -InputObject $service
        $service.WaitForStatus('Running', (New-TimeSpan -Minutes 1))
    }
}

function Get-RustDeskConfigPath {
    # FIXED array syntax here
    $searchRoots = @(
        (Join-Path -Path $env:APPDATA -ChildPath 'RustDesk'),
        (Join-Path -Path $env:PROGRAMDATA -ChildPath 'RustDesk')
    )

    $deadline = (Get-Date).AddMinutes(2)
    while ((Get-Date) -lt $deadline) {
        foreach ($root in $searchRoots) {
            if (-not $root) { continue }
            $candidate = Join-Path -Path $root -ChildPath 'config\RustDesk.toml'
            if (Test-Path -Path $candidate) {
                Write-Verbose "Found RustDesk configuration at $candidate"
                return $candidate
            }
        }
        Start-Sleep -Seconds 5
    }

    throw 'Timed out while waiting for RustDesk to generate its configuration file.'
}

function Read-RustDeskCredentials {
    param([Parameter(Mandatory)] [string] $ConfigPath)

    $id = $null
    $password = $null
    foreach ($line in Get-Content -Path $ConfigPath) {
        if (-not $id -and $line -match '^\s*id\s*=\s*"([^"]+)"') { $id = $Matches[1] }
        elseif (-not $password -and $line -match '^\s*password\s*=\s*"([^"]+)"') { $password = $Matches[1] }
        if ($id -and $password) { break }
    }

    if (-not $id) { throw 'RustDesk ID could not be located in the configuration file.' }
    if (-not $password) { throw 'RustDesk password could not be located in the configuration file.' }

    [pscustomobject]@{ Id = $id; Password = $password }
}

# MAIN
Write-Host 'Downloading latest RustDesk installer...'
$installerUrl = Get-LatestRustDeskInstallerUrl -ApiUrl $GithubApiUrl -NamePattern $AssetNamePattern
Write-Host "Installer URL: $installerUrl"

# Save installer to user's Downloads folder instead of TEMP
$installerPath = Join-Path $env:USERPROFILE "Downloads\rustdesk_installer.exe"

Write-Host "Downloading RustDesk installer to $installerPath ..."
Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -UseBasicParsing -ErrorAction Stop
Write-Host "Download complete. Installing RustDesk from $installerPath ..."

Invoke-SilentInstaller -InstallerPath $installerPath


$rustDeskExe = Get-RustDeskExecutablePath
Ensure-RustDeskServiceReady -ExecutablePath $rustDeskExe

Write-Host 'Waiting for RustDesk to generate credentials...'
$configPath = Get-RustDeskConfigPath
$credentials = Read-RustDeskCredentials -ConfigPath $configPath

$credentialLines = @(
    "RustDesk ID: $($credentials.Id)",
    "RustDesk Password: $($credentials.Password)",
    "Saved from configuration: $configPath",
    "Timestamp (UTC): $([DateTime]::UtcNow.ToString('u'))"
)

# ensure directory exists
$credentialDirectory = Split-Path -Path $CredentialOutputPath -Parent
if (-not (Test-Path -Path $credentialDirectory)) {
    New-Item -ItemType Directory -Force -Path $credentialDirectory | Out-Null
}

$credentialLines | Set-Content -Path $CredentialOutputPath -Encoding UTF8
Write-Host "RustDesk installation complete. Credentials saved to '$CredentialOutputPath'."

# (Keeping installer file in Downloads for later)
Write-Host "Installer kept at $installerPath"
