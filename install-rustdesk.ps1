<#
.SYNOPSIS
    Downloads and installs the latest RustDesk release for Windows, then captures the generated ID and password.
.DESCRIPTION
    The script fetches the most recent RustDesk release from GitHub, performs a silent install,
    and waits for RustDesk to generate its configuration. Once the ID and password are available,
    they are written to a text file for later reference.
    Administrator privileges are required for installation.
.PARAMETER GithubApiUrl
    Override for the GitHub API endpoint used to obtain the latest RustDesk release metadata.
.PARAMETER AssetNamePattern
    Regex pattern used to select the Windows installer asset from the GitHub release metadata.
.EXAMPLE
    PS> .\install-rustdesk.ps1

    Installs RustDesk using the latest GitHub release and saves the generated ID/password to
    C:\ProgramData\RustDesk\rustdesk-credentials.txt.
#>
[CmdletBinding()]
param(
    [Parameter()] [string] $GithubApiUrl = 'https://api.github.com/repos/rustdesk/rustdesk/releases/latest',
    [Parameter()] [string] $AssetNamePattern = 'windows.*x86_64.*\.exe$'
)

$CredentialOutputPath = 'C:\ProgramData\RustDesk\rustdesk-credentials.txt'

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-LatestRustDeskInstallerUrl {
    param(
        [Parameter(Mandatory)] [string] $ApiUrl,
        [Parameter(Mandatory)] [string] $NamePattern
    )

    Write-Verbose "Querying GitHub release metadata from $ApiUrl"
    $release = Invoke-RestMethod -Uri $ApiUrl -Headers @{ 'User-Agent' = 'PowerShell' }
    if (-not $release.assets) {
        throw 'Unable to locate any downloadable assets in the latest RustDesk release metadata.'
    }

    $asset = $release.assets | Where-Object { $_.name -match $NamePattern } | Select-Object -First 1
    if (-not $asset) {
        throw "Could not find a release asset matching pattern '$NamePattern'."
    }

    return $asset.browser_download_url
}

function Invoke-SilentInstaller {
    param(
        [Parameter(Mandatory)] [string] $InstallerPath
    )

    Write-Verbose "Starting silent installation using $InstallerPath"
    $arguments = @('/verysilent', '/norestart')
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
    param(
        [Parameter(Mandatory)] [string] $ExecutablePath
    )

    $service = Get-Service -Name 'RustDesk' -ErrorAction SilentlyContinue
    if (-not $service) {
        Write-Verbose 'Registering RustDesk service.'
        Start-Process -FilePath $ExecutablePath -ArgumentList '--register-service' -Wait
        $service = Get-Service -Name 'RustDesk' -ErrorAction Stop
    }

    if ($service.Status -ne 'Running') {
        Write-Verbose 'Starting RustDesk service.'
        Start-Service -InputObject $service
        $service.WaitForStatus('Running', (New-TimeSpan -Minutes 1))
    }
}

function Get-RustDeskConfigPath {
    $searchRoots = @(
        Join-Path -Path $env:APPDATA -ChildPath 'RustDesk'),
        Join-Path -Path $env:PROGRAMDATA -ChildPath 'RustDesk'
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
    param(
        [Parameter(Mandatory)] [string] $ConfigPath
    )

    $id = $null
    $password = $null
    foreach ($line in Get-Content -Path $ConfigPath) {
        if (-not $id -and $line -match '^\s*id\s*=\s*"([^"]+)"') {
            $id = $Matches[1]
        }
        elseif (-not $password -and $line -match '^\s*password\s*=\s*"([^"]+)"') {
            $password = $Matches[1]
        }

        if ($id -and $password) {
            break
        }
    }

    if (-not $id) { throw 'RustDesk ID could not be located in the configuration file.' }
    if (-not $password) { throw 'RustDesk password could not be located in the configuration file.' }

    [pscustomobject]@{
        Id       = $id
        Password = $password
    }
}

Write-Host 'Downloading latest RustDesk installer...'
$installerUrl = Get-LatestRustDeskInstallerUrl -ApiUrl $GithubApiUrl -NamePattern $AssetNamePattern

$tempInstaller = New-TemporaryFile
$installerPath = [System.IO.Path]::ChangeExtension($tempInstaller.FullName, '.exe')
Move-Item -Path $tempInstaller.FullName -Destination $installerPath -Force

Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -UseBasicParsing

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

if (-not [System.IO.Path]::IsPathRooted($CredentialOutputPath)) {
    $CredentialOutputPath = Join-Path -Path (Get-Location).Path -ChildPath $CredentialOutputPath
}

$credentialDirectory = Split-Path -Path $CredentialOutputPath -Parent
if (-not $credentialDirectory) {
    $credentialDirectory = (Get-Location).Path
    $CredentialOutputPath = Join-Path -Path $credentialDirectory -ChildPath (Split-Path -Path $CredentialOutputPath -Leaf)
}

if (-not (Test-Path -Path $credentialDirectory)) {
    $null = New-Item -ItemType Directory -Force -Path $credentialDirectory
}

$credentialLines | Set-Content -Path $CredentialOutputPath -Encoding UTF8

Write-Host "RustDesk installation complete. Credentials saved to '$CredentialOutputPath'."

try {
    Remove-Item -Path $installerPath -Force
} catch {
    Write-Warning "Unable to remove temporary installer: $($_.Exception.Message)"
}
