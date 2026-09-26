import Foundation

/// One row in the chat.
enum ChatItem: Identifiable {
    case user(id: String, text: String)
    case assistant(id: String, text: String)
    case tool(id: String, tool: AgentTool?, outcome: ToolOutcome?)

    var id: String {
        switch self {
        case .user(let id, _), .assistant(let id, _), .tool(let id, _, _): id
        }
    }
}

/// Drives the assistant: sends the conversation to Claude, runs tool calls on the phone,
/// waits for the person's approval on actions, and continues until Claude is done.
@MainActor
@Observable
final class AgentController {
    private(set) var conversation: Conversation
    private(set) var isWorking = false
    private(set) var statusText: String?
    var errorMessage: String?
    /// Consent or sign-in is needed before the assistant can run.
    var needsSetup = false

    let store: ConversationStore
    let account: AccountStore
    let connectors: ConnectorSettings
    let memory: MemoryStore

    @ObservationIgnored private let tools: DeviceTools
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var pendingText: String?

    /// Claude calls per request before pausing, as a runaway guard.
    static let maxSteps = 12
    private static let contextPrefix = "<context>"

    init(store: ConversationStore, account: AccountStore, connectors: ConnectorSettings, memory: MemoryStore) {
        self.store = store
        self.account = account
        self.connectors = connectors
        self.memory = memory
        self.tools = DeviceTools(memory: memory)
        self.conversation = store.conversations.first ?? Conversation()
    }

    // MARK: - Conversations

    func newChat() {
        stop()
        errorMessage = nil
        conversation = Conversation()
    }

    func open(_ id: UUID) {
        guard let saved = store.conversation(id) else { return }
        stop()
        errorMessage = nil
        conversation = saved
    }

    func deleteConversation(_ id: UUID) {
        store.delete(id)
        if conversation.id == id { newChat() }
    }

    // MARK: - Chat

    var items: [ChatItem] {
        var items: [ChatItem] = []
        for message in conversation.messages {
            for (index, block) in message.content.enumerated() {
                let id = "\(message.id.uuidString)-\(index)"
                switch block["type"]?.stringValue ?? "" {
                case "text":
                    guard let text = block["text"]?.stringValue,
                          !text.hasPrefix(Self.contextPrefix),
                          !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                    items.append(message.role == .user ? .user(id: id, text: text) : .assistant(id: id, text: text))
                case "tool_use":
                    guard let call = ToolCall(block) else { continue }
                    items.append(.tool(id: call.id, tool: AgentTool(rawValue: call.name), outcome: conversation.outcomes[call.id]))
                default:
                    continue
                }
            }
        }
        return items
    }

    var canRetry: Bool {
        !isWorking && errorMessage != nil && !conversation.messages.isEmpty
    }

