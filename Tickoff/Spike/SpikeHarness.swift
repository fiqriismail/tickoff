import Foundation
import FoundationModels
import HuggingFace
import MLX
import MLXFoundationModels
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

// THROWAWAY (issue #67): measures Apple's model and MLX candidates on the same scripted
// tool-call prompts. Not shipped UI; delete once the results are in `brain/docs/ai-assistant.md`.
// Run from a terminal, one Mac at a time:
//   TICKOFF_SPIKE=system,qwen3_1_7b_4bit,qwen3_4b_4bit,qwen3_8b_4bit \
//     Tickoff.app/Contents/MacOS/Tickoff | tee spike-<mac>.md

// MARK: - Stub tools (record the call, change nothing)

/// Collects the tool calls a prompt made; tools only record, so no database is involved.
actor CallRecorder {
    private(set) var calls: [(name: String, args: String)] = []
    func record(_ name: String, _ args: String) { calls.append((name, args.lowercased())) }
    func reset() { calls = [] }
}

@Generable struct AddTaskArgs {
    @Guide(description: "Short task title") var title: String
    @Guide(description: "Project name; omit for Inbox") var project: String?
    @Guide(description: "low, medium or high; omit if not said") var priority: String?
}

@Generable struct SetStatusArgs {
    @Guide(description: "Id of an existing task") var taskID: Int
    @Guide(description: "todo, in_progress or done") var status: String
}

@Generable struct MoveTaskArgs {
    @Guide(description: "Id of an existing task") var taskID: Int
    @Guide(description: "Name of the destination project") var project: String
}

@Generable struct DeleteTaskArgs {
    @Guide(description: "Id of an existing task") var taskID: Int
}

@Generable struct GoalArgs {
    @Guide(description: "Name of an existing daily goal") var goal: String
    @Guide(description: "up to add progress, down to remove it") var direction: String
}

struct AddTaskTool: FoundationModels.Tool {
    let recorder: CallRecorder
    let name = "add_task"
    let description = "Add a new task."
    func call(arguments a: AddTaskArgs) async throws -> String {
        await recorder.record(name, "title=\(a.title) project=\(a.project ?? "") priority=\(a.priority ?? "")")
        return "Proposed."
    }
}

struct SetStatusTool: FoundationModels.Tool {
    let recorder: CallRecorder
    let name = "set_task_status"
    let description = "Change the status of an existing task."
    func call(arguments a: SetStatusArgs) async throws -> String {
        await recorder.record(name, "taskid=\(a.taskID) status=\(a.status)")
        return "Proposed."
    }
}

struct MoveTaskTool: FoundationModels.Tool {
    let recorder: CallRecorder
    let name = "move_task"
    let description = "Move an existing task to another project."
    func call(arguments a: MoveTaskArgs) async throws -> String {
        await recorder.record(name, "taskid=\(a.taskID) project=\(a.project)")
        return "Proposed."
    }
}

struct DeleteTaskTool: FoundationModels.Tool {
    let recorder: CallRecorder
    let name = "delete_task"
    let description = "Delete an existing task."
    func call(arguments a: DeleteTaskArgs) async throws -> String {
        await recorder.record(name, "taskid=\(a.taskID)")
        return "Proposed."
    }
}

struct GoalProgressTool: FoundationModels.Tool {
    let recorder: CallRecorder
    let name = "change_goal_progress"
    let description = "Add or remove one unit of today's progress on a daily goal."
    func call(arguments a: GoalArgs) async throws -> String {
        await recorder.record(name, "goal=\(a.goal) direction=\(a.direction)")
        return "Proposed."
    }
}

// MARK: - Scripted prompts

struct SpikeCase {
    let prompt: String
    /// nil: the model must not call any tool. Otherwise the one expected call.
    let expected: (tool: String, contains: [String])?
}

enum SpikeScript {
    static let instructions = """
        You manage the user's tasks. Use the tools to propose changes; never claim a change \
        is done without calling a tool. Answer other questions briefly.
        Projects: Inbox, Work, Personal.
        Tasks (id: title, project, status):
        1: Buy groceries, Inbox, todo
        2: Write quarterly report, Work, in_progress
        3: Call dentist, Inbox, todo
        4: Fix login bug, Work, todo
        5: Plan holiday, Personal, todo
        6: Renew passport, Personal, todo
        7: Review pull requests, Work, todo
        8: Book flights, Personal, done
        Daily goals: Meditate (check-off), Drink water (counter, target 8).
        """

