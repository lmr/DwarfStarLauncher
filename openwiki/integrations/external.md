# External Integrations

## ds4-server Binary

The primary external dependency is **ds4-server**, a local LLM inference server binary. This repo does **not** build or vendor ds4-server. The app expects it at:

```
~/.ds4-launcher/bin/ds4-server
```

### Contract

- **CLI interface** — ds4-server must accept flags as defined by `ServerConfig.buildArguments()`. See [Domain Concepts](domain/llm-launcher.md#server-cli-contract) for the full flag table.
- **Startup signal** — The server must print a line containing `"listening on http"` on **stderr** to indicate successful startup.
- **Shutdown signal** — A line containing `"shutdown requested"` on either stdout or stderr transitions the status to `.stopped`.
- **Log format** — For telemetry parsing, the server should emit lines containing `prefill`, `decoding`, and `ctx=` patterns on any output stream (both stdout and stderr are captured). See [Domain Concepts](domain/llm-launcher.md#expected-log-format-for-telemetry).
- **Exit codes** — Exit code 0 → `.stopped`; non-zero → `.error(exitCode)`.

### Process Management

`ServerManager` creates a `Process` with:

- Executable URL → `PathResolver.serverBinary` (i.e., `~/.ds4-launcher/bin/ds4-server`)
- Arguments → `ServerConfig.buildArguments()`
- Current directory → `PathResolver.dataRoot` (i.e., `~/.ds4-launcher/`)
- stdout/stderr → separate `Pipe` objects for line-by-line capture

The process is **not** managed as a daemon — it runs as a direct child process of the app and terminates when the user presses Stop or the app exits.

---

## HuggingFace Hub (Model Downloads)

The model download feature uses a native Swift URLSession-based downloader (`ModelDownloader`, in the `App` target). No external script is required.

### Downloader Contract

- **Target catalog** — 13 named targets organized into three categories: DeepSeek Flash (5), PRO Models (4), and GLM Models (4). See [Download Targets](domain/llm-launcher.md#download-targets) for the full list including expected sizes and source repos.
- **HF API client** — `DefaultHuggingFaceClient` resolves file paths, download URLs, and OIDs via the Hugging Face REST API (`/api/models/{repo}/tree/main/{path}` and `/resolve/main/{path}`). Resolved OIDs are cached in `~/.ds4-launcher/cache/model_oids.json`.
- **URL construction** — `buildHFDownloadURL(target:file:)` constructs per-file URLs from each target's HuggingFace repo and the file's remote name (supports nested subdirectory paths like GLM Unsloth shards).
- **Resume support** — partial `.part` files are detected via magic header verification (`verifyMagicHeader`) before resuming; HTTP Range headers request bytes from the last offset.
- **Progress** — reported as percent, bytes downloaded, total bytes, speed (bytes/sec), and ETA (seconds) via `URLSessionDataDelegate` callbacks.
- **Completion** — on success, `.part` is renamed to `.gguf`, the model list is refreshed, and single-file targets inside the models dir are auto-selected in config. Multi-file targets complete all files before reporting completion.
- **Integrity** — verifies file size matches expected; checks GGUF magic header (`GGUF`/`GGML`/`FGGU`); when a cached SHA256 OID is available from the HF API, performs full hash verification via `CryptoKit.SHA256`. Failed integrity deletes the `.part` and restarts.
- **Token resolution** — tries the file-backed `hfToken` in `config.json` (cached in-memory), then `HF_TOKEN` env var, then `~/.cache/huggingface/token`, in that order.

---

## Filesystem Layout

All paths are managed by `PathResolver`, a utility enum that centralizes path construction:

| Path | Resolver Property | Purpose |
|------|------------------|---------|
| `~/.ds4-launcher/` | `dataRoot` | Top-level data directory, server CWD |
| `~/.ds4-launcher/bin/` | `binDir` | ds4-server + DS4 build binaries (via import or manual placement) |
| `~/.ds4-launcher/models/` | `modelsDir` | GGUF model files and `.part` download files (custom override via UserDefaults `customModelsDirectory`) |
| `~/.ds4-launcher/metal/` | `metalDir` | Metal shader libraries (copied from DS4 project on import) |
| `~/.ds4-launcher/cache/model_oids.json` | — | Cached HF file OIDs for integrity verification |
| `~/.config/ds4-launcher/` | `configRoot` | Persistent configuration directory |
| `~/.config/ds4-launcher/config.json` | `configFile` | Serialized `ServerConfig` JSON (includes `importPath`, `ssdStreaming`, `kvDiskPath`, `hfToken`) |
| `~/.ds4-launcher/models/<filename>.part` | `partFileURL(for:)` | Partial download file for resume |

On app startup, `ContentView.ensureDirectoriesExist()` creates `binDir`, `modelsDir`, `metalDir`, and `configRoot` if they don't exist. The app does **not** create the `ds4-server` binary — it must be imported via "Import Build" or placed manually.

---

## OpenWiki / GitHub Actions Integration

The repository includes an OpenWiki update workflow at `.github/workflows/openwiki-update.yml`. This workflow refreshes the `openwiki/` documentation on push to the main branch. The `AGENTS.md` and `CLAUDE.md` files contain markers indicating that OpenWiki generates the documentation and that hand-editing wiki pages is discouraged.
