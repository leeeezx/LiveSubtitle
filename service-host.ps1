param(
    [ValidateSet("flow", "quality")]
    [string]$Mode = "flow"
)

$ErrorActionPreference = "Stop"
$appRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$pidDir = Join-Path $appRoot "runtime\pids"
$hostLog = Join-Path $appRoot "logs\host.log"

try {
    # 由 Windows 后台任务持有本脚本，避免字幕进程依赖 Chrome 或 Codex 的生命周期。
    & (Join-Path $appRoot "start.ps1") -Mode $Mode -NoDialog

    while ($true) {
        $allRunning = $true
        foreach ($name in @("llama.pid", "subtitle.pid")) {
            $pidFile = Join-Path $pidDir $name
            if (-not (Test-Path -LiteralPath $pidFile)) {
                $allRunning = $false
                break
            }
            $savedPid = [int](Get-Content -LiteralPath $pidFile -Raw)
            if (-not (Get-Process -Id $savedPid -ErrorAction SilentlyContinue)) {
                $allRunning = $false
                break
            }
        }

        if (-not $allRunning) {
            Add-Content -LiteralPath $hostLog -Encoding utf8 -Value (
                "{0} 字幕子进程已停止，后台宿主退出。" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            )
            exit 1
        }
        Start-Sleep -Seconds 10
    }
} catch {
    Add-Content -LiteralPath $hostLog -Encoding utf8 -Value (
        "{0} 后台宿主启动失败：{1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $_.Exception.Message
    )
    exit 1
}