    func send(_ rawText: String) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isWorking else { return }
        guard account.hasConsented, account.isSignedIn else {
            pendingText = text
            needsSetup = true
            return
        }
        errorMessage = nil
        // Any action still waiting for approval is treated as declined: the person moved on.
        for call in conversation.openToolCalls where conversation.outcomes[call.id]?.isResolved != true {
            var outcome = conversation.outcomes[call.id] ?? ToolOutcome(status: .declined, summary: call.name)
            outcome.status = .declined
            outcome.resultText = "The person didn't approve this and sent a new message instead."
            conversation.outcomes[call.id] = outcome
        }
        var content = toolResultBlocks()
        content.append(.text(contextBlock()))
        content.append(.text(text))
        if conversation.messages.isEmpty { conversation.title = String(text.prefix(60)) }
        append(.user, content)
        startLoop()
    }

    func setupFinished() {
        needsSetup = false
        if let text = pendingText {
            pendingText = nil
            send(text)
        } else if canRetry {
            retry()
        }
    }

    func setupCancelled() {
        needsSetup = false
        pendingText = nil
    }

    func retry() {
        errorMessage = nil
        continueIfReady()
    }

    func stop() {
        task?.cancel()
    }

    // MARK: - Approvals

    func approve(_ callID: String) {
        guard !isWorking,
              let call = conversation.openToolCalls.first(where: { $0.id == callID }),
              conversation.outcomes[callID]?.status == .awaitingApproval else { return }
        guard let tool = AgentTool(rawValue: call.name), connectors.allows(tool) else {
            resolve(callID, ToolRunResult(text: "This connector is turned off.", isError: true))
            continueIfReady()
            return
        }
        conversation.outcomes[callID]?.status = .running
        save()
        Task {
            let result = await tools.run(tool, input: call.input)
            resolve(callID, result)
            continueIfReady()
        }
    }

    func decline(_ callID: String) {
        guard conversation.outcomes[callID]?.status == .awaitingApproval else { return }
        conversation.outcomes[callID]?.status = .declined
        conversation.outcomes[callID]?.resultText = "The person declined this action."
        save()
        continueIfReady()
    }

    // MARK: - The loop

    /// Continues the conversation once every tool call from Claude's last turn has a result.
    private func continueIfReady() {
        guard !isWorking else { return }
        let open = conversation.openToolCalls
        if open.isEmpty {
            // A failed request left the person's last message unanswered: try it again.
            if conversation.messages.last?.role == .user { startLoop() }
            return
        }
        guard open.allSatisfy({ conversation.outcomes[$0.id]?.isResolved == true }) else { return }
        append(.user, toolResultBlocks())
        startLoop()
    }

    private func startLoop() {
        // Set synchronously so a second approval can't start a parallel loop.
        isWorking = true
        task = Task { await loop() }
    }

    private func loop() async {
        defer {
            isWorking = false
            statusText = nil
        }
        for _ in 0..<Self.maxSteps {
            statusText = "Thinking…"
            let reply: AgentReply
            do {
                reply = try await account.agentTurn(
                    messages: conversation.messages.map { WireMessage(role: $0.role.rawValue, content: $0.content) },
                    tools: connectors.enabledTools.map(\.rawValue)
                )
            } catch is CancellationError {
                return
            } catch let error as URLError where error.code == .cancelled {
                return
            } catch APIError.unauthorized {
                errorMessage = "Please sign in again."
                needsSetup = true
                return
            } catch {
                errorMessage = error.localizedDescription
                return
            }
            if Task.isCancelled { return }

            if reply.stopReason == "refusal" {
                errorMessage = "Musing can't help with that request."
                return
            }
            guard !reply.content.isEmpty else {
                errorMessage = "Musing didn't reply. Tap Retry."
                return
            }
            append(.assistant, reply.content)

            let calls = conversation.openToolCalls
            if calls.isEmpty { return }
            if reply.stopReason != "tool_use" {
                // The reply was cut off, so its tool calls may be incomplete. Report that instead of running them.
                for call in calls {
                    conversation.outcomes[call.id] = ToolOutcome(
                        status: .failed, summary: "Couldn't finish this step",
                        resultText: "Your reply was cut off before this tool call was complete. Try again more briefly.",
                        isError: true
                    )
                }
                append(.user, toolResultBlocks())
                continue
            }

            var waitingForApproval = false
            for call in calls {
                guard let tool = AgentTool(rawValue: call.name) else {
                    resolve(call.id, ToolRunResult(text: "Unknown tool \(call.name).", isError: true, summary: "Unknown action"))
                    continue
                }
                let summary = tools.summary(for: tool, input: call.input)
                guard connectors.allows(tool) else {
                    conversation.outcomes[call.id] = ToolOutcome(status: .failed, summary: summary)
                    resolve(call.id, ToolRunResult(
                        text: "The \(tool.connector.title) connector is turned off (or read-only). Ask the person to change it in Settings.",
                        isError: true, summary: "\(tool.connector.title) is turned off in Settings"
                    ))
                    continue
                }
                if tool.needsApproval {
                    conversation.outcomes[call.id] = ToolOutcome(status: .awaitingApproval, summary: summary)
                    waitingForApproval = true
                    continue
                }
                conversation.outcomes[call.id] = ToolOutcome(status: .running, summary: summary)
                save()
                statusText = summary + "…"
                resolve(call.id, await tools.run(tool, input: call.input))
            }
            save()
            if waitingForApproval || Task.isCancelled { return }
            append(.user, toolResultBlocks())
        }
        errorMessage = "Musing paused after \(Self.maxSteps) steps. Tap Retry to let it keep going."
    }

    // MARK: - Helpers

    private func resolve(_ callID: String, _ result: ToolRunResult) {
        var outcome = conversation.outcomes[callID] ?? ToolOutcome(status: .done, summary: "")
        outcome.status = result.isError ? .failed : .done
        outcome.resultText = result.text
        outcome.isError = result.isError
        if let summary = result.summary { outcome.summary = summary }
        conversation.outcomes[callID] = outcome
        save()
    }

    /// Results for every tool call in Claude's last turn, in the order Claude made them.
    private func toolResultBlocks() -> [JSONValue] {
        conversation.openToolCalls.map { call in
            let outcome = conversation.outcomes[call.id]
            return .toolResult(id: call.id, text: outcome?.resultText ?? "No result.", isError: outcome?.isError ?? true)
        }
    }

    /// Time, time zone, connector access and memories, sent at the start of each message.
    private func contextBlock() -> String {
        let now = Date()
        var lines = [
            Self.contextPrefix,
            "Current time: \(DeviceTools.iso(now)) (\(now.formatted(.dateTime.weekday(.wide))))",
            "Time zone: \(TimeZone.current.identifier)",
            "Connectors: \(connectors.summary)",
        ]
        if connectors.level(.memory) != .off {
            if memory.memories.isEmpty {
                lines.append("Memories: none yet")
            } else {
                lines.append("Memories:")
                lines += memory.memories.map { "- [\($0.id)] \($0.text)" }
            }
        }
        lines.append("</context>")
        return lines.joined(separator: "\n")
    }

    private func append(_ role: ChatMessage.Role, _ content: [JSONValue]) {
        conversation.messages.append(ChatMessage(role: role, content: content))
        save()
    }

    private func save() {
        store.save(conversation)
    }
}
