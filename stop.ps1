param([switch]$NoDialog)

$ErrorActionPreference = "SilentlyContinue"
$appRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$pidDir = Join-Path $appRoot "runtime\pids"
$taskName = "LiveSubtitle-Flow"

# 后台任务持有整个字幕进程树，必须先停止它，否则子进程可能继续存活。
$task = Get-ScheduledTask -TaskName $taskName
if ($task -and $task.State -eq "Running") {
    Stop-ScheduledTask -TaskName $taskName
    Start-Sleep -Milliseconds 800
}

# 先处理实际监听 8765 的子进程。它可能显示为系统 Python 路径，
# 因此以启动脚本记录的 PID + 端口归属双重校验，而不是只检查可执行文件路径。
$serverPidFile = Join-Path $pidDir "subtitle-server.pid"
if (Test-Path -LiteralPath $serverPidFile) {
    $serverPid = [int](Get-Content -LiteralPath $serverPidFile -Raw)
    $listener = Get-NetTCPConnection -LocalPort 8765 -State Listen -ErrorAction SilentlyContinue
    if ($listener -and $listener.OwningProcess -eq $serverPid) {
        Stop-Process -Id $serverPid -Force
    }
    Remove-Item -LiteralPath $serverPidFile -Force
}

# 处理由本应用直接启动的 Whisper 包装进程和 llama.cpp。
foreach ($name in @("subtitle.pid", "llama.pid")) {
    $pidFile = Join-Path $pidDir $name
    if (-not (Test-Path -LiteralPath $pidFile)) { continue }
    $savedPid = [int](Get-Content -LiteralPath $pidFile -Raw)
    $process = Get-Process -Id $savedPid
    if ($process -and $process.Path -and
        $process.Path.StartsWith($appRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        Stop-Process -Id $savedPid -Force
    }
    Remove-Item -LiteralPath $pidFile -Force
}

Start-Sleep -Milliseconds 500
$remaining = Get-NetTCPConnection -LocalPort 8765, 8766 -State Listen -ErrorAction SilentlyContinue
$success = -not $remaining
$message = if ($success) {
    "字幕服务、语音识别和翻译模型均已停止。"
} else {
    "停止不完整：端口 {0} 仍被占用，请查看 logs 文件夹。" -f (($remaining.LocalPort | Sort-Object -Unique) -join ", ")
}

if (-not $NoDialog) {
    Add-Type -AssemblyName PresentationFramework
    $icon = if ($success) { "Information" } else { "Error" }
    [System.Windows.MessageBox]::Show($message, "本地实时字幕", "OK", $icon) | Out-Null
}

if (-not $success) { exit 1 }
