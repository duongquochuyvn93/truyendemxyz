# deploy.ps1 - Chay sau khi Simply Static export xong
# Usage: .\scripts\deploy.ps1 [message]

$msg = if ($args[0]) { $args[0] } else { "deploy: $(Get-Date -Format 'yyyy-MM-dd HH:mm')" }

Set-Location "e:\taotruyen"

git add -A
git commit -m $msg
if ($LASTEXITCODE -eq 0) {
    git push
    Write-Host "Deploy xong! Cloudflare dang build (~30s)..." -ForegroundColor Green
} else {
    Write-Host "Khong co gi thay doi." -ForegroundColor Yellow
}
