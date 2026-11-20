# On-device AI assistant (plan)

Status: **planned** (20-11-2026). Decisions confirmed by the owner; tracked by GitHub milestone
**On-device assistant** (#6), issues #66–#73. Nothing implemented yet.

An assistant panel where the user chats with an on-device model that can find, create,
edit, complete and move tasks and update Daily Goals progress. **Apple's built-in model is
the default**; the user can instead download an open-source model from a curated list, run
with **MLX Swift**. No cloud API; the only network use is downloading MLX weights.

## Reference (the source of truth)

MLX Swift's documentation is the reference for every MLX decision. When this plan and
the docs disagree, the docs win and this plan is updated.

- MLX: <https://swiftpackageindex.com/ml-explore/mlx-swift/main/documentation/mlx>
  (source: `ml-explore/mlx-swift`, `Source/MLX/Documentation.docc`). Read: Installation,
  Troubleshooting, Lazy Evaluation, Unified Memory, Using Streams, Wired Memory.
- MLX Swift LM: <https://swiftpackageindex.com/ml-explore/mlx-swift-lm/main/documentation/mlxlmcommon>
  (`using`, `upgrade`, `model-compatibility`, `wired-memory`), plus the
  `Libraries/MLXFoundationModels` and `MLXScriptedLM` READMEs/DocC.
- Apple: Foundation Models framework, and the WWDC26 session "Bring an LLM provider to the
  Foundation Models framework".
- Checked on 20-11-2026 against `mlx-swift` **0.33.0** and `mlx-swift-lm` **3.33.0**.
  Re-read the docs whenever a pinned version changes.

### What the docs settle

- **One API for both models.** `MLXFoundationModels.MLXLanguageModel` conforms to Apple's
  `FoundationModels.LanguageModel`, so a `LanguageModelSession` runs on either
  `SystemLanguageModel.default` or an MLX model. Tools (`Tool`), structured output
  (`@Generable`) and streaming are the same code. We don't write our own agent loop or
  tool-call parser.
- **That bridge needs the macOS 27 SDK and macOS 27 at runtime.** On older SDKs the module
  compiles empty. Xcode 27 is already in use, so the SDK is fine; the runtime check is
  `if #available(macOS 27, *)`.
- **MLX capabilities are declared, not inferred.** Construct with
  `capabilities: [.toolCalling, .guidedGeneration]`; a request beyond them fails with a typed error.
- **`MLXLanguageModel.availability`** reports `.available`, `.downloading` or
  `.unavailable(.deviceNotCapable | .modelNotDownloaded | .downloadFailed)`, which drives the panel state.
- **Build:** add packages in Xcode; the Metal shaders build only with Xcode/`xcodebuild`
  (not command-line SwiftPM). `release.sh` and the documented `xcodebuild` commands already
  qualify. MLX is linked as a library, so only the app target may link it (two copies of
  MLX in one process break).
- **Package traits:** `mlx-swift`'s `JACCL` (distributed over Thunderbolt 5) is on by
  default and unused here; disable it if Xcode lets us set traits on the dependency
  (it stays on if any dependent requests defaults). `mlx-swift-lm`'s
  `FoundationModelsIntegration` must stay **on** (default).
- **Downloader/tokenizer:** mlx-swift-lm 3.x is decoupled from them. Use the
  `MLXHuggingFace` integration (`swift-huggingface` + `swift-transformers`), but call the
  `MLXLanguageModel` initializer directly with our own `weightsLocation:` so weights live
  under `~/Library/Application Support/Tickoff/Models/` and can be listed and deleted.
- **Concurrency:** `MLXArray` is not `Sendable`; only evaluated `MaterializedArray`
  snapshots cross actors. We never touch `MLXArray`: all MLX use stays inside the bridge.
  Default device/stream scopes are task-local and don't carry into `Task.detached`.
- **Memory:** use `WiredMemoryManager.shared` with a `.reservation` ticket for loaded
  weights and an `.active` ticket (`withWiredLimit`) per generation. Never set the wired
  limit directly. `GPU.maxRecommendedWorkingSetBytes()` decides which models a Mac is
  offered. Unload the model when idle.
- **Tests:** `MLXScriptedLM` provides scripted tokenizers and models, so generation can be
  tested without weights.

## Decisions (20-11-2026)

| Topic | Choice | Reason |
|---|---|---|
| Minimum OS | **macOS 26 Tahoe** for the whole app | Owner's requirement; Foundation Models exists from 26 |
| MLX models | **macOS 27 and later** (`#available`) | The MLX ↔ Foundation Models bridge needs 27; on 26 only Apple's model is offered |
| Architecture | **Apple Silicon only** (arm64) | Apple Intelligence and MLX both require it |
| Default model | Apple's on-device model (`SystemLanguageModel.default`) | No download, works immediately where Apple Intelligence is on |
| Optional models | Curated list from `LLMRegistry`, downloaded on demand | User choice; we vet each for tool calling |
| Agent API | Foundation Models (`LanguageModelSession`, `Tool`, `@Generable`) for both models | One code path, documented by MLX's bridge |
| Scope v1 | Chat that acts on tasks and projects, plus Daily Goals progress | Owner's choice |
| Writes | **Propose, then confirm** | Small models guess wrong; nothing changes until approved |

### Curated MLX model list (to confirm in the spike)

From `LLMRegistry` in mlx-swift-lm 3.33.0, all 4-bit:

| Label | Registry entry | Approx. download | Offer when (macOS 27+) |
|---|---|---|---|
| Small | `qwen3_1_7b_4bit` (or `qwen3_5_2b_4bit`) | ~1 GB | 8 GB+ |
| Balanced | `qwen3_4b_4bit` | ~2.3 GB | 16 GB+ (tight on 8 GB) |
| Large | `qwen3_8b_4bit` | ~4.5 GB | 24 GB+ (tight on 16 GB) |

The list is a fixed enum in code (stored key never changes), not free-form Hugging Face ids.
"Offer when" is decided by the hardware check below, not by these rough numbers.

### Hardware validation (before any download)

Each `ModelChoice` carries `downloadBytes` and `peakMemoryBytes` (weights + KV cache at our
context length + overhead), measured in the spike, not guessed. A pure function decides
eligibility from a `HardwareProfile`, so it's unit-tested with fake Macs:

```swift
enum Eligibility { case recommended, tight(String), blocked(String) }
func eligibility(of model: ModelChoice, on mac: HardwareProfile) -> Eligibility
```

`HardwareProfile.current` reads everything in one place, with Metal and `sysctl` rather than
MLX, so the check also runs on macOS 26 and in tests:

| Fact | Source | Used for |
|---|---|---|
| Chip name and generation (M1…M5, base/Pro/Max/Ultra) | `sysctlbyname("machdep.cpu.brand_string")` | Shown in the picker; "may be slow" note |
| Physical RAM | `ProcessInfo.processInfo.physicalMemory` | Shown in the picker |
| GPU memory budget | `MTLDevice.recommendedMaxWorkingSetSize` (the value MLX's `GPU.maxRecommendedWorkingSetBytes()` reports) | **Hard limit** |
| Metal GPU family | `MTLDevice.supportsFamily(_:)` | **Hard limit** (MLX needs a modern Apple GPU family) |
| Free disk space | `volumeAvailableCapacityForImportantUsage` on the Models folder | **Hard limit** |

Rules (thresholds confirmed in the spike):

- **Blocked** (Download disabled, reason shown) if `peakMemoryBytes` > 70% of the GPU
  budget, the GPU family is unsupported, or free disk < `downloadBytes` + 2 GB. No override.
- **Tight** (allowed, with a warning and a confirmation) if peak memory > 50% of the budget,
  or the chip is a base M1/M2 and the model is Balanced or Large ("works, but replies will be slow").
- **Recommended** otherwise. The picker preselects the largest recommended model.
- Chip generation only adjusts speed warnings; memory, GPU family and disk are the hard gates.
  A 16 GB M1 can still run the Balanced model, just more slowly.

Checks run again right before downloading (disk may have filled) and before loading. At
load time, MLX's wired-memory admission (`canAdmit` on the policy) refuses to start if
memory isn't available, and the error is shown in the panel instead of crashing. Expected
outcome on today's thresholds: 8 GB Macs get Small (Balanced tight, Large blocked);
16 GB Macs get Small and Balanced (Large tight); 24 GB+ get all three.

### Consequences of the OS bump

- `MACOSX_DEPLOYMENT_TARGET` 14.0 → 26.0; `release.sh` defaults to `ARCHS="arm64"`. Users on
  Sonoma/Sequoia or Intel Macs keep the last compatible release; tag it
  (e.g. `v<version>-sonoma`) and say so on the website.
- The database is untouched: same file, same migration rules.
- `AGENTS.md`, `README.md` and the website requirements change in the same PR.
- New dependencies (an architectural decision, recorded here): `mlx-swift-lm` (brings
  `mlx-swift`, `swift-syntax` for macros), `swift-huggingface`, `swift-transformers`.

## Architecture

```
Tickoff/Features/Assistant/
  AssistantView.swift        inspector panel: transcript, input, proposal cards, model status
  AssistantModel.swift       @MainActor @Observable: session, transcript, pending proposals
  AssistantTools.swift       Foundation Models `Tool`s; reads from passed-in data, writes only proposals
  Proposal.swift             a pending change (create/update/status/move/delete task, goal progress)
  ModelChoice.swift          enum: .apple + curated MLX models; label, download and peak memory bytes
  HardwareProfile.swift      chip, RAM, GPU budget, GPU family, free disk; `eligibility(of:on:)`
  ModelProvider.swift        the ONLY file that imports MLX: builds the `LanguageModel`,
                             download/delete/availability, wired-memory tickets, idle unload
```

- **Features never import each other.** `ContentView` passes the assistant the `TaskSet`,
  visible projects, today's goals, the stores and a `report` closure. Applying proposals
  returns an `Outcome`; the shell reloads on `.changed`.
- **SQL stays in its stores.** Tools read the in-memory `TaskSet` / projects /
  `DailyGoalsModel` (no queries per turn). Approved proposals are applied in one
  transaction via `in db:` static helpers on `TaskStore`, `ProjectStore` and
  `DailyGoalStore` (the `deleteTasks` pattern) inside one `queue.write`.
- **Settings** (`settings` table, unknown values fall back to defaults): `assistant_model`
  (`apple` or a `ModelChoice` key). No Settings window: the model picker, download and
  delete live in the panel and the menu bar.

### Agent behaviour

1. Session instructions: today's date and weekday, the Status/Priority vocabulary, project
   names and ids (task projects and daily-goal projects), "use tools; never invent ids".
2. Tools:
   - Read: `SearchTasks(query?, status?, project?, dueBefore?)`, `GetTask(id)`,
     `ListProjects`, `TodaysGoals`. Results capped (count and characters): Apple's model
     has a small context window, and 10,000 tasks must never flood it.
   - Propose: `CreateTask`, `UpdateTask`, `SetTaskStatus`, `MoveTask`, `DeleteTask`,
     `ChangeGoalProgress`. Arguments are `@Generable`, so output is constrained to the
     schema. They validate ids/values against current data and return "proposed #n"; they
     never write.
3. The panel shows proposals as cards: **Apply all**, **Apply** / **Discard** each. Applying
   re-validates against the reloaded `TaskSet`.
4. The transcript is in memory only for v1. When the context fills, start a new session
   with a short summary.
5. Unavailable states are explained: Apple Intelligence off or not supported, Apple model
   not ready, MLX model not downloaded/failed.

### UI

- `.inspector` on the right, toggled by a toolbar button and View ▸ Show Assistant.
- Model picker in the panel header: Apple (default) plus the curated list with size and a
  memory note; Download (progress, cancel), Delete, and which model is active.
- **On macOS 26 the curated MLX list is not shown**; the picker offers Apple's model only.
  On macOS 27 and later the list appears. The choices come from a pure
  `ModelChoice.available(onMacOS27OrLater:)`, so both cases are unit-tested. A stored MLX
  choice on a Mac that's back on 26 (or blocked by hardware) falls back to Apple's model.
- Semantic styles only; proposal cards reuse task-row visuals copied into the Assistant folder.

## Milestone: On-device assistant

1. **#66 Require macOS 26 and Apple Silicon:** deployment target, `release.sh` arm64 default,
   tag the last compatible release, README/AGENTS/website requirements. *Do first.*
2. **#67 Spike: Foundation Models plus MLX bridge:** add the packages (traits as above), run the
   same 20 scripted tool-call prompts on Apple's model and on 2–3 MLX candidates. Measure
   load time, tokens/s, peak memory and tool accuracy on 8 GB and 16 GB Macs (base M1 or
   M2 included). Output: the curated list with measured `downloadBytes`/`peakMemoryBytes`,
   validated eligibility thresholds, pinned versions, findings written back into this doc.
   *Blocks 4–7.*
3. **#68 Proposal apply path:** `in db:` store helpers, one-transaction batch apply, tests on
   the in-memory database. *Independent.*
4. **#69 Assistant tools:** `Tool` implementations and proposal validation, tested by calling
   the tools directly (no model), plus a scripted-model test with `MLXScriptedLM`. *Depends on 2, 3.*
5. **#70 Hardware validation:** `HardwareProfile` and `eligibility(of:on:)`, tested with
   fake 8/16/24 GB, base/Pro chip and low-disk profiles. Blocked models can't be downloaded
   or loaded. *Depends on 2.*
6. **#71 Model provider and picker:** `ModelChoice`, the MLX list shown only on macOS 27+,
   availability, download/delete in
   Application Support, eligibility shown per model (recommended / tight / blocked with
   reason), re-checks before download and load, wired-memory tickets, idle unload,
   `assistant_model` setting with fallback tests (a stored model that's now blocked falls
   back to Apple's model). *Depends on 5.*
7. **#72 Assistant panel:** inspector UI, streaming, proposal cards, menu command and toolbar,
   shell wiring. *Depends on 4, 6.*
8. **#73 User documentation:** website guide (Apple Intelligence requirement, choosing and
   downloading a model, sizes, privacy: everything on-device, approving changes), landing
   page, requirements, screenshots. *Depends on 7.*

## Risks

- **MLX needs macOS 27:** Tahoe users only get Apple's model (owner's decision,
  20-11-2026: keep Tahoe as the minimum, offer MLX models on 27+).
- **Apple Intelligence may be off or unavailable:** then the assistant needs an MLX model
  (27+) or stays unavailable with a clear reason.
- **Small-model accuracy:** guided generation constrains the shape, not the meaning; tools
  validate, and proposals are reviewed.
- **Memory on 8 GB Macs:** hardware validation blocks models that would not fit and warns on tight ones;
  unload when idle.
- **API churn** (mlx-swift-lm is moving fast; 3.x already broke 2.x): pin exact versions,
  keep MLX in `ModelProvider.swift`, re-read the docs on every bump.
