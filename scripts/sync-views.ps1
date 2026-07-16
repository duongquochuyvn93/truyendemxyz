# Đồng bộ lượt xem từ Durable Object về WordPress.
# Worker giữ một batch cho đến khi script xác nhận thành công, nên lỗi WP/mạng
# không làm mất lượt xem. Journal cục bộ giúp tiếp tục một batch dở dang.

$ErrorActionPreference = 'Stop'
$envFile = Join-Path $PSScriptRoot '.env'
$stateFile = Join-Path $PSScriptRoot '.sync-views-state.json'
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
    Write-Host 'Thieu bien trong scripts\.env (WP_URL/WP_USER/WP_APP_PASS/CF_SYNC_SECRET/SITE_URL).' -ForegroundColor Red
    exit 1
}

$cred = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("${WP_USER}:${WP_APP_PASS}"))
$wpHeaders = @{ Authorization = "Basic $cred" }
$syncHeaders = @{ Authorization = "Bearer $SYNC_SECRET" }

function Save-State($state) {
    $state | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $stateFile -Encoding utf8
}

function Get-StoryViews([string]$id) {
    $post = Invoke-RestMethod -Uri "$WP_URL/truyen/$id`?_fields=acf" -Headers $wpHeaders -TimeoutSec 20
    return [int]$post.acf.luot_xem
}

function Set-StoryViews([string]$id, [int]$value) {
    $body = @{ acf = @{ luot_xem = $value } } | ConvertTo-Json
    Invoke-RestMethod -Uri "$WP_URL/truyen/$id" -Method Post -Headers $wpHeaders -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 20 | Out-Null
}

Write-Host 'Dang lay batch view tu Cloudflare...' -ForegroundColor Cyan
try {
    $batch = Invoke-RestMethod -Uri "$SITE_URL/api/views/export" -Method Post -Headers $syncHeaders -TimeoutSec 30
} catch {
    Write-Host "Khong lay duoc batch: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

$ids = @($batch.values.PSObject.Properties.Name)
if ($ids.Count -eq 0) {
    Write-Host 'Khong co view moi nao can dong bo.' -ForegroundColor Yellow
    exit 0
}

if (-not $batch.id) {
    Write-Host 'Batch khong hop le.' -ForegroundColor Red
    exit 1
}

$state = $null
if (Test-Path $stateFile) {
    try { $state = Get-Content -Raw -LiteralPath $stateFile | ConvertFrom-Json } catch {
        Write-Host 'Journal sync bi hong. Khong tu dong dong bo de tranh cong trung.' -ForegroundColor Red
        exit 1
    }
}

if (-not $state) {
    $state = [pscustomobject]@{
        version = 1
        batchId = $batch.id
        stories = [pscustomobject]@{}
    }
    Save-State $state
} elseif ($state.batchId -ne $batch.id) {
    Write-Host 'Journal dang thuoc mot batch khac. Kiem tra scripts\.sync-views-state.json truoc khi chay lai.' -ForegroundColor Red
    exit 1
}

$hadErrors = $false
foreach ($id in $ids) {
    $target = [int]$batch.values.$id
    $entry = $state.stories.PSObject.Properties[$id].Value
    if (-not $entry) {
        $entry = [pscustomobject]@{ applied = 0; prepared = $null }
        $state.stories | Add-Member -NotePropertyName $id -NotePropertyValue $entry
        Save-State $state
    }

    # A prepared operation may have reached WordPress before the local journal
    # was marked complete. Compare the expected value before deciding to retry.
    if ($entry.prepared) {
        try {
            $actual = Get-StoryViews $id
            if ($actual -eq [int]$entry.prepared.expected) {
                $entry.applied = [int]$entry.applied + [int]$entry.prepared.delta
                $entry.prepared = $null
                Save-State $state
            } elseif ($actual -eq [int]$entry.prepared.before) {
                Set-StoryViews $id ([int]$entry.prepared.expected)
                $entry.applied = [int]$entry.applied + [int]$entry.prepared.delta
                $entry.prepared = $null
                Save-State $state
            } else {
                throw "Gia tri WP la $actual, khong khop truoc ($($entry.prepared.before)) hoac sau ($($entry.prepared.expected))."
            }
        } catch {
            $hadErrors = $true
            Write-Host "Loi khoi phuc truyen id=$id : $($_.Exception.Message)" -ForegroundColor Red
            continue
        }
    }

    $remaining = $target - [int]$entry.applied
    if ($remaining -lt 0) {
        $hadErrors = $true
        Write-Host "Journal id=$id vuot qua batch; dung de tranh sai du lieu." -ForegroundColor Red
        continue
    }
    if ($remaining -eq 0) { continue }

    try {
        $current = Get-StoryViews $id
        $entry.prepared = [pscustomobject]@{
            before = $current
            expected = $current + $remaining
            delta = $remaining
        }
        Save-State $state
        Set-StoryViews $id ([int]$entry.prepared.expected)
        $entry.applied = [int]$entry.applied + $remaining
        $entry.prepared = $null
        Save-State $state
        Write-Host "Truyen id=$id : +$remaining" -ForegroundColor Green
    } catch {
        $hadErrors = $true
        Write-Host "Loi khi dong bo truyen id=$id : $($_.Exception.Message)" -ForegroundColor Red
    }
}

if ($hadErrors) {
    Write-Host 'Batch chua duoc xac nhan; chay lai script sau khi sua loi. View khong bi mat.' -ForegroundColor Yellow
    exit 1
}

try {
    $ackBody = @{ batchId = $batch.id } | ConvertTo-Json
    $ack = Invoke-RestMethod -Uri "$SITE_URL/api/views/ack" -Method Post -Headers $syncHeaders -ContentType 'application/json' -Body $ackBody -TimeoutSec 30
    if (-not $ack.acknowledged) { throw 'Cloudflare khong xac nhan batch.' }
    Remove-Item -LiteralPath $stateFile -Force
    Write-Host 'Dong bo va xac nhan batch thanh cong.' -ForegroundColor Green
} catch {
    Write-Host "Da cap nhat WordPress, nhung chua xac nhan batch: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host 'Chay lai script; journal se xac nhan ma khong cong trung.' -ForegroundColor Yellow
    exit 1
}
