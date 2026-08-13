# SwiftUI Views Overview

## View Hierarchy

```
DwarfStarLauncherApp (WindowGroup + Settings + MenuBarExtra)
├── WindowGroup "main" — ContentView (tabbed shell, min 800×600)
│   ├── ErrorBanner (conditional, top) — transient error bar via AppErrorManager
│   ├── Active tab content (Dashboard / Log / Downloads)
│   └── BottomTabBar — custom navigation with badges + Settings gear
│   └── .toolbar { TopChromeStrip } — status dot + Play/Stop/Restart
├── Settings — ConfigOverlayView (standard macOS Settings, NavigationSplitView)
└── MenuBarExtra (tray icon)
    ├── TrayTitleLabel — colored dot + status label in menu bar
    └── TrayMenu — status, model info, throughput, controls, quick actions, show, quit
```

### ContentView

- Root `VStack`: optional `ErrorBanner` at top, then the active tab content (with light top inset), then `BottomTabBar`.
- Owns `selectedTab` (`MainTab`: dashboard / log / downloads) and switches content via a `switch` — **no TabView**; the shell is dashboard-first.
- Injects the six services via `.environment()`; consumes `ServerManager`, `StatusMonitor`, `ModelManager`, and `AppErrorManager` directly.
- Toolbar hosts `TopChromeStrip` (status dot + label and a custom Play/Stop/Restart `ControlGroup`).
- `onAppear` calls `ensureDirectoriesExist()` which creates `binDir`, `modelsDir`, `metalDir`, and `configRoot`.
- **Error handling** — `AppErrorManager.errorMessage` drives the inline `ErrorBanner` only; the old alert-based error display was removed.

### BottomTabBar

- Custom navigation bar for Dashboard / Log / Downloads with per-tab badges and a Settings gear.
- **Dashboard badge** — shows an in-flight dot when the server is running.
- **Downloads badge** — shows an indicator while a download is in progress (`.progress` state).
- **Log tab danger dot** — shown when the server is in the `.error` state.

### TopChromeStrip

- Toolbar chrome strip: status dot + label, plus a custom Play/Stop/Restart `ControlGroup`.
- Replaces the old `StatusBar` bottom strip; controls moved to the toolbar.

### DashboardView

- Primary tab with warm-up gating and live metric charts.
- **Warm-up gating** — prefill/generation/context/memory/GPU stat tiles show "—" until the server is running *and* has produced real generation/prefill data (`hasRealGeneration`). This avoids misleading zeroes during startup.
- **Stat tiles** — `Prefill` (tok/s), `Generation` (tok/s), `Context` (used/total), `Memory` (used/total MB), `GPU` (%).
- **Metric charts** — five `Chart` cards (prefill, generation, context %, memory %, GPU %) each rendered with `AreaMark` over the last 60 seconds of `StatusMonitor.history`. Charts use `.interpolationMethod(.monotone)` for smoother graphs (added in the latest commit).
- **Empty state** — when stopped, shows "Server Stopped" with a Start action; when starting, shows a spinner.

### ConfigOverlayView (Settings)

- Standard macOS **Settings** window (`NavigationSplitView` with a sidebar list of 6 groups: Model / MTP / Server / Advanced / DS4 Build / Interface).
- Uses a **local config mirror** (`@State` fields) initialized from `AppDelegate.sharedServerManager.config` in `init()`, then persists via a 500ms debounced `persistTask` that cancels prior tasks before writing. A "Saved" indicator confirms writes, and a `saveError` shows failures inline.
- **Model group** — `ModelPickerView` (main models) plus a button to change the models directory (via `FolderPicker` → `PathResolver.setCustomModelsDirectory`) and "Reset to Default".
- **MTP group** — `enableMtp` toggle + `MtpModelPickerView`.
- **Server group** — context size, host, port (clamped 0–65535).
- **Advanced group** — power slider, SSD streaming toggle, and KV disk path/space fields (shown only when SSD streaming is on).
- **DS4 Build group** — `ImportStatusView`: shows import path + last-import date, Import Build / Refresh / Change buttons, and a progress spinner. Import errors surface via a native `.alert`.
- **Interface group** — Log view font family (monospaced families only) and font size (9–20pt), stored via `@AppStorage` (`logFontFamily`, `logFontSize`).

### DownloadsView

- **Downloads tab** with collapsible category sections (`DisclosureGroup`, DeepSeek Flash expanded by default) and per-target model cards.
- Each card shows display name, status badge, progress row (linear progress + Size/Speed/ETA stat slots), file status, and Download/Resume/Cancel actions.
- Empty state ("No Models Available") when `availableTargets` is empty.

### HuggingFaceTokenSection

- HF token management UI at the top of Downloads: "Set Token" button opens a popover with a `SecureField`; Save/Clear.
- Token is stored via `ConfigTokenStore()` (file-backed `hfToken` in `config.json` with static in-memory cache) and mirrored into `serverManager.config.hfToken` so argument building stays consistent.
- `loadToken()` considers a token present if `ConfigTokenStore.exists()` OR `serverManager.config.hfToken != nil`.

### ModelPickerView

- Lists all discovered main GGUF models; tapping calls `modelManager.selectModel()` and updates `config.modelPath`.
- Empty state shows "No models found — download one" with an "Open Downloader" action.
- Refresh button to rescan the models directory.

### MtpModelPickerView

- Lists MTP models (`.gguf` files containing "mtp") and updates `config.mtpModelPath` on selection.

### FolderPicker

- `NSViewControllerRepresentable` wrapping `NSOpenPanel` configured for directory selection only (`canChooseDirectories = true`). Used by DS4 Build import and the models-directory picker.
- Completion handler feeds into `ProjectImportManager.importFrom(url:)` or `PathResolver.setCustomModelsDirectory(url)`.

### LogView

- Monospaced, scrollable log viewer using `LazyVStack` + `ScrollViewReader` with a selectable font family/size (from the Interface settings).
- Each line rendered with `LogLevel.color` and `.textSelection(.enabled)`.
- Auto-scroll toggle (default on) with scroll-to-bottom and auto-scroll controls; Copy button copies all lines.
- Uses `.defaultScrollAnchor(.bottom)` for smooth auto-scroll.

### TrayMenu

- `VStack` with sections separated by `Divider`:
  - **Status** — colored dot + server status label
  - **Model Info** — selected model name (and MTP model if enabled), truncated
  - **Throughput** — prefill t/s, gen t/s, context usage (when running/starting)
  - **Controls** — Start/Stop/Restart with disable logic
  - **Quick Actions** — Open Models Folder, Open Config File, Open Logs, Settings (opens main window)
  - **Show** — "Show DwarfStarLauncher" with `Command+S`
  - **Quit** — Quit DwarfStarLauncher