    static let cases: [SpikeCase] = [
        .init(prompt: "Add a task to buy milk", expected: ("add_task", ["milk"])),
        .init(prompt: "Remind me to email Sam, high priority", expected: ("add_task", ["email sam", "priority=high"])),
        .init(prompt: "Add 'Prepare slides' to my Work project", expected: ("add_task", ["prepare slides", "project=work"])),
        .init(prompt: "Mark the dentist task as done", expected: ("set_task_status", ["taskid=3", "status=done"])),
        .init(prompt: "Start working on fixing the login bug", expected: ("set_task_status", ["taskid=4", "status=in_progress"])),
        .init(prompt: "I finished reviewing pull requests", expected: ("set_task_status", ["taskid=7", "status=done"])),
        .init(prompt: "Move the passport task to Work", expected: ("move_task", ["taskid=6", "project=work"])),
        .init(prompt: "Put Buy groceries in Personal", expected: ("move_task", ["taskid=1", "project=personal"])),
        .init(prompt: "Delete the book flights task", expected: ("delete_task", ["taskid=8"])),
        .init(prompt: "Remove Call dentist", expected: ("delete_task", ["taskid=3"])),
        .init(prompt: "I drank a glass of water", expected: ("change_goal_progress", ["drink water", "direction=up"])),
        .init(prompt: "I meditated today", expected: ("change_goal_progress", ["meditate", "direction=up"])),
        .init(prompt: "Undo my last water entry", expected: ("change_goal_progress", ["drink water", "direction=down"])),
        .init(prompt: "Reopen the flights task", expected: ("set_task_status", ["taskid=8", "status=todo"])),
        .init(prompt: "Add a low priority task to renew car insurance in Personal", expected: ("add_task", ["car insurance", "priority=low", "project=personal"])),
        .init(prompt: "What is the capital of France?", expected: nil),
        .init(prompt: "Thanks!", expected: nil),
        .init(prompt: "Mark the quarterly report as done", expected: ("set_task_status", ["taskid=2", "status=done"])),
        .init(prompt: "Move Fix login bug to Personal", expected: ("move_task", ["taskid=4", "project=personal"])),
        .init(prompt: "Add a task to water the plants", expected: ("add_task", ["water the plants"])),
    ]
}

// MARK: - Runner

@available(macOS 27.0, *)
enum SpikeHarness {
    /// MLX candidates by the name accepted in `TICKOFF_SPIKE`.
    static let mlxModels: [String: ModelConfiguration] = [
        "qwen3_1_7b_4bit": LLMRegistry.qwen3_1_7b_4bit,
        "qwen3_5_2b_4bit": LLMRegistry.qwen3_5_2b_4bit,
        "qwen3_4b_4bit": LLMRegistry.qwen3_4b_4bit,
        "qwen3_8b_4bit": LLMRegistry.qwen3_8b_4bit,
    ]

    struct Result {
        var name: String
        var downloadBytes: Int?
        var loadSeconds: Double
        var tokensPerSecond: Double
        var peakMLXBytes: Int?
        var peakFootprintBytes: Int
        var passed: Int
        var total: Int
        var failures: [String]
    }

