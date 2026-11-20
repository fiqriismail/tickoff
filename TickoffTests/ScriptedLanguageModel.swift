import Foundation
import FoundationModels

@testable import Tickoff

/// A deterministic `LanguageModel` for tests: its first turn calls one tool, and once the tool's output
/// is in the transcript it answers with `reply`. `MLXScriptedLM` can't do this yet (its README lists
/// tool calls as planned), and linking MLX into the test bundle would load it twice.
@available(macOS 27.0, *)
struct ScriptedLanguageModel: LanguageModel {
    typealias Executor = ScriptedExecutor

    var toolName: String
    var arguments: String
    var reply: String

    var capabilities: LanguageModelCapabilities { LanguageModelCapabilities([.toolCalling]) }
    var executorConfiguration: ScriptedExecutor.Configuration {
        .init(toolName: toolName, arguments: arguments, reply: reply)
    }
}

@available(macOS 27.0, *)
struct ScriptedExecutor: LanguageModelExecutor {
    typealias Model = ScriptedLanguageModel

    struct Configuration: Hashable, Sendable {
        var toolName: String
        var arguments: String
        var reply: String
    }

    let configuration: Configuration

    init(configuration: Configuration) throws {
        self.configuration = configuration
    }

    nonisolated(nonsending) func respond(
        to request: LanguageModelExecutorGenerationRequest, model: ScriptedLanguageModel,
        streamingInto channel: LanguageModelExecutorGenerationChannel
    ) async throws {
        let toolHasRun = request.transcript.contains {
            if case .toolOutput = $0 { true } else { false }
        }
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
