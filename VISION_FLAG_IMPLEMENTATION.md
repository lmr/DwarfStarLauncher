# Vision Encoder Flag Implementation Guide

## Goal

Add optional DeepSeek/GLM vision-encoder support to DwarfStarLauncher by making
the app emit this argument when a sidecar has been selected:

```text
--vision /path/to/DeepSeek-V4-Flash-Vision-Encoder.gguf
```

The existing launcher only manages `ds4-server`, so the required change is to
persist the encoder path, expose it in Settings, and include it in
`ServerConfig.buildArguments()`.

Use `visionEncoderPath` as the Swift/config name throughout this guide. Keep it
optional: an empty or missing value must preserve the current text-only launch
behavior.

## Important ds4 contract

The encoder is a sidecar, not a standalone language model:

- `modelPath` must point to the matching Vision-Exp language GGUF.
- `visionEncoderPath` points to `DeepSeek-V4-Flash-Vision-Encoder.gguf`.
- A normal DeepSeek V4 Flash 0731 text checkpoint must not be paired with this
  encoder; ds4 rejects that combination.
- The encoder is passed with `--vision`, never with `--model`.
- Vision requires a GPU-enabled ds4 build; a CPU-only build cannot run it.
- For Vision-Exp DSpark, use the matching
  `DeepSeek-V4-Flash-Vision-Exp-DSpark-support.gguf`, not the ordinary 0731
  DSpark support model.

The reference launch shape is:

```sh
ds4-server \
  --model /models/DeepSeek-V4-Flash-Vision-Exp-IQ2XXS-w2Q2K-AProjQ8-SExpQ8-OutQ8.gguf \
  --vision /models/DeepSeek-V4-Flash-Vision-Encoder.gguf \
  --ctx 32768
```

The authoritative ds4-side examples are in the sibling engine repository's
`README.md` under “DeepSeek V4 Flash Vision Experimental”.

## Current launcher gaps

These are the files that need to change:

- `Sources/App/Models/ServerConfig.swift` — no encoder-path field and no
  `--vision` emission.
- `Sources/App/Views/ConfigOverlayView.swift` — the local Settings mirror does
  not load, display, or save an encoder path.
- `Sources/App/Services/ModelManager.swift` — every `.gguf` that is not MTP or
  DSpark is currently classified as a main model, so the encoder would appear
  in the main-model picker.
- `Tests/AppTests/ServerConfigTests.swift` — no flag or backward-compatibility
  coverage.
- `Tests/AppTests/FileSystemServicesTests.swift` — no vision-encoder model
  classification coverage.

`ServerManager` already obtains its process arguments from
`launchConfig.buildArguments()`, so no new `Process` plumbing is needed for the
minimum implementation.

## Phase 1: implement the flag and manual sidecar selection

### 1. Extend `ServerConfig`

In `Sources/App/Models/ServerConfig.swift`:

1. Add an optional property near `modelPath`:

   ```swift
   var visionEncoderPath: String?
   ```

   Give it a `nil` default, either inline or through the existing initializer.

2. Add `visionEncoderPath` to `CodingKeys`.

3. In `init(from:)`, decode it with `decodeIfPresent`. Missing keys must decode
   as `nil`, so existing `config.json` files remain valid.

4. In `buildArguments()`, append the flag after `--model` and before the other
   runtime arguments when the trimmed path is non-empty:

   ```swift
   if let path = visionEncoderPath?.trimmingCharacters(in: .whitespacesAndNewlines),
      !path.isEmpty {
       args.append(contentsOf: ["--vision", path])
   }
   ```

   Store absolute paths from the picker. If manually entered paths may contain
   `~`, expand them before launching or require an absolute path; `Process`
   does not perform shell tilde expansion.

Do not automatically emit `--vision` merely because a filename contains the
word `vision`. The user-selected path must be explicit, and ds4 itself is the
authority on whether the main model and sidecar are compatible.

### 2. Keep the sidecar out of the main-model list

Update `Sources/App/Services/ModelManager.swift`:

1. Add:

   ```swift
   var visionModels: [GGUFModel] = []
   var selectedVisionModel: GGUFModel? = nil
   ```

2. Classify a file as a vision encoder when its filename contains
   `vision-encoder` case-insensitively. This covers both the DeepSeek and GLM
   encoder naming used by ds4, while leaving the main `Vision-Exp` language
   model in the normal model list.

3. Build `visionModels` separately, then exclude those files from `models` and
   from `mtpModels`.

4. When the models directory is missing or scanning fails, clear all three
   arrays, not just `models`.

5. Add `selectVisionModel(_:)` and `selectVisionModel(byPath:)`, mirroring the
   existing main-model and MTP selection helpers. Continue resolving symlinks
   for path comparisons.

A filename check is appropriate for the picker only. Do not use it as a
replacement for ds4's GGUF metadata validation.

### 3. Add the encoder picker to Settings

In `Sources/App/Views/ConfigOverlayView.swift`:

1. Add a local mirror property:

   ```swift
   @State private var localVisionEncoderPath: String? = nil
   ```

2. Load `config.visionEncoderPath` in `loadConfigIfNeeded()`.

3. Save it in `persistConfig()`.

4. Add a `VisionModelPickerView`, or generalize the existing picker into a
   reusable picker that accepts a model collection and selection callback. The
   simplest implementation is a small view parallel to
   `MtpModelPickerView`:

   - read `modelManager.visionModels`;
   - display filename and size;
   - select the row into `localVisionEncoderPath`;
   - call `modelManager.selectVisionModel(byPath:)` when the view appears;
   - offer a Refresh button;
   - show an empty state such as “No vision encoders found — place one in the
     models directory”.

