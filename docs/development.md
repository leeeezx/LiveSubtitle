# 开发与修改说明

## 修改前

1. 分别运行一次流畅模式和质量模式，确认原始版本能够启动、显示字幕并正常停止。
2. 在自己的分支中工作，不要直接修改正在使用的部署。
3. 一次只处理一个功能点，便于判断问题来自哪里。

## 从哪里开始

- 字幕位置、字体、颜色和原文显示：`extension/content.js`、`extension/styles.css`、`extension/popup.*`
- 扩展连接和自动重连：`extension/background.js`
- 声音采集：`service/audio_capture.py`
- 声音分段、重复字幕处理和主流程：`service/pipeline.py`
- 本机 Whisper 识别：`service/engines/stt/whisper_local.py`
- Hy-MT2 翻译提示语和输出清理：`service/engines/translation/llama_cpp.py`
- 启动、停止和模式切换：`launch.ps1`、`start.ps1`、`stop.ps1`、`service-host.ps1`

## 完成检查

每次修改后至少完成下面这条完整路径：

`启动 → 播放视频 → 确认字幕出现 → 停止 → 再次启动 → 再确认字幕出现`

流畅模式和质量模式都应测试。修改 PowerShell 或 CMD 文件后，还需要在 Windows 中实际双击入口测试，不能只在终端中检查语法。

## 仓库约定

- 不要提交 `models/`、`runtime/`、`.venv/`、`logs/` 和 `backups/`。
- 不要提交真实 API Key、令牌或个人设备名称。
- 字幕服务使用端口 `8765`，本机翻译模型使用端口 `8766`。
- 启动和停止逻辑必须配套修改。能启动但不能干净停止，不算完成。
- 中文脚本继续使用 PowerShell 7，避免旧版 Windows PowerShell 的编码问题。
