# Architecture Overview

## App Architecture

DwarfStarLauncher is a SwiftUI macOS app (minimum macOS 14.0) that launches, configures, and monitors a local LLM inference server called **ds4-server**. It is split into two SwiftPM targets: an executable (`App`) and a small library dependency (`HuggingFaceDownloader`). The downloader was collapsed into the `App` target during the UI rework, so the library now holds only the HuggingFace API client and the file-backed token store.

The `App` target follows an **environment-injected service layer** pattern — six `@Observable` service classes are created as static singletons on `AppDelegate` and injected into every scene (main window, Settings window, and menu bar extra) via a shared `rootContent`/`injectAppEnvironment` helper and SwiftUI's `.environment()` mechanism. Views consume them with `@Environment(ServiceName.self)` (the Observation pattern). There is **no unified `AppState` container** — state is decentralized across the per-domain managers.

### Service Layer

```
DwarfStarLauncherApp (WindowGroup + Settings + MenuBarExtra)
  ├── ServerManager        — process lifecycle, config persistence, log capture/classification
  ├── StatusMonitor        — log parsing for throughput & context telemetry + system metrics
  ├── ModelManager         — filesystem scan for GGUF model files (main + MTP)
  ├── ModelDownloader      — native URLSession HF Hub downloader (single- & multi-file, resume + integrity)
  ├── ProjectImportManager — DS4 build import: validate metal/ dir + binaries, copy to local dirs
  └── AppErrorManager      — centralized error string surfaced via the inline ErrorBanner

Shared (library) dependency:
  ConfigTokenStore         — file-backed HF token store (hfToken in config.json) with static in-memory cache
```

| Service | Observables / Properties | Role |
|---------|--------------------------|------|
| `ServerManager` | `status`, `config`, `logLines`, `statusMonitor` (let, injected) | Spawns/kills/restarts the ds4-server `Process`, captures stdout/stderr as `LogLine`s, classifies log levels, persists config to JSON |
| `StatusMonitor` | `prefillTokensPerSecond`, `generationTokensPerSecond`, `contextUsed`, `contextTotal`, `maxContext`, `systemMemoryUsedMB`, `systemMemoryTotalMB`, `gpuLoadPercent`, `history` | Regex-parses each log line for performance metrics; collects system memory (host_statistics64) and GPU load (IOKit) on a 2-second timer |
| `ModelManager` | `models`, `mtpModels`, `selectedModel`, `selectedMtpModel`, `isRefreshing` | Enumerates `~/.ds4-launcher/models/` for `.gguf` files; separates into main and MTP lists; tracks dual selection |
| `ModelDownloader` | `downloadState`, `currentTarget`, `availableTargets` (all `DownloadTarget` cases), `resolvedSizes`, `resolvedOids`, `onDownloadComplete`/`onDownloadError` callbacks | Downloads models from HuggingFace Hub via a `URLSessionDataDelegate` (single-file) and `AsyncBytes` (multi-file) with resume support, real-time size resolution via `HuggingFaceClient`, OID caching + SHA256 integrity checks; completion callbacks are wired in `AppDelegate.configureDownloadCallbacks()` |
| `ProjectImportManager` | `importPath`, `lastImportDate`, `isImporting`, `statusMessage`, `alertMessage` | Validates a DS4 project directory (requires `metal/` dir + executable `ds4-server`), copies binaries and metal shaders to local dirs; import path persisted in config |
| `AppErrorManager` | `errorMessage` | Holds the current error message, displayed as an inline `ErrorBanner` at the top of `ContentView` |

### Service Lifecycle & Safety (recent hardening)

Recent commits hardened the service layer in ways that matter for future edits:

