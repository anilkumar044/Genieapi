import Foundation

struct Memory: Codable, Identifiable, Hashable {
    var id: String
    var text: String
    var createdAt = Date()
}

/// Facts and preferences the assistant remembers across conversations. Stored only on this device.
@MainActor
@Observable
final class MemoryStore {
    private(set) var memories: [Memory] = []

    private static let fileURL = URL.documentsDirectory.appending(path: "memories.json")

    init() {
        if let data = try? Data(contentsOf: Self.fileURL),
           let saved = try? JSONDecoder().decode([Memory].self, from: data) {
            memories = saved
        }
    }

    @discardableResult
    func add(_ text: String) -> Memory {
        let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
        if let existing = memories.first(where: { $0.text.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return existing
        }
        let memory = Memory(id: "m" + String(UUID().uuidString.prefix(6)).lowercased(), text: trimmed)
        memories.append(memory)
        persist()
        return memory
    }

    func remove(id: String) -> Memory? {
        guard let index = memories.firstIndex(where: { $0.id == id }) else { return nil }
        let removed = memories.remove(at: index)
        persist()
        return removed
    }

    func removeAll() {
        memories = []
        persist()
    }

    private func persist() {
        try? JSONEncoder().encode(memories).write(to: Self.fileURL, options: [.atomic, .completeFileProtection])
    }
}
