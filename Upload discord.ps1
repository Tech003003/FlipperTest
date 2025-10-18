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

    # Validate that at least one parameter is provided
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
                # Use curl for file uploads (more reliable)
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