- **`StatusMonitor` is now a required dependency of `ServerManager`.** `ServerManager.init(statusMonitor:)` takes the shared monitor; `AppDelegate.sharedServerManager` is constructed with `AppDelegate.sharedStatusMonitor` so there is a single canonical monitor instance. The old optional `statusMonitor?` property is gone — code calls `statusMonitor.parse(line)` / `startTimer()` / `stopTimer()` directly with no nil-checks.
- **`StatusMonitor.startTimer()` self-guards against timer leaks.** It now calls `timer?.invalidate()` before scheduling a new 2-second timer, so a replacement never leaks a still-scheduled timer. This was previously guarded by a `spawn()` check in `ServerManager`.
- **Log parsing is dispatched to the main thread.** `ServerManager` wraps stdout/stderr line processing in `DispatchQueue.main.async` to prevent concurrent access to `logLines` and `StatusMonitor.history` while SwiftUI reads them.
- **Download-completion callbacks are `[weak self]` and decomposed.** `AppDelegate.configureDownloadCallbacks()` no longer reaches into three managers from one closure. It calls `handleDownloadCompletion(of:)` which applies **Effect 1** (refresh model list) unconditionally, then **Effect 2** (wire a selectable model path into `config.modelPath` + selection) only if the target maps to a single selectable model file inside the models directory. The side-effect-free decision lives in `selectableModelPath(for:)`, which resolves symlinks on both the downloaded path and the models dir before the containment check.
| `AppErrorManager` | `errorMessage` | Holds the current error message, displayed as an inline `ErrorBanner` at the top of `ContentView` |

### Data Flow

1. **Startup** → `ContentView.onAppear` calls `ensureDirectoriesExist()`, ensuring data root, bin, models, metal, and config directories exist. `AppDelegate.init()` constructs the shared `ServerManager(statusMonitor:)`, wires download callbacks, and warms the in-memory token cache (`ConfigTokenStore().load()`).
2. **Model Discovery** → `ModelManager.refresh()` runs on Settings model picker `onAppear` and manual refresh. Scans the models dir for all `.gguf` files; separates those whose name contains "mtp" or "dspark" into `mtpModels`.
3. **Model Selection** → Tapping a model in Settings sets `serverManager.config.modelPath` (or `mtpModelPath` for MTP) via `selectModel(byPath:)`.
4. **Server Launch** → User presses Play (toolbar `TopChromeStrip`) → `ServerManager.spawn(config:)` constructs a `Process` with the ds4-server binary and `config.buildArguments()` (including `--mtp`/`--dspark --mtp` and `--mtp-draft 2`, plus `--ssd-streaming`/`--kv-disk-dir`/`--kv-disk-space-mb` when SSD streaming is enabled), captures output pipes, and starts the status-monitor timer.
5. **Log Streaming** → `readabilityHandler` on stdout/stderr pipes dispatches to the main thread, appends `LogLine` entries to `serverManager.logLines`, classifies levels, and forwards each line to `StatusMonitor.parse(_:)`.
6. **Telemetry Parsing** → `StatusMonitor.parse(_:)` extracts prefill/generation/context metrics via regex and appends `MetricsSnapshot` entries to `history` (capped at 1000).
7. **System Metrics** → A 2-second timer calls `collectSystemMetrics()` (memory) and `collectGPU()` (GPU load) while the server runs; results are stored in `history`. Throughput values expire after 3 seconds of inactivity.
8. **Server Stop** → `ServerManager.stop()` stops the monitor timer, terminates the process with a 5-second timeout, then SIGKILL if needed. On app termination, `stopSynchronously()` is called.
9. **Server Restart** → `ServerManager.restart()` calls `stop()` then `spawn()` after a 1-second delay.

### Download Flow (HuggingFace Hub)

1. User selects a target in `DownloadsView` (Downloads tab) or clicks Download on a model card. The downloader resolves real file sizes via the HF API (`/api/models/<repo>/tree/main/<path>`), caching OIDs in `~/.ds4-launcher/cache/model_oids.json`.
2. `ModelDownloader.download(target:)` opens a `.part` file for resume (verifying the GGUF magic header before appending) and starts a URLSession task with Bearer auth resolved from the token chain.
3. Progress is reported via the URLSession delegate as percent/bytes/speed/ETA; speed uses a 5-second rolling window and progress pushes are throttled to ~4 Hz.
4. On completion, integrity is checked (size match + magic header + optional SHA256 OID verification); on success the `.part` file is renamed to `.gguf` and `downloadState` becomes `.complete`.
5. The `onDownloadComplete` callback (wired in `AppDelegate.configureDownloadCallbacks()`) refreshes `ModelManager` and, for single-file targets inside the models dir, sets `config.modelPath` and auto-selects the model. Multi-file targets (`proQ4Split`, `glmUnslothQ4`) are **not** auto-selected because they produce multiple files that need manual assembly.
6. Errors are routed through `AppErrorManager.errorMessage` → the inline `ErrorBanner`, or surfaced as a per-card error state.

