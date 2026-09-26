import Foundation

struct ChatMessage: Codable, Identifiable {
    enum Role: String, Codable { case user, assistant }

    var id = UUID()
    var role: Role
    /// Content blocks exactly as sent to / received from Claude.
    var content: [JSONValue]
    var createdAt = Date()
}

/// What happened to one tool call Claude made.
struct ToolOutcome: Codable {
    enum Status: String, Codable {
        /// Waiting for the person to approve or decline.
        case awaitingApproval
        case running
        case done
        case declined
        case failed
    }

    var status: Status
    /// Short description shown in the chat, e.g. "Add “Dinner” to your calendar".
    var summary: String
    /// The text returned to Claude as the tool result.
    var resultText: String?
    var isError = false

    var isResolved: Bool { status == .done || status == .declined || status == .failed }
}

/// A tool call in the conversation, parsed from a `tool_use` block.
struct ToolCall: Identifiable {
    let id: String
    let name: String
    let input: JSONValue

    init?(_ block: JSONValue) {
        guard block["type"]?.stringValue == "tool_use",
              let id = block["id"]?.stringValue,
              let name = block["name"]?.stringValue else { return nil }
        self.id = id
        self.name = name
        self.input = block["input"] ?? .object([:])
    }
}

struct Conversation: Codable, Identifiable {
    var id = UUID()
    var title = "New Chat"
    var messages: [ChatMessage] = []
    var outcomes: [String: ToolOutcome] = [:]
    var updatedAt = Date()

    /// Tool calls from Claude's latest turn that still need a result before the conversation can continue.
    var openToolCalls: [ToolCall] {
        guard let last = messages.last, last.role == .assistant else { return [] }
        return last.content.compactMap(ToolCall.init)
    }
}

/// Saves conversations as JSON files on the device.
@MainActor
@Observable
final class ConversationStore {
    private(set) var conversations: [Conversation] = []

    private static let directory = URL.documentsDirectory.appending(path: "Conversations", directoryHint: .isDirectory)

    init() {
        try? FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: Self.directory, includingPropertiesForKeys: nil)) ?? []
        conversations = files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder().decode(Conversation.self, from: Data(contentsOf: $0)) }
            .map(Self.recoverInterrupted)
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func conversation(_ id: UUID) -> Conversation? {
        conversations.first { $0.id == id }
    }

    func save(_ conversation: Conversation) {
        var conversation = conversation
        conversation.updatedAt = Date()
        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[index] = conversation
        } else {
            conversations.insert(conversation, at: 0)
        }
        conversations.sort { $0.updatedAt > $1.updatedAt }
        do {
            try JSONEncoder().encode(conversation).write(to: fileURL(conversation.id), options: [.atomic, .completeFileProtection])
        } catch {
            print("Musing: failed to save conversation: \(error)")
        }
    }

    func delete(_ id: UUID) {
        conversations.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: fileURL(id))
    }

    func deleteAll() {
        for conversation in conversations { try? FileManager.default.removeItem(at: fileURL(conversation.id)) }
        conversations = []
    }

    private func fileURL(_ id: UUID) -> URL {
        Self.directory.appending(path: "\(id.uuidString).json")
    }

    /// A tool that was mid-run when the app quit never finished; report it as failed so the chat can continue.
    private static func recoverInterrupted(_ conversation: Conversation) -> Conversation {
        var conversation = conversation
        for (id, outcome) in conversation.outcomes where outcome.status == .running {
            conversation.outcomes[id]?.status = .failed
            conversation.outcomes[id]?.isError = true
            conversation.outcomes[id]?.resultText = "The app was closed before this finished."
        }
        return conversation
    }
}