    /// Runs the requested models (comma separated) and prints a Markdown report to stdout.
    static func run(spec: String) async {
        print("# Spike results")
        print("- Chip: \(chipName()), RAM: \(gigabytes(Int(ProcessInfo.processInfo.physicalMemory))) GB, "
            + "GPU budget: \(GPU.maxRecommendedWorkingSetBytes().map(gigabytes) ?? "n/a") GB, "
            + "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        var results: [Result] = []
        for name in spec.split(separator: ",").map({ String($0).trimmingCharacters(in: .whitespaces) }) {
            print("\n(running \(name)…)")
            fflush(stdout)
            if let result = await measure(name) { results.append(result) }
        }
        print("\n| Model | Download | Load s | Tokens/s | Peak MLX | Peak footprint | Tool calls |")
        print("|---|---|---|---|---|---|---|")
        for r in results {
            print("| \(r.name) | \(r.downloadBytes.map(gigabytes).map { "\($0) GB" } ?? "n/a") "
                + "| \(String(format: "%.1f", r.loadSeconds)) | \(String(format: "%.1f", r.tokensPerSecond)) "
                + "| \(r.peakMLXBytes.map(gigabytes).map { "\($0) GB" } ?? "n/a") "
                + "| \(gigabytes(r.peakFootprintBytes)) GB | \(r.passed)/\(r.total) |")
        }
        for r in results where !r.failures.isEmpty {
            print("\n\(r.name) misses:")
            r.failures.forEach { print("- \($0)") }
        }
        fflush(stdout)
    }

    private static func measure(_ name: String) async -> Result? {
        let recorder = CallRecorder()
        let tools: [any FoundationModels.Tool] = [
            AddTaskTool(recorder: recorder), SetStatusTool(recorder: recorder),
            MoveTaskTool(recorder: recorder), DeleteTaskTool(recorder: recorder),
            GoalProgressTool(recorder: recorder),
        ]
        let model: any FoundationModels.LanguageModel
        var downloadBytes: Int?
        var loadSeconds = 0.0
        Memory.peakMemory = 0
        if name == "system" {
            let system = SystemLanguageModel.default
            guard case .available = system.availability else {
                print("Apple's model is unavailable: \(system.availability)")
                return nil
            }
            model = system
        } else if let configuration = mlxModels[name] {
            let mlx = MLXLanguageModel(
                configuration: configuration,
                capabilities: [.toolCalling, .guidedGeneration],
                weightsLocation: { id in
                    let cache = HubCache.default
                    guard let repo = Repo.ID(rawValue: id) else { return cache.cacheDirectory }
                    return cache.repoDirectory(repo: repo, kind: .model)
                },
                load: { configuration, progress in
                    try await loadModelContainer(
                        from: #hubDownloader(), using: #huggingFaceTokenizerLoader(),
                        configuration: configuration, progress: progress)
                })
            let start = ContinuousClock.now
            do { try await mlx.preload() } catch {
                print("Could not load \(name): \(error.localizedDescription)")
                return nil
            }
            loadSeconds = seconds(since: start)
            if let repo = Repo.ID(rawValue: configuration.name) {
                downloadBytes = blobBytes(HubCache.default.repoDirectory(repo: repo, kind: .model))
            }
            model = mlx
        } else {
            print("Unknown model \(name)")
            return nil
        }

        var passed = 0
        var failures: [String] = []
        var outputTokens = 0
        var generating = 0.0
        for item in SpikeScript.cases {
            await recorder.reset()
            let session = LanguageModelSession(model: model, tools: tools, instructions: SpikeScript.instructions)
            let start = ContinuousClock.now
            do {
                let response = try await session.respond(to: item.prompt)
                outputTokens += response.usage.output.totalTokenCount
            } catch {
                failures.append("“\(item.prompt)” threw \(error.localizedDescription)")
                generating += seconds(since: start)
                continue
            }
            generating += seconds(since: start)
            let calls = await recorder.calls
            if Self.matches(item.expected, calls) {
                passed += 1
            } else {
                let got = calls.map { "\($0.name)(\($0.args))" }.joined(separator: "; ")
                failures.append("“\(item.prompt)” expected \(item.expected?.tool ?? "no tool"), got \(got.isEmpty ? "no tool" : got)")
            }
        }
        return Result(
            name: name, downloadBytes: downloadBytes, loadSeconds: loadSeconds,
            tokensPerSecond: generating > 0 ? Double(outputTokens) / generating : 0,
            peakMLXBytes: name == "system" ? nil : Memory.peakMemory,
            peakFootprintBytes: footprintBytes(), passed: passed, total: SpikeScript.cases.count,
            failures: failures)
    }

    private static func matches(_ expected: (tool: String, contains: [String])?, _ calls: [(name: String, args: String)]) -> Bool {
        guard let expected else { return calls.isEmpty }
        guard calls.count == 1, let call = calls.first, call.name == expected.tool else { return false }
        return expected.contains.allSatisfy { call.args.contains($0) }
    }

    // MARK: Measurement helpers

    private static func seconds(since start: ContinuousClock.Instant) -> Double {
        let d = start.duration(to: .now)
        return Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
    }

    private static func gigabytes(_ bytes: Int) -> String { String(format: "%.2f", Double(bytes) / 1_073_741_824) }

    private static func chipName() -> String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0)
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// The process's physical footprint, the number Activity Monitor reports as Memory.
    private static func footprintBytes() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return status == KERN_SUCCESS ? Int(info.phys_footprint) : 0
    }

    /// Sum of the downloaded blobs (the snapshot folder only holds links to them).
    private static func blobBytes(_ repoDirectory: URL) -> Int {
        let blobs = repoDirectory.appendingPathComponent("blobs")
        let files = (try? FileManager.default.contentsOfDirectory(at: blobs, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }
}