### Project Import Flow

1. User clicks "Import Build" in Settings' DS4 Build group, triggering `FolderPicker`.
2. User selects a directory; `ProjectImportManager.validateProject(at:)` checks for an executable `ds4-server` and a `metal/` subdirectory. If invalid, sets `alertMessage`.
3. On valid selection, `importFrom(url:)` runs on a background queue: removes-and-replaces the local `metal/` dir, then copies each binary (`ds4`, `ds4-agent`, `ds4-bench`, `ds4-eval`, `ds4-server`) into `~/.ds4-launcher/bin/`.
4. On completion, persists the import path in config (via `persistImportPath()`), updates `importPath`/`lastImportDate` for UI binding.
5. "Refresh" re-runs the same copy from the persisted path; "Change Path" clears it so a new picker appears.

### Config Persistence

`ServerConfig` is persisted to `~/.config/ds4-launcher/config.json`. On app launch, `ServerManager.init()` loads it if present. Changes are made in the Settings window (`ConfigOverlayView`) against a **local config mirror**, then persisted with a 500ms debounced `persistTask` that cancels prior tasks before writing; a "Saved" indicator confirms writes. The config includes `importPath` (set by `ProjectImportManager`), `ssdStreaming`, `kvDiskPath`, and `hfToken` — the same file now backs both server config and the HF token, with `ConfigTokenStore` decoding only the `hfToken` field to avoid coupling on the full schema.

---

## Directory Layout

```
~/.ds4-launcher/
├── bin/              — ds4-server + DS4 build binaries (imported via ProjectImportManager)
├── models/           — GGUF model files (scanned at runtime), .part files during download
├── metal/            — Metal shader libraries (copied from DS4 project on import)
└── cache/
    └── model_oids.json  — cached HF file OIDs for integrity checks

~/.config/ds4-launcher/
└── config.json       — persisted ServerConfig (includes importPath, ssdStreaming, kvDiskPath, hfToken)

~/.ds4/server-kv/     — KV cache disk directory (created by ds4-server when SSD streaming is on)
```

See [External Integrations](integrations/external.md) for details.

---

## Why This Architecture

- **Dashboard-first shell** — the app moved away from the old split-view (left config panel + right tab view). The main window is now a tabbed shell (Dashboard / Log / Downloads) with a bottom navigation bar and toolbar chrome; configuration moved to the standard macOS **Settings** window. This separation keeps monitoring and configuration independent.
- **Modular dependency** — the app is split into two SwiftPM targets: `HuggingFaceDownloader` (now a thin library with the HF API client and file-backed token store) and `App` (the executable containing download targets, path resolution, services, and views). This keeps model-download logic testable in isolation from SwiftUI.
- **Process-based server management** — the LLM server runs as a child process rather than in-process, providing process isolation and letting the user kill/restart independently.
- **Observable services** — each service is `@Observable` (Swift 5.9 macro), enabling fine-grained SwiftUI reactivity without Combine.
- **Log-based telemetry** — the server emits structured log lines; the app parses them client-side rather than requiring a separate metrics API.
- **Native model downloads** — `ModelDownloader` uses `URLSessionDataDelegate` for direct HuggingFace Hub downloads with resume support, eliminating the shell-script dependency.
- **System metrics** — system memory and GPU load are collected via macOS IOKit and Mach APIs for in-app performance monitoring.
- **Build import workflow** — `ProjectImportManager` lets users point the app at a DS4 build directory; it validates the presence of a `metal/` folder and an executable `ds4-server`, then copies all binaries into `~/.ds4-launcher/bin/`. The import path is persisted in config.
- **Centralized error surface** — `AppErrorManager` holds a single error string that drives the inline `ErrorBanner`, so download failures, launch errors, and other issues are consistently surfaced without scattering alert state across views.
- **File-backed token store** — the HuggingFace token is stored in `config.json` (as `hfToken`) with a static in-memory cache, replacing the old Keychain store. This avoids keychain password prompts during downloads but means the token is plaintext in the user's config file.
