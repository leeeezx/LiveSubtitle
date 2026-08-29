param(
    [ValidateSet("flow", "quality")]
    [string]$Mode = "flow",
    [switch]$NoDialog
)

$ErrorActionPreference = "Stop"
$appRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$runtimeDir = Join-Path $appRoot "runtime"
$logDir = Join-Path $appRoot "logs"
$pidDir = Join-Path $runtimeDir "pids"
$modelDir = Join-Path $appRoot "models"

New-Item -ItemType Directory -Force -Path $logDir, $pidDir | Out-Null

function Stop-ManagedProcess([string]$pidFile) {
    if (-not (Test-Path -LiteralPath $pidFile)) { return }
    $savedPid = [int](Get-Content -LiteralPath $pidFile -Raw)
    $process = Get-Process -Id $savedPid -ErrorAction SilentlyContinue
    if ($process -and $process.Path -and $process.Path.StartsWith($appRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        Stop-Process -Id $savedPid -Force
    }
    Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
}

function Show-Result([string]$message, [bool]$success) {
    if ($NoDialog) { return }
    Add-Type -AssemblyName PresentationFramework
    $icon = if ($success) { "Information" } else { "Error" }
    [System.Windows.MessageBox]::Show($message, "本地实时字幕", "OK", $icon) | Out-Null
}

try {
    Stop-ManagedProcess (Join-Path $pidDir "subtitle.pid")
    $serverPidFile = Join-Path $pidDir "subtitle-server.pid"
    if (Test-Path -LiteralPath $serverPidFile) {
        $serverPid = [int](Get-Content -LiteralPath $serverPidFile -Raw)
        $listener = Get-NetTCPConnection -LocalPort 8765 -State Listen -ErrorAction SilentlyContinue
        if ($listener -and $listener.OwningProcess -eq $serverPid) {
            Stop-Process -Id $serverPid -Force -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath $serverPidFile -Force -ErrorAction SilentlyContinue
    }
    Stop-ManagedProcess (Join-Path $pidDir "llama.pid")

    $env:HF_HOME = Join-Path $modelDir "huggingface-cache"
    $env:HF_HUB_CACHE = Join-Path $env:HF_HOME "hub"
    $env:HF_HUB_DISABLE_SYMLINKS_WARNING = "1"
    $env:PYTHONUNBUFFERED = "1"
    $env:LIVE_SUBTITLE_CONFIG = if ($Mode -eq "quality") {
        Join-Path $appRoot "config.quality.json"
    } else {
        Join-Path $appRoot "config.flow.json"
    }

    $llamaExe = Join-Path $runtimeDir "llama\llama-server.exe"
    $pythonExe = Join-Path $appRoot ".venv\Scripts\python.exe"
    $modelFile = if ($Mode -eq "quality") {
        Join-Path $modelDir "hy-mt2\Hy-MT2-1.8B-Q6_K.gguf"
    } else {
        Join-Path $modelDir "hy-mt2\Hy-MT2-1.8B-Q4_K_M.gguf"
    }

    foreach ($required in @($llamaExe, $pythonExe, $modelFile)) {
        if (-not (Test-Path -LiteralPath $required)) { throw "缺少运行文件：$required" }
    }

    $llamaArgs = @(
        "--model", $modelFile,
        "--host", "127.0.0.1",
        "--port", "8766",
        "--ctx-size", "2048",
        "--parallel", "1",
        "--n-gpu-layers", "99",
        "--api-key", "live-subtitle-local-6f87d3a2",
        "--jinja",
        "--no-webui"
    )
    $llamaProcess = Start-Process -FilePath $llamaExe -ArgumentList $llamaArgs `
        -WorkingDirectory $appRoot -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput (Join-Path $logDir "llama.out.log") `
        -RedirectStandardError (Join-Path $logDir "llama.err.log")
    Set-Content -LiteralPath (Join-Path $pidDir "llama.pid") -Value $llamaProcess.Id

    $ready = $false
    for ($attempt = 0; $attempt -lt 120; $attempt++) {
        if ($llamaProcess.HasExited) { throw "翻译模型启动失败，请查看 logs\llama.err.log" }
        try {
            $response = Invoke-WebRequest -Uri "http://127.0.0.1:8766/health" -UseBasicParsing -TimeoutSec 2
            if ($response.StatusCode -eq 200) { $ready = $true; break }
        } catch {}
        Start-Sleep -Milliseconds 1000
    }
    if (-not $ready) { throw "翻译模型加载超时，请查看 logs 文件夹" }

    $subtitleProcess = Start-Process -FilePath $pythonExe -ArgumentList "run.py" `
        -WorkingDirectory $appRoot -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput (Join-Path $logDir "subtitle.out.log") `
        -RedirectStandardError (Join-Path $logDir "subtitle.err.log")
    Set-Content -LiteralPath (Join-Path $pidDir "subtitle.pid") -Value $subtitleProcess.Id

    $subtitleReady = $false
    for ($attempt = 0; $attempt -lt 120; $attempt++) {
        if ($subtitleProcess.HasExited) { throw "字幕服务启动失败，请查看 logs\subtitle.err.log" }
        $listener = Get-NetTCPConnection -LocalPort 8765 -State Listen -ErrorAction SilentlyContinue
        if ($listener) {
            Set-Content -LiteralPath (Join-Path $pidDir "subtitle-server.pid") -Value $listener.OwningProcess
            $subtitleReady = $true
            break
        }
        Start-Sleep -Milliseconds 1000
    }
    if (-not $subtitleReady) { throw "语音模型加载超时，请查看 logs 文件夹" }

    $modeName = if ($Mode -eq "quality") { "质量模式" } else { "流畅模式" }
    Show-Result "$modeName 已启动。请在 Chrome 中播放视频；扩展图标显示绿色即连接成功。" $true
} catch {
    Show-Result $_.Exception.Message $false
    if ($NoDialog) { throw }
    exit 1
}
