# 源码部署说明

当前 GitHub 仓库只保存源码、启动脚本和配置示例，不是完整安装包。仓库没有提供自动下载模型或创建后台任务的一键安装脚本。

## 运行环境

当前启动脚本按以下环境设计：

- Windows 10 或 Windows 11；
- PowerShell 7，默认位置为 `C:\Program Files\PowerShell\7\pwsh.exe`；
- NVIDIA 显卡和可用的 CUDA 运行环境；
- 项目根目录中的 Python 虚拟环境 `.venv`；
- CUDA 版 `llama-server.exe`；
- Whisper 和 Hy-MT2 模型文件。

建议至少准备 6 GB 显存、16 GB 内存和 10 GB 可用磁盘空间。不同显卡、驱动和模型量化版本的实际占用会有差异。

## 脚本要求的目录

```text
.venv/Scripts/python.exe
models/
├─ huggingface-cache/                 Whisper 模型缓存
└─ hy-mt2/
   ├─ Hy-MT2-1.8B-Q4_K_M.gguf        流畅模式
   └─ Hy-MT2-1.8B-Q6_K.gguf          质量模式
runtime/
└─ llama/
   └─ llama-server.exe
```

Python 依赖记录在项目根目录的 `requirements.txt` 中。启动脚本会把 Hugging Face 缓存位置指向 `models/huggingface-cache`，避免把模型散落到其他目录。

## 后台任务

根目录中的两个 CMD 入口会调用 `launch.ps1`。该脚本要求 Windows 中已经存在名为 `LiveSubtitle-Flow` 的计划任务，并在切换模式时更新其启动参数。

如果计划任务不存在，脚本会提示“缺少 Windows 后台任务”。当前仓库还没有包含创建该任务的安装脚本，因此从源码重新部署时需要自行完成这一项。

## 配置文件

- `config.flow.json`：流畅模式，默认使用较轻的识别参数和 Q4 翻译模型。
- `config.quality.json`：质量模式，默认使用更仔细的识别参数和 Q6 翻译模型。
- `config.json.example`：其他配置方式的空白示例。

常用字段：

- `translation.source_language`：源语言，例如 `English`、`Japanese`、`Korean`；留空表示自动识别。
- `translation.target_language`：目标语言，例如 `简体中文`、`繁体中文` 或 `English`。
- `audio.chunk_duration_seconds`：每次处理的声音长度。越短响应越快，越长上下文越完整。
- `audio.overlap_seconds`：相邻声音片段的重叠时间，用于减少词语在边界处被切断。
- `stt.whisper_local.beam_size`：识别搜索宽度。数值提高后通常更慢，也更占用显卡。

一次只修改一个字段，并在修改后停止、重新启动服务。不要把真实 API Key、令牌或个人设备名称提交到仓库。
