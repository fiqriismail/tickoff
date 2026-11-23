import Foundation
import FoundationModels

@testable import Tickoff

/// A deterministic `LanguageModel` for tests: each turn calls one tool, and once that tool's output is the
/// last transcript entry it answers with `reply`. `delay` makes a turn slow, so cancelling can be tested. `MLXScriptedLM` can't do this yet (its README lists
/// tool calls as planned), and linking MLX into the test bundle would load it twice.
@available(macOS 27.0, *)
struct ScriptedLanguageModel: LanguageModel {
    typealias Executor = ScriptedExecutor

    var toolName: String
    var arguments: String
    var reply: String
    var delay: Duration = .zero
    /// Answers the first prompt with a claim of having proposed something, without calling the tool.
    var claimsWithoutTool = false

    var capabilities: LanguageModelCapabilities { LanguageModelCapabilities([.toolCalling]) }
    var executorConfiguration: ScriptedExecutor.Configuration {
        .init(
            toolName: toolName, arguments: arguments, reply: reply, delay: delay, claimsWithoutTool: claimsWithoutTool)
    }
}

@available(macOS 27.0, *)
struct ScriptedExecutor: LanguageModelExecutor {
    typealias Model = ScriptedLanguageModel

    struct Configuration: Hashable, Sendable {
        var toolName: String
        var arguments: String
        var reply: String
        var delay: Duration
        var claimsWithoutTool: Bool
    }

    let configuration: Configuration

    init(configuration: Configuration) throws {
        self.configuration = configuration
    }

    nonisolated(nonsending) func respond(
        to request: LanguageModelExecutorGenerationRequest, model: ScriptedLanguageModel,
        streamingInto channel: LanguageModelExecutorGenerationChannel
    ) async throws {
        try await _Concurrency.Task.sleep(for: configuration.delay)
        let prompts = request.transcript.filter { if case .prompt = $0 { true } else { false } }.count
        if configuration.claimsWithoutTool, prompts == 1 {
            await channel.send(.response(action: .appendText("I’ve proposed that.", tokenCount: 1)))
            return
        }
        let toolHasRun: Bool
        if case .toolOutput? = request.transcript.last { toolHasRun = true } else { toolHasRun = false }
        if toolHasRun {
            await channel.send(.response(action: .appendText(configuration.reply, tokenCount: 1)))
        } else {
            await channel.send(
                .toolCalls(
                    action: .toolCall(
                        id: "call-1", name: configuration.toolName,
                        action: .appendArguments(configuration.arguments, tokenCount: 1))))
        }
    }
}
