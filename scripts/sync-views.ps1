# sync-views.ps1 - Dong bo luot xem that (Cloudflare KV) ve luot_xem tren WordPress
# Chay truoc moi lan Simply Static Generate de "Truyen Hot" va so hien thi khop voi
# view that. Doc WP_URL/WP_USER/WP_APP_PASS/CF_SYNC_SECRET/SITE_URL tu scripts\.env
# Usage: .\scripts\sync-views.ps1

$envFile = Join-Path $PSScriptRoot ".env"
$envVars = @{}
if (Test-Path $envFile) {
    foreach ($line in Get-Content $envFile) {
        if ($line -match '^([A-Z_]+)=(.*)$') { $envVars[$Matches[1]] = $Matches[2].Trim() }
    }
}

$WP_URL      = $envVars['WP_URL']
$WP_USER     = $envVars['WP_USER']
$WP_APP_PASS = $envVars['WP_APP_PASS']
$SYNC_SECRET = $envVars['CF_SYNC_SECRET']
$SITE_URL    = $envVars['SITE_URL']

if (-not $WP_URL -or -not $WP_USER -or -not $WP_APP_PASS -or -not $SYNC_SECRET -or -not $SITE_URL) {
    Write-Host "Thieu bien can thiet trong scripts\.env (WP_URL/WP_USER/WP_APP_PASS/CF_SYNC_SECRET/SITE_URL)." -ForegroundColor Red
    exit 1
}

$cred = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("${WP_USER}:${WP_APP_PASS}"))
$wpHeaders = @{ Authorization = "Basic $cred" }

Write-Host "Dang lay view moi tu Cloudflare KV..." -ForegroundColor Cyan
try {
    $deltas = Invoke-RestMethod -Uri "$SITE_URL/api/views/export?secret=$SYNC_SECRET" -TimeoutSec 30
} catch {
    Write-Host "Loi khi goi export endpoint: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

$ids = $deltas.PSObject.Properties.Name
if (-not $ids -or $ids.Count -eq 0) {
    Write-Host "Khong co view moi nao can dong bo." -ForegroundColor Yellow
    exit 0
}

foreach ($id in $ids) {
    $delta = [int]$deltas.$id
    try {
        $post = Invoke-RestMethod -Uri "$WP_URL/truyen/$id`?_fields=acf" -Headers $wpHeaders -TimeoutSec 20
        $current = [int]$post.acf.luot_xem
        $new = $current + $delta

        $body = @{ acf = @{ luot_xem = $new } } | ConvertTo-Json
        $bytes = [Text.Encoding]::UTF8.GetBytes($body)
        Invoke-RestMethod -Uri "$WP_URL/truyen/$id" -Method Post -Headers $wpHeaders -ContentType "application/json; charset=utf-8" -Body $bytes | Out-Null

        Write-Host "Truyen id=$id : $current + $delta = $new" -ForegroundColor Green
    } catch {
        Write-Host "Loi khi dong bo truyen id=$id : $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "Dong bo xong." -ForegroundColor Cyan
