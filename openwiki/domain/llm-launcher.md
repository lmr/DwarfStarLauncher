# Domain Concepts

## LLM Inference Server (ds4-server)

The app manages a local inference server called **ds4-server**. It is a standalone binary (not included in this repo) placed at `~/.ds4-launcher/bin/ds4-server`. The app passes CLI arguments built by `ServerConfig.buildArguments()`.

### Server CLI Contract

The app expects ds4-server to accept these flags:

| Flag | Config Field | Description |
|------|-------------|-------------|
| `--model <path>` | `modelPath` | Path to a main GGUF model file |
| `--mtp <path>` | `mtpModelPath` | Path to MTP (multi-token prediction) model (only when `enableMtp` is true and name does not contain "dspark") |
| `--dspark --mtp <path>` | — | DSpark variant of MTP launch; used when the MTP model filename contains "dspark" |
| `--mtp-draft <int>` | — | Draft count for MTP (always `2`) |
| `--ctx <int>` | `contextSize` | Context size in tokens (default 262,144) |
| `--power <int>` | `power` | Power/performance level (0–100) |
| `--host <addr>` | `host` | Bind address (default `0.0.0.0`) |
| `--port <int>` | `port` | Bind port (default 1234) |
| `--ssd-streaming` | `ssdStreaming` | Enable SSD streaming (flag only, no value; omitted when false) |
| `--kv-disk-dir <dir>` | `kvDiskPath` | KV cache disk directory (only emitted when `ssdStreaming` is true and path is set) |
| `--kv-disk-space-mb <int>` | `kvSpace` | KV cache disk space limit in MB (only when `ssdStreaming` is true and > 0) |

The server is expected to emit a line containing `"listening on http"` on stderr to signal successful startup, which transitions the status to `.running`. A line containing `"shutdown requested"` transitions the status to `.stopped`.

### Expected Log Format for Telemetry

`StatusMonitor` parses these patterns from log lines:

- `chunk=... t/s avg=<number> t/s` — prefill (prompt processing) throughput, extracted via regex on lines containing "prefill"
- `decoding chunk=... t/s avg=<number> t/s` — generation throughput, extracted via regex
- `ctx=<start>..<end>:<used>` — context utilization (e.g. `ctx=1..1024:1024`); the `end` value is used as `contextUsed`, and `maxContext` (default 262,144) is used as total

### System Metrics

`StatusMonitor` also collects system-level telemetry on a 2-second timer while the server is running:

- **System memory** — retrieved via `host_statistics64` (active + wire pages) and `ProcessInfo.physicalMemory`
- **GPU load** — retrieved via IOKit `IOAccelerator` service registry, using `"GPU Core Utilization"` or `"Device Utilization %"` performance statistics

---

## GGUF Model Format

The app works exclusively with **GGUF** (GPT-Generated Unified Format) model files. GGUF is a file format for quantized LLMs, commonly used with llama.cpp-based servers.

Models are stored as `.gguf` files under `~/.ds4-launcher/models/`. `ModelManager` scans this directory and separates files into two lists:

- **Main models** — all `.gguf` files not containing "mtp" in their name, sorted by size (largest first)
- **MTP models** — `.gguf` files whose name contains "mtp", sorted by size

Each model is represented by `GGUFModel`:

- `path` — absolute filesystem path
- `name` — last path component (the filename)
- `size` — file size in bytes (displayed via `ByteCountFormatter`)
- `isSelected` — UI selection state

---

## Download Targets

The app provides a **native Swift URLSession-based downloader** (`ModelDownloader`, in the `App` target) with download targets defined in `DownloadTargets.swift`. Thirteen named targets are grouped into three categories, each pulling from HuggingFace Hub:

| Category | Target Name (raw) | Display Name | Files | Expected Size | Source Repo |
|----------|-------------------|--------------|-------|---------------|-------------|
| DeepSeek Flash | `ds4f-q2` | DeepSeek Flash Q2 | 1 | ~86.7 GB | `antirez/deepseek-v4-gguf` |
| DeepSeek Flash | `ds4f-q2q4` | DeepSeek Flash Q2/Q4 Imatrix | 1 | ~97.6 GB | `antirez/deepseek-v4-gguf` |
| DeepSeek Flash | `ds4f-q4` | DeepSeek Flash Q4 Imatrix | 1 | ~164.6 GB | `antirez/deepseek-v4-gguf` |
| DeepSeek Flash | `ds4f-mxfp4` | DeepSeek Flash MxFP4 | 1 | ~155.9 GB | `antirez/deepseek-v4-gguf` |
| DeepSeek Flash | `ds4f-dspark` | DeepSeek Flash DSpark | 1 | ~6.0 GB | `antirez/deepseek-v4-gguf` |
| PRO Models | `pro-q2-imatrix` | PRO Q2 Imatrix | 1 | ~464.6 GB | `antirez/deepseek-v4-gguf` |
| PRO Models | `pro-q4-layers00-30` | PRO Q4 Layers 00–30 | 1 | ~457.5 GB | `antirez/deepseek-v4-gguf` |
| PRO Models | `pro-q4-layers31-output` | PRO Q4 Layers 31-Output | 1 | ~441.9 GB | `antirez/deepseek-v4-gguf` |
| PRO Models | `pro-q4-split` | PRO Q4 Split (2 files) | 2 | ~905.5 GB combined | `antirez/deepseek-v4-gguf` |
| GLM Models | `glm-unsloth-q4` | GLM Unsloth Q4 (11 shards) | 11 | ~538.7 GB total | `unsloth/GLM-5.2-GGUF` |
| GLM Models | `glm-antirez-iq2xxs` | GLM Antirez IQ2XXS | 1 | ~211.0 GB | `antirez/GLM-5.2-GGUF` |
| GLM Models | `glm-antirez-q2` | GLM Antirez Q2 | 1 | ~262.0 GB | `antirez/GLM-5.2-GGUF` |
| GLM Models | `glm-antirez-q4` | GLM Antirez Q4 | 1 | ~434.1 GB | `antirez/GLM-5.2-GGUF` |

