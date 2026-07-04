# deploy.ps1 - Chay sau khi Simply Static export xong
# Usage: .\scripts\deploy.ps1 [message]

$msg = if ($args[0]) { $args[0] } else { "deploy: $(Get-Date -Format 'yyyy-MM-dd HH:mm')" }

Set-Location "e:\taotruyen"

git add -A
git commit -m $msg
$HOOK = "https://api.cloudflare.com/client/v4/workers/builds/deploy_hooks/576470b4-f1e4-43f4-84b3-0bc919007cd4"

if ($LASTEXITCODE -eq 0) {
    git push
    Invoke-RestMethod -Uri $HOOK -Method Post | Out-Null
    Write-Host "Deploy xong! Cloudflare dang build (~30s)..." -ForegroundColor Green
} else {
    Write-Host "Khong co gi thay doi." -ForegroundColor Yellow
    Invoke-RestMethod -Uri $HOOK -Method Post | Out-Null
    Write-Host "Da kich hoat Cloudflare build." -ForegroundColor Cyan
}
