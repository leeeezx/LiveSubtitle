param(
    [ValidateSet("flow", "quality")]
    [string]$Mode = "flow",
    [switch]$NoDialog
)

$ErrorActionPreference = "Stop"
$appRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$taskName = "LiveSubtitle-Flow"
$pwshExe = "C:\Program Files\PowerShell\7\pwsh.exe"
$hostScript = Join-Path $appRoot "service-host.ps1"

function Show-Result([string]$message, [bool]$success) {
    if ($NoDialog) { return }
    Add-Type -AssemblyName PresentationFramework
    $icon = if ($success) { "Information" } else { "Error" }
    [System.Windows.MessageBox]::Show($message, "本地实时字幕", "OK", $icon) | Out-Null
}

try {
    foreach ($required in @($pwshExe, $hostScript, (Join-Path $appRoot "stop.ps1"))) {
        if (-not (Test-Path -LiteralPath $required)) {
            throw "缺少运行文件：$required"
        }
    }

    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if (-not $task) {
        throw "缺少 Windows 后台任务 $taskName，请重新部署后台宿主。"
    }

    # 先关闭可能残留的旧模式，再修改任务动作，确保切换模式时没有端口竞争。
    & (Join-Path $appRoot "stop.ps1") -NoDialog

    $modeArgument = if ($Mode -eq "quality") { "quality" } else { "flow" }
    $action = New-ScheduledTaskAction -Execute $pwshExe -Argument (
        '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -Mode {1}' -f $hostScript, $modeArgument
    )
    Set-ScheduledTask -TaskName $taskName -Action $action | Out-Null
    Start-ScheduledTask -TaskName $taskName

    $ready = $false
    for ($attempt = 0; $attempt -lt 120; $attempt++) {
        $ws = Get-NetTCPConnection -LocalPort 8765 -State Listen -ErrorAction SilentlyContinue
        $llama = Get-NetTCPConnection -LocalPort 8766 -State Listen -ErrorAction SilentlyContinue
        if ($ws -and $llama) {
            $ready = $true
            break
        }
        $state = (Get-ScheduledTask -TaskName $taskName).State
        if ($state -ne "Running" -and $attempt -gt 2) {
            throw "后台任务提前退出，请查看 logs\host.log 和模型日志。"
        }
        Start-Sleep -Seconds 1
    }
    if (-not $ready) { throw "模型或字幕服务加载超时，请查看 logs 文件夹。" }

    $modeName = if ($Mode -eq "quality") { "质量模式" } else { "流畅模式" }
    Show-Result "$modeName 已启动。Chrome 插件将在数秒内自动连接。" $true
} catch {
    Show-Result $_.Exception.Message $false
    if ($NoDialog) { throw }
    exit 1
}
