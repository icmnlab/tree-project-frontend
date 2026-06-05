# 交接備份：複製原始碼與文件到 G:\（不含 node_modules / build / 敏感檔）
# 用法：powershell -ExecutionPolicy Bypass -File scripts\handoff_backup.ps1

param(
    [string]$DestRoot = "G:\TreeAI-Handoff"
)

$ErrorActionPreference = "Stop"
$stamp = Get-Date -Format "yyyyMMdd_HHmm"
$dest = Join-Path $DestRoot $stamp

$frontendRoot = Split-Path $PSScriptRoot -Parent
$backendRoot = Join-Path (Split-Path $frontendRoot -Parent) "backend"

$excludeDirs = @(
    "node_modules", ".dart_tool", "build", ".gradle", "Pods",
    ".venv", "__pycache__", ".git", "dist", "coverage",
    "raw_captures", "checkpoints", ".cache"
)

function Copy-ProjectTree {
    param([string]$Source, [string]$Target, [string]$Label)
    if (-not (Test-Path $Source)) {
        Write-Warning "Skip $Label (missing): $Source"
        return
    }
    Write-Host "Backup $Label -> $Target"
    robocopy $Source $Target /E /XD $excludeDirs /XF "*.jks" "key.properties" "local.properties" "gradle.properties" "apiKeys.json" /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy failed ($Label) exit=$LASTEXITCODE" }
}

New-Item -ItemType Directory -Force -Path $dest | Out-Null
Copy-ProjectTree -Source $frontendRoot -Target (Join-Path $dest "frontend") -Label "frontend"
Copy-ProjectTree -Source $backendRoot -Target (Join-Path $dest "backend") -Label "backend"

# 敏感檔清單（需手動另拷，勿進 Git）
$secretsNote = @"
# 手動備份清單（勿提交 GitHub）

請另存至安全位置（例如 $dest\secrets_manual\）：

- frontend/android/key.properties
- frontend/android/*.jks 或 keystore/
- frontend/android/local.properties（若含本機 SDK 路徑可重建）
- backend/.env（資料庫、JWT、ML_API_KEY 等）
- Tailscale / 圖資中心 SSH 金鑰與部署設定

詳見 docs/HANDOFF_SECRETS_CHECKLIST.md
"@
$secretsNote | Out-File -Encoding utf8 (Join-Path $dest "SECRETS_README.txt")

Write-Host ""
Write-Host "Done: $dest"
Write-Host "Next: git push source; copy secrets per SECRETS_README.txt"
