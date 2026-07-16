# Chạy sau khi Simply Static export xong.
# Chỉ tự stage artifact website; file lạ sẽ chặn deploy thay vì bị commit nhầm.

$ErrorActionPreference = 'Stop'
$msg = if ($args[0]) { $args[0] } else { "deploy: $(Get-Date -Format 'yyyy-MM-dd HH:mm')" }
$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

$blockedPattern = '(^|/)(\.wrangler|\.codex|\.claude|\.agents)(/|$)|(^|/)[^/]*\.(env|pem|key)$|(^|/)(id_rsa|AGENTS\.md)$|\.sqlite(-wal|-shm)?$|\.map$'
$artifactPattern = '\.(html|css|js|json|png|jpe?g|gif|webp|svg|woff2?|ttf|eot|ico|xml|gz)$'
$untracked = @(git ls-files --others --exclude-standard)
$blocked = @($untracked | Where-Object { ($_ -replace '\\','/') -match $blockedPattern })
$unexpected = @($untracked | Where-Object { (($_ -replace '\\','/') -notmatch $artifactPattern) -or (($_ -replace '\\','/') -match $blockedPattern) })
if ($unexpected.Count -gt 0) {
    Write-Host 'Dung deploy: chi duoc tu dong them static artifact; file sau can xu ly thu cong:' -ForegroundColor Red
    $unexpected | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    exit 1
}

$HOOK = $null
$envFile = Join-Path $PSScriptRoot '.env'
if (Test-Path $envFile) {
    foreach ($line in Get-Content $envFile) {
        if ($line -match '^CF_DEPLOY_HOOK=(.+)$') { $HOOK = $Matches[1].Trim() }
    }
}

function Invoke-DeployHook {
    if (-not $HOOK) {
        Write-Host 'Khong co CF_DEPLOY_HOOK; bo qua deploy hook.' -ForegroundColor Yellow
        return
    }
    Invoke-RestMethod -Uri $HOOK -Method Post -TimeoutSec 30 | Out-Null
    Write-Host 'Da kich hoat Cloudflare build.' -ForegroundColor Cyan
}

git add -A
$stagedBlocked = @(git diff --cached --name-only | Where-Object { ($_ -replace '\\','/') -match $blockedPattern })
if ($stagedBlocked.Count -gt 0) {
    git restore --staged -- $stagedBlocked
    Write-Host 'Dung deploy: file nhay cam da bi stage va da duoc unstage.' -ForegroundColor Red
    $stagedBlocked | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    exit 1
}

git diff --cached --quiet
if ($LASTEXITCODE -eq 0) {
    Write-Host 'Khong co thay doi de commit.' -ForegroundColor Yellow
    Invoke-DeployHook
    exit 0
}

git commit -m $msg
git push
Invoke-DeployHook
Write-Host 'Push xong.' -ForegroundColor Green
