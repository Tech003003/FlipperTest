param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath,

    [string]$WebhookUrl = 'https://discord.com/api/webhooks/1194215544342196275/dgFll7XP-mLSiNWHxUoFkSpuKT62Uf5GN-_IlcuB4VknzWky9UwAlPoQRezxzLoIWRJI'
)

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
