# Qwen3-TTS Studio

**本地运行 Qwen3-TTS 的轻量方案：Q8 GGUF + 原生 C++ 推理 + 一个网页前端 + OpenAI 兼容接口。**
不装 PyTorch，不装官方 Python 包，也不用 Gradio。

A lightweight way to run Qwen3-TTS locally on Windows: Q8 GGUF weights, native C++ inference
([qwentts.cpp](https://github.com/ServeurpersoCom/qwentts.cpp)), a single-file web UI and an
OpenAI-compatible HTTP API that both humans and AI agents can drive. English summary below.

---

## 为什么做这个

官方 Qwen3-TTS 需要完整的 PyTorch 环境，安装包好几个 GB，还用 BF16/FP32 跑，显存占用高。
社区的 GGUF 方案大多只提供命令行，或者只是演示。这个仓库把能日常用的几块拼在一起：

| | 官方 Python 版 | 本项目 |
|---|---|---|
| 运行环境 | Python + PyTorch + CUDA 版 torch | 一个 `tts-server.exe`（几十 MB） |
| 权重 | BF16 safetensors | Q8_0 GGUF（1.7B talker 约 2 GB） |
| 前端 | Gradio | 单个 HTML 文件，双击就能打开 |
| 给程序调用 | 需要自己写 | 内置 OpenAI 兼容 `/v1/audio/speech` |

三种模式都支持：

- **声音克隆**（Base）：上传 3~20 秒参考音频即可克隆音色，附上原文效果更好
- **预设音色**（CustomVoice）：9 个内置说话人，可以加语气/风格指令（含北京话、四川话说话人）
- **声音设计**（VoiceDesign）：用一句话描述想要的声音

## 目录结构

```
qwen3-tts-studio/
├─ web/index.html             前端（直接用浏览器打开）
├─ scripts/build.cmd          拉取并编译 qwentts.cpp（CUDA），输出到 bin\
├─ scripts/start.cmd          不依赖其它启动器，直接起服务 + 打开前端
├─ scripts/register-voices.ps1  把声音库里的 wav 注册到服务
├─ bin/                       编译产物（build.cmd 生成，不进仓库）
├─ qwentts.cpp/               上游源码（build.cmd 拉取，不进仓库）
└─ models/                    放模型（可换位置，不进仓库）
```

## 准备

1. **Visual Studio Build Tools**，勾选「使用 C++ 的桌面开发」（自带 CMake 和 Ninja）
   ```
   winget install Microsoft.VisualStudio.BuildTools --override "--quiet --wait --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
   ```
2. **CUDA Toolkit**（12.x 或 13.x）和 **git**
3. **模型**：从 [Serveurperso/Qwen3-TTS-GGUF](https://huggingface.co/Serveurperso/Qwen3-TTS-GGUF) 下载，放进 `models\`：
   - `qwen-tokenizer-12hz-*.gguf`（必需，三种模式共用）
   - `qwen-talker-1.7b-base-Q8_0.gguf`（声音克隆）
   - `qwen-talker-1.7b-customvoice-Q8_0.gguf`（预设音色）
   - `qwen-talker-1.7b-voicedesign-Q8_0.gguf`（声音设计）

   只用某一种模式的话，下载对应的 talker 就行。

## 编译

```
scripts\build.cmd
```

默认只为本机显卡编译（`CUDA_ARCH=native`，快很多）。要发给别人用，先 `set CUDA_ARCH=`（留空）再编译，
这样会用上游的多架构列表。以后更新上游源码用 `scripts\build.cmd update`。

## 启动

```
scripts\start.cmd               三种模式全开（1.7B Q8 合计约 10 GB 显存）
scripts\start.cmd base          只开声音克隆（约 3 GB）
scripts\start.cmd customvoice   只开预设音色
scripts\start.cmd voicedesign   只开声音设计
scripts\start.cmd all D:\tts-models   指定模型目录
```

服务窗口最小化运行，关掉窗口就停止服务。前端会自动打开，顶部会显示每个端口的状态。

| 模式 | 端口 |
|---|---|
| 声音克隆（base） | 8090 |
| 预设音色（customvoice） | 8091 |
| 声音设计（voicedesign） | 8092 |

默认只监听 `127.0.0.1`；要开放给局域网，先 `set TTS_HOST=0.0.0.0`。

## 声音库

在服务端注册的声音只存在内存里，重启后就没了。要长期保存，在模型目录下建 `voices\`：

```
models\voices\
  narrator.wav     参考音频（任意采样率的 WAV）
  narrator.txt     可选：音频里说的原文（UTF-8）。有原文时用 ICL 克隆，相似度更高
```

`start.cmd` 会在 base 服务就绪后自动注册这些声音，之后用 `"voice": "narrator"` 就能调用。
前端里也可以临时注册：支持 wav、mp3、m4a 等格式，浏览器会先转成 24 kHz 单声道 WAV 再上传。

## API（给 AI / 脚本用）

每种模式一个端口，请求格式和 OpenAI `audio/speech` 一致，另外加了几个扩展字段。

```bash
# 预设音色 + 风格指令
curl -X POST http://127.0.0.1:8091/v1/audio/speech -H "Content-Type: application/json" \
  -d '{"input":"今天天气真好。","voice":"vivian","instructions":"用开心的语气说","language":"chinese","response_format":"wav"}' \
  -o out.wav

# 声音设计
curl -X POST http://127.0.0.1:8092/v1/audio/speech -H "Content-Type: application/json" \
  -d '{"input":"Hello there.","instructions":"male, middle-aged, deep and calm","response_format":"wav"}' -o out.wav

# 克隆：先注册（wav_b64 是 WAV 文件的 base64；ref_text 可选）
curl -X POST http://127.0.0.1:8090/v1/audio/voices -H "Content-Type: application/json" \
  -d '{"name":"narrator","ref_text":"参考音频原文","wav_b64":"<base64>"}'
curl -X POST http://127.0.0.1:8090/v1/audio/speech -H "Content-Type: application/json" \
  -d '{"input":"用克隆的声音说这句话。","voice":"narrator","response_format":"wav"}' -o out.wav
```

Python（`openai` 包）：

```python
from openai import OpenAI
client = OpenAI(base_url="http://127.0.0.1:8091/v1", api_key="local")
with client.audio.speech.with_streaming_response.create(
        model="qwen3-tts-customvoice", voice="vivian", input="你好！",
        response_format="wav", extra_body={"language": "chinese"}) as r:
    r.stream_to_file("out.wav")
```

| 接口 | 说明 |
|---|---|
| `POST /v1/audio/speech` | 合成。`input` 必填；`voice`、`instructions`、`language`；`response_format`：`wav`（整段返回）或 `pcm`（边生成边流式返回 s16le 24 kHz 单声道） |
| `GET /v1/audio/voices` | 可用声音：`kind:"speaker"` 是内置说话人，`kind:"registered"` 是注册的克隆声音 |
| `POST /v1/audio/voices` | 注册克隆声音：`{name, wav_b64, ref_text?}`，或 `{name, spk_b64, rvq_b64, ref_text?}` |
| `DELETE /v1/audio/voices/{name}` | 删除注册的声音 |
| `GET /v1/models` | 当前加载的模型 id（`qwen3-tts-base` 等） |
| `GET /health` | 存活检查 |

可选采样参数：`seed`、`temperature`、`top_k`、`top_p`、`repetition_penalty`、`max_new_tokens`（12.5 帧约等于 1 秒），
以及 `subtalker_temperature`、`subtalker_top_k`、`subtalker_top_p`。固定 `seed` 可以复现同样的结果。

`language`（不区分大小写）：`auto`、`chinese`、`english`、`japanese`、`korean`、`german`、`french`、`russian`、
`portuguese`、`spanish`、`italian`、`beijing_dialect`、`sichuan_dialect`。

预设说话人：`vivian`、`serena`、`uncle_fu`、`dylan`（北京话）、`eric`（四川话）、`ryan`、`aiden`、`ono_anna`、`sohee`。

规则：`instructions` 对预设音色是可选的，对声音设计是必填的，Base 模型会拒绝它。克隆声音只能在 Base 端口（8090）上用。

---

## English summary

- `scripts\build.cmd` clones [qwentts.cpp](https://github.com/ServeurpersoCom/qwentts.cpp) and builds it with CUDA
  (needs VS Build Tools with the C++ workload, the CUDA Toolkit and git). Binaries land in `bin\`.
- Put the GGUFs from [Serveurperso/Qwen3-TTS-GGUF](https://huggingface.co/Serveurperso/Qwen3-TTS-GGUF) in `models\`.
- `scripts\start.cmd [all|base|customvoice|voicedesign] [models_dir]` starts one server per mode
  (base 8090, customvoice 8091, voicedesign 8092) and opens `web\index.html`.
- `models\voices\<name>.wav` (+ optional `<name>.txt` transcript) are registered on the base server at
  startup and become usable as `"voice": "<name>"`.
- The API is OpenAI-compatible (`/v1/audio/speech`) with extra fields: `language`, `instructions`, `seed`
  and sampling overrides. See the table above.

## 致谢 / Credits

- [qwentts.cpp](https://github.com/ServeurpersoCom/qwentts.cpp)（MIT）：C++/GGML 推理引擎和 `tts-server`
- [Qwen3-TTS](https://github.com/QwenLM/Qwen3-TTS)（Apache 2.0）：Alibaba Qwen 团队的原始模型
- [Serveurperso/Qwen3-TTS-GGUF](https://huggingface.co/Serveurperso/Qwen3-TTS-GGUF)：转换好的 GGUF 权重

本仓库的前端和脚本使用 MIT 许可证。