### Download Workflow

The download workflow has two paths depending on whether the target is single-file or multi-file:

**Single-file targets** (`ds4f-*`, `pro-*` individual, all GLM Antirez/Unsloth except shards):
1. On `download(target:)`, resolves real file sizes from the HuggingFace API via `DefaultHuggingFaceClient.resolveFilePath` (falls back to catalog size if resolution fails).
2. Checks for an existing `.part` file and resumes via HTTP Range request if the magic header (`GGUF`/`GGML`/`FGGU`) is valid; otherwise deletes and restarts.
3. Streams data through `URLSessionDataDelegate`, writing chunks to the `.part` file while computing speed (5-second sliding window) and ETA in real time.
4. On completion, verifies integrity via size match + magic header (+ optional SHA-256 if a cached OID exists), then renames `.part` → final filename.

**Multi-file targets** (`pro-q4-split`, `glm-unsloth-q4`):
1. Uses `downloadMultiFile(target:)` which iterates over all files in the target.
2. Each file is downloaded sequentially with its own resume/integrity logic.
3. Progress reflects overall bytes across all files.

### Resume & Integrity

- **Resume** — partial `.part` files at `~/.ds4-launcher/models/<filename>.part` are detected by size; if the first 4 bytes match a known GGUF magic header, download resumes from that offset via `Range: bytes=<offset>-`.
- **OID cache** — resolved HuggingFace file OIDs (SHA-256) are cached in `~/.ds4-launcher/cache/model_oids.json` to avoid re-fetching on every size resolution. Cached hashes are used for optional post-download SHA-256 verification (`checkIntegrity`).
- **Auto-select** — on completion, single-file targets inside the models directory auto-select the downloaded model and set `config.modelPath`; multi-file targets (`proQ4Split`, `glmUnslothQ4`) do not auto-select because they produce multiple files that need manual assembly.

### Authentication

The downloader resolves a HuggingFace token via fallbacks:
1. **File-backed config token** — `ConfigTokenStore` reads/writes the `hfToken` field of `~/.config/ds4-launcher/config.json` (the same file as `ServerConfig`), with a static in-memory cache so the file is read once per session. `ServerConfig.hfToken` mirrors it for argument building.
2. **`HF_TOKEN` environment variable** — fallback if no stored token exists.
3. **`~/.cache/huggingface/token`** — HF CLI token cache file, last resort.

Users can save/clear tokens via the `HuggingFaceTokenSection` UI in the Downloads tab. The token is plaintext in the user's config file (no Keychain involvement).

---

## Server Status Model

The server lifecycle is modeled by `ServerStatus`:

```
starting  →  running  →  stopped
                        →  error(exitCode)
```

| Status | UI Color | Transition |
|--------|----------|------------|
| `starting` | yellow | Process launched |
| `running` | green | stderr contains "listening on http" |
| `stopped` | gray | Process exits with code 0, or stderr contains "shutdown requested" |
| `error(exitCode)` | red | Process exits with non-zero code, or launch failure |

---

## Download State Model

`DownloadState` tracks model download progress:

```
idle  →  progress(bytes, total, speed, eta)  →  complete
                                              →  error(message)
                                              →  failed(reason)
```

- `.idle` — no download active
- `.progress(percent, bytesDownloaded, totalBytes, speedBytesPerSec, etaSeconds)` — active download with byte-level progress
- `.complete` — finished successfully
- `.error(message)` — download failure with error message
- `.failed(reason)` — integrity check failure (hash mismatch, etc.)
- `cancel()` resets to `idle` and cancels the URLSession task

---

## Log Line Classification

`ServerManager.classify(_:)` assigns a `LogLevel` to each log line based on keywords:

| Level | Keywords | UI Color |
|-------|----------|----------|
| `.timing` | `t/s` | Teal |
| `.generation` | `gen=` | Green |
| `.prefill` | `prefill` | Teal |
| `.kvcache` | `kv cache` | Olive |
| `.tool` | `tool calls` | Gray |
| `.warning` | `warning` | Orange |
| `.error` | `failed` or `error` | Red |
| `.info` | (default) | Primary |

`LogView` displays each line with its level color and a monospaced font.
