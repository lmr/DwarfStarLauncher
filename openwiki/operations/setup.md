# Operations & Setup

## Building

```bash
# Build the app
swift build

# Run (requires macOS 14.0+)
swift run
```

The project uses **Swift Package Manager** with two targets:

- `HuggingFaceDownloader` — a library containing the HuggingFace API client and the file-backed token store
- `App` — the executable target (depends on `HuggingFaceDownloader`)

No third-party dependencies are required beyond the standard Swift toolchain. The minimum deployment target is macOS 14.0 (Sonoma).

## Prerequisites

### 1. DS4 Build Import (Recommended)

The easiest way to set up ds4-server and its companion binaries is to **import a built DS4 project** from the Settings window's "DS4 Build" group:

1. Click **"Import Build"** and select the root directory of your compiled ds4 checkout (the folder containing `metal/` and `ds4-server`).
2. The app validates that the directory contains an executable `ds4-server` and a `metal/` subdirectory, then copies all binaries (`ds4`, `ds4-agent`, `ds4-bench`, `ds4-eval`, `ds4-server`) into `~/.ds4-launcher/bin/`.
3. Click **"Refresh"** anytime to re-copy updated binaries from the same import path (persisted in config as `importPath`).

### 2. Manual Binary Placement

Alternatively, place the ds4-server binary manually at:

```
~/.ds4-launcher/bin/ds4-server
```

This binary is **not included** in this repository. You must obtain it separately or via step 1 above. The app expects it to accept the CLI flags documented in [Domain Concepts](domain/llm-launcher.md).

### 3. Model Files

Place GGUF model files in:

```
~/.ds4-launcher/models/
```

Only files with `.gguf` extension (or path ending in `.gguf`) are detected. The app scans this directory at launch and on manual refresh. `ModelManager` separates main models from MTP/DSpark models based on filename keywords.

### 4. Metal Shaders Directory

The `~/.ds4-launcher/metal/` directory stores Metal shader libraries copied during DS4 build import. It is created automatically by the import workflow and also ensured at app startup via `ContentView.ensureDirectoriesExist()`.

### 5. (No external download script required)

Model downloads use the app's **native HuggingFace Hub downloader** (`ModelDownloader`) backed by the `HuggingFaceDownloader` library module. No external script is needed — the app fetches GGUF files directly via URLSession with resume support and integrity verification.

## Configuration

The app persists server configuration to:

```
~/.config/ds4-launcher/config.json
```

This file is loaded on launch and written on every config change. You can also edit it directly — it's a JSON representation of `ServerConfig`.

### Default Config Values

| Field | Default | Description |
|-------|---------|-------------|
| `modelPath` | `""` | Path to main GGUF model (must be set via UI) |
| `hfToken` | `nil` | HuggingFace token (managed via ConfigTokenStore; same config file) |
| `mtpModelPath` | `"~/.ds4-launcher/models/DeepSeek-V4-Flash-MTP-Q4K-Q8_0-F32.gguf"` | Path to MTP model |
| `enableMtp` | `true` | Enable multi-token prediction (uses `--dspark --mtp` when filename contains "dspark") |
| `contextSize` | 262,144 | Context size in tokens |
| `power` | 100 | Power level (0–100) |
| `host` | `"0.0.0.0"` | Bind address |
| `port` | 1234 | Bind port |
| `kvSpace` | 8192 | KV cache disk space limit in MB (only emitted when `ssdStreaming` is true) |
| `ssdStreaming` | `false` | Enable SSD streaming (`--ssd-streaming`, `--kv-disk-dir`, `--kv-disk-space-mb`) |
| `kvDiskPath` | `nil` | Optional explicit KV cache disk directory path |
| `importPath` | `nil` | Persisted DS4 build import directory (set via ProjectImportManager) |
| `customModelsDirectory` | `nil` | Optional user-chosen models directory (stored in UserDefaults, not config.json) |

## Running

1. Launch the app. The main window is a tabbed shell (Dashboard / Log / Downloads) with a bottom navigation bar and toolbar chrome.
2. **(Recommended)** Open **Settings → DS4 Build** and click **"Import Build"** to copy ds4 binaries from your compiled checkout into `~/.ds4-launcher/bin/`. Alternatively place `ds4-server` manually as described above.
3. Select a model in **Settings → Model**, or download one via the **Downloads** tab — which also hosts the HuggingFace token manager.
4. Configure server options in **Settings**: context size, host/port, power level, MTP model toggle, and SSD streaming with optional KV disk path/space.
5. Press **Play** (▶) in the toolbar to start ds4-server.
6. Monitor startup in the Log tab. Status changes to "Running" when the server reports `"listening on http"`. Watch live metrics on the Dashboard tab.
7. Press **Stop** (⏹) to shut down, or **Restart** (↻) to restart.

## Troubleshooting

- **"Failed to launch" error** — Verify ds4-server exists at `~/.ds4-launcher/bin/ds4-server` and is executable. Use "Import Build" in Settings → DS4 Build or place it manually.
- **No models found** — Place `.gguf` files in the models directory (default `~/.ds4-launcher/models/`, or a custom directory set in Settings → Model) and press Refresh. MTP/DSpark models are separated automatically by filename.
- **Server starts but status stays "Starting"** — The server must emit `"listening on http"` on stderr. Check the log output.
- **Download fails with 401/403** — Save a HuggingFace token via the Downloads tab's "Hugging Face Token" section (stored in `config.json` as `hfToken`). Alternatively set `HF_TOKEN` environment variable or use `~/.cache/huggingface/token`.
- **Download fails with 429** — You are rate-limited. Adding an HF token increases limits significantly.
- **Integrity check failed after download** — The `.part` file's size or magic header did not match expectations. Resume may have been corrupted; the downloader deletes and restarts on integrity failure. Check available disk space.
- **"Import Error" alert during build import** — The selected directory does not contain a valid DS4 project (missing `metal/` folder or non-executable `ds4-server`). Select the correct root directory of your ds4 checkout.
- **SSD streaming options grayed out / KV cache errors** — SSD streaming requires server support for `--ssd-streaming`, `--kv-disk-dir`, and `--kv-disk-space-mb`. Ensure you are running a compatible ds4-server version.
- **Config not loading** — Check that `~/.config/ds4-launcher/config.json` exists and is valid JSON matching `ServerConfig`.

## Filesystem Layout Summary

```
~/.ds4-launcher/
├── bin/
│   └── ds4-server           # Required — the LLM inference server binary (import via "Import Build" or place manually)
├── models/                  # Place .gguf files here; .part files during downloads
├── metal/                   # Metal shader libraries (copied from DS4 project on import)
└── cache/
    └── model_oids.json      # Cached HF file OIDs for integrity verification

~/.config/ds4-launcher/
└── config.json              # Auto-managed server configuration (includes importPath, ssdStreaming, kvDiskPath)

~/.ds4/server-kv/             # Created by ds4-server when SSD streaming is enabled
```
