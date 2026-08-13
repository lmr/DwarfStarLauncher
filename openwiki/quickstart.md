# DwarfStarLauncher Quickstart

**DwarfStarLauncher** is a native macOS app (SwiftUI, minimum macOS 14.0) that launches, configures, and monitors a local LLM inference server called **ds4-server**. It manages the full lifecycle: model discovery, model download, server start/stop, live log streaming, and real-time performance telemetry.

The app uses a **design-token-driven shell** with three tabs (Dashboard / Log / Downloads), a bottom navigation bar, a toolbar status chrome strip, and a standard macOS **Settings** window. Configuration and monitoring no longer live side-by-side in a split view — the shell is now dashboard-first.

---

## What This Wiki Covers

| Page | Description |
|------|-------------|
| [Architecture Overview](architecture/overview.md) | App structure (6 services + keychain), data flow, and design rationale |
| [Domain Concepts](domain/llm-launcher.md) | ds4-server CLI contract, GGUF format, download targets, server status model |
| [SwiftUI Views](views/overview.md) | View hierarchy, Downloads tab, HF token management, interactive controls |
| [Operations & Setup](operations/setup.md) | Building, configuring, and running the app |
| [External Integrations](integrations/external.md) | ds4-server binary, HuggingFace Hub downloader, filesystem layout |

---

## Key Files

| File | Purpose |
|------|---------|
| `Package.swift` | SwiftPM manifest — two targets: `HuggingFaceDownloader` library + `App` executable, macOS 14.0+ |
| `DwarfStarLauncherApp.swift` | `@main` App struct — `WindowGroup` + `Settings` + `MenuBarExtra`; injects six shared services into every scene via `rootContent`/`injectAppEnvironment`; `AppDelegate` owns the singletons, wires download callbacks, and warms the token cache |
| `ContentView.swift` | Root shell — owns `selectedTab` (`MainTab`), inline error banner, tab-content switch, `BottomTabBar`, toolbar `TopChromeStrip`, and directory bootstrap |
| `DashboardView.swift` | Primary tab — stat tiles + Swift Charts metric history (monotone interpolation), warm-up gating, and an empty state with Start action when stopped |
| `DownloadsView.swift` | Collapsible download categories, per-target model cards with status badge, linear progress, Size/Speed/ETA stat slots, and Download/Resume/Cancel actions |
| `ConfigOverlayView.swift` | Standard macOS Settings window (`NavigationSplitView`, 6 groups: Model/MTP/Server/Advanced/DS4 Build/Interface) with a local config mirror + 500ms debounced persistence |
| `BottomTabBar.swift` | Custom navigation bar (Dashboard/Log/Downloads) with per-tab badges and a Settings gear |
| `TopChromeStrip.swift` | Toolbar chrome — status dot + label and a custom Play/Stop/Restart `ControlGroup` |
| `ServerManager.swift` | Server lifecycle — `Process` management, config persistence, log capture (main-thread dispatch) and classification, restart support, DSpark/MTP flag handling; requires an injected `StatusMonitor` |
| `StatusMonitor.swift` | Regex-parses log lines for prefill/generation throughput and context usage; collects system memory and GPU load via macOS APIs on a 2s timer (self-invalidating `startTimer()`) |
| `ModelManager.swift` | Scans the models dir for `.gguf` files; separates main and MTP/DSpark models by filename |
| `ModelDownloader.swift` (App) | HF Hub downloader — resolves sizes/OIDs via `HuggingFaceClient`, single- and multi-file flows, resume + SHA256 integrity checks |
| `ProjectImportManager.swift` | DS4 build import — validates `metal/` dir + executable `ds4-server`, copies binaries, persists import path in config |
| `AppErrorManager.swift` | Centralized error string driving the inline `ErrorBanner`; set by download callbacks and launch failures |
| `ConfigTokenStore.swift` (library) | **File-backed** HF token store (`hfToken` in `config.json`) with static in-memory caching — no Keychain |
| `PathResolver.swift` | Centralises all filesystem paths under `~/.ds4-launcher/` and `~/.config/ds4-launcher/`, including a custom models directory override (UserDefaults) |
| `DesignSystem/` | Reusable tokens and components: `DesignTokens`, `Card`, `Panel`, `StatTile`, `MetricRow`, `FlowLayout`, `EmptyStateView` |

---

## Quick Start

1. **Build the app**: `swift build` (or open in Xcode and run).
2. **(Recommended)** Open **Settings → DS4 Build** and click "Import Build" to copy DS4 binaries from a compiled checkout into `~/.ds4-launcher/bin/`. Or place `ds4-server` manually at that path.
3. **Place/download models** in the models directory (default `~/.ds4-launcher/models/`, or a custom directory set in Settings → Model) — the app scans for `.gguf` files, or download directly via the **Downloads** tab (requires a HF token saved in the app config).
4. **Run the app**: pick a model in Settings, configure server options (including SSD streaming), and press **Play** in the toolbar.

For detailed setup steps, see [Operations & Setup](operations/setup.md).

---

## Next Steps

- Read [Architecture Overview](architecture/overview.md) to understand the service design.
- Read [Domain Concepts](domain/llm-launcher.md) to understand LLM serving concepts used by the app.
- Read [Views](views/overview.md) to understand the UI layout and controls.
- Read [Operations](operations/setup.md) for build, configuration, and troubleshooting.
- Read [Integrations](integrations/external.md) for the ds4-server binary and download script contract.
