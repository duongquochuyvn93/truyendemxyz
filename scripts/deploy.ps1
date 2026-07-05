# deploy.ps1 - Chay sau khi Simply Static export xong
# Usage: .\scripts\deploy.ps1 [message]
# Deploy hook URL doc tu scripts\.env (CF_DEPLOY_HOOK=...) - khong hardcode vao file nay

$msg = if ($args[0]) { $args[0] } else { "deploy: $(Get-Date -Format 'yyyy-MM-dd HH:mm')" }

Set-Location "e:\taotruyen"

$HOOK = $null
$envFile = Join-Path $PSScriptRoot ".env"
if (Test-Path $envFile) {
    foreach ($line in Get-Content $envFile) {
        if ($line -match '^CF_DEPLOY_HOOK=(.+)$') { $HOOK = $Matches[1].Trim() }
    }
}

function Invoke-DeployHook {
    if (-not $HOOK) {
        Write-Host "Thieu CF_DEPLOY_HOOK trong scripts\.env - khong trigger duoc Cloudflare build." -ForegroundColor Yellow
        return
    }
    try {
        Invoke-RestMethod -Uri $HOOK -Method Post | Out-Null
        Write-Host "Da kich hoat Cloudflare build (~60s)..." -ForegroundColor Cyan
    } catch {
        Write-Host "Loi khi goi deploy hook: $($_.Exception.Message)" -ForegroundColor Red
    }
}

git add -A
git commit -m $msg
if ($LASTEXITCODE -eq 0) {
    git push
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Push xong!" -ForegroundColor Green
        Invoke-DeployHook
    } else {
        Write-Host "git push THAT BAI - chua deploy. Kiem tra mang/dang nhap GitHub roi chay lai." -ForegroundColor Red
    }
} else {
    Write-Host "Khong co gi thay doi de commit." -ForegroundColor Yellow
    Invoke-DeployHook
}