5. Put the picker in the existing Model Settings section, directly below the
   main model picker. Label it clearly, for example:

   ```text
   Vision Encoder (optional)
   Used only with a matching DeepSeek Vision-Exp or GLM vision model.
   ```

6. Provide a clear/remove action that sets the local value back to `nil`. An
   empty value is the supported way to disable vision.

Do not put the encoder in the MTP section. It is not an MTP/draft model and
must not be passed through the `--mtp` or `--dspark` logic.

Because Settings uses a local config mirror and a debounced save, the picker
should update the local binding. Avoid relying on a direct mutation of
`serverManager.config` alone; the next debounced save must persist the value.

### 4. Add launch validation

The minimal change works if a missing path is passed through and ds4 reports the
error. A better user experience is to validate the configured sidecar in
`ServerManager.spawn(config:)` before starting the process:

- expand `~` if supported;
- verify the path exists and is readable;
- if it is missing, report an actionable launch error through `reportLaunchError`
  and return without spawning;
- do not silently disable the vision sidecar the way missing MTP is currently
  downgraded, because vision was explicitly selected by the user.

If you normalize the path in a temporary `launchConfig`, make sure the
normalized value is the one passed to `buildArguments()`. Keep the persisted
config unchanged unless the user explicitly saves the normalized path.

The launch log already records the complete command line, so it provides a
useful manual verification point.

## Tests to add

### `ServerConfigTests.swift`

Add coverage for:

1. Existing text-only arguments are unchanged when
   `visionEncoderPath == nil`.
2. A configured path emits exactly one `--vision` followed by that path.
3. `nil`, `""`, and whitespace-only values omit the flag.
4. A JSON config that predates this feature decodes with
   `visionEncoderPath == nil`.
5. A JSON config containing `visionEncoderPath` round-trips correctly.

For example, the expected argument prefix should be:

```swift
[
    "--model", "/tmp/vision-exp.gguf",
    "--vision", "/tmp/DeepSeek-V4-Flash-Vision-Encoder.gguf",
    "--ctx", "262144"
]
```

### `FileSystemServicesTests.swift`

Extend the seeded model directory with:

```text
DeepSeek-V4-Flash-Vision-Encoder.gguf
DeepSeek-V4-Flash-Vision-Exp-IQ2XXS.gguf
```

Assert that:

- the encoder appears only in `visionModels`;
- the Vision-Exp language model appears in `models`;
- the encoder does not appear in `mtpModels`;
- `selectVisionModel(byPath:)` selects the encoder.

Update existing count assertions to account for the new collection.

### Optional `ServerManager` integration test

Use the existing temporary executable/resolver pattern to start a tiny fake
server, configure a vision path, and assert that the launch log contains:

```text
--vision /tmp/DeepSeek-V4-Flash-Vision-Encoder.gguf
```

Also test that a missing configured sidecar produces the new actionable error
and does not start the process.

## Phase 2: optional Downloads-tab support

Do this only after Phase 1 works with manually placed files. The current
`DownloadTarget` catalog has no Vision-Exp targets, and adding a download card
is a separate concern from adding the flag.

If full download support is desired:

1. Add a compound target for each supported Vision-Exp language quantization,
   with two files: the language GGUF and
   `DeepSeek-V4-Flash-Vision-Encoder.gguf`.
2. Add a sidecar-only target if users may already have the language GGUF.
3. Use the actual Hugging Face repository filenames and sizes from the ds4
   download manifest; do not guess sizes.
4. Keep the encoder out of the main-model picker through the classification in
   Phase 1.
5. On compound-target completion, auto-select only the first language file as
   `modelPath`; set `visionEncoderPath` explicitly to the encoder file.
6. Extend `DownloadTargetsTests` and the AppDelegate download-completion tests
   for the compound-file behavior.

Avoid making the encoder a normal single-file “main model” download. That would
allow the existing completion callback to select it as `modelPath`.

## Manual verification checklist

1. Build/import a GPU-enabled ds4 build that includes `--vision` support.
2. Put a matching Vision-Exp language GGUF and the encoder GGUF in the models
   directory.
3. Open Settings and select the Vision-Exp language model under Model.
4. Select `DeepSeek-V4-Flash-Vision-Encoder.gguf` under Vision Encoder.
5. Save Settings, press Play, and inspect the first launch log line. It must
   contain both `--model <language.gguf>` and `--vision <encoder.gguf>`.
6. Send a request containing an inline PNG/JPEG image to the running server.
7. Clear the encoder selection, restart, and confirm the launch command no
   longer contains `--vision`.
8. Select a normal text-only model while leaving the encoder selected and
   confirm the UI explains that the pairing is invalid, or verify that ds4
   rejects it with its compatibility error.

For the launcher’s current import workflow, use Settings → DS4 Build → Refresh
after rebuilding ds4 so the copied `ds4-server` is not an older binary.

## Acceptance criteria

- Existing text-only configurations and tests remain unchanged.
- A selected encoder path is persisted in `config.json` as
  `visionEncoderPath`.
- A selected encoder produces exactly one `--vision <path>` argument.
- The encoder cannot be selected as the main language model.
- Clearing the selection removes the flag on the next launch.
- Missing sidecars fail with an actionable error rather than silently starting
  a misconfigured server.
- The feature is verified with a matching Vision-Exp language GGUF and the
  DeepSeek vision encoder on a GPU-enabled ds4 build.
