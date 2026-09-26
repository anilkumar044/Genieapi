import Foundation

/// A kind of access the assistant can be given, like Muse's connectors.
enum Connector: String, CaseIterable, Identifiable, Codable {
    case calendar, reminders, contacts, drafts, links, memory

    var id: String { rawValue }

    var title: String {
        switch self {
        case .calendar: "Calendar"
        case .reminders: "Reminders"
        case .contacts: "Contacts"
        case .drafts: "Email & Text Drafts"
        case .links: "Open Links"
        case .memory: "Memory"
        }
    }

    var systemImage: String {
        switch self {
        case .calendar: "calendar"
        case .reminders: "checklist"
        case .contacts: "person.crop.circle"
        case .drafts: "envelope"
        case .links: "safari"
        case .memory: "brain.head.profile"
        }
    }

    var detail: String {
        switch self {
        case .calendar: "See your events and add new ones."
        case .reminders: "See, add and complete reminders."
        case .contacts: "Look up phone numbers and email addresses."
        case .drafts: "Prepare emails and texts for you to review and send."
        case .links: "Open websites, maps and booking pages."
        case .memory: "Remember your preferences between chats."
        }
    }

    /// Access levels that make sense for this connector.
    var levels: [AccessLevel] {
        switch self {
        case .calendar, .reminders: [.off, .readOnly, .full]
        case .contacts: [.off, .readOnly]
        case .drafts, .links, .memory: [.off, .full]
        }
    }
}

enum AccessLevel: String, Codable, CaseIterable, Identifiable {
    case off, readOnly, full

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: "Off"
        case .readOnly: "Read only"
        case .full: "Read & act"
        }
    }
}

/// Every tool the backend can offer Claude (names must match `backend/src/agent.ts`).
enum AgentTool: String, CaseIterable {
    case calendarListEvents = "calendar_list_events"
    case calendarCreateEvent = "calendar_create_event"
    case remindersList = "reminders_list"
    case remindersCreate = "reminders_create"
    case remindersComplete = "reminders_complete"
    case contactsSearch = "contacts_search"
    case composeEmail = "compose_email"
    case composeMessage = "compose_message"
    case openLink = "open_link"
    case memorySave = "memory_save"
    case memoryForget = "memory_forget"

    var connector: Connector {
        switch self {
        case .calendarListEvents, .calendarCreateEvent: .calendar
        case .remindersList, .remindersCreate, .remindersComplete: .reminders
        case .contactsSearch: .contacts
        case .composeEmail, .composeMessage: .drafts
        case .openLink: .links
        case .memorySave, .memoryForget: .memory
        }
    }

    /// Reads need "Read only" access; everything else needs full access.
    var isRead: Bool {
        switch self {
        case .calendarListEvents, .remindersList, .contactsSearch: true
        default: false
        }
    }

    /// Actions the person confirms before they happen. Memory is visible in the chat and in Settings instead.
    var needsApproval: Bool {
        !isRead && connector != .memory
    }

    /// Label for the approve button.
    var approveTitle: String {
        switch self {
        case .composeEmail, .composeMessage: "Review Draft"
        case .openLink: "Open"
        default: "Approve"
        }
    }
}

/// Which connectors the person has turned on, saved on the device.
@MainActor
@Observable
final class ConnectorSettings {
    private(set) var levels: [Connector: AccessLevel]

    private static let key = "connectorLevels"
    private static let defaults: [Connector: AccessLevel] = [
        .calendar: .full, .reminders: .full, .contacts: .readOnly, .drafts: .full, .links: .full, .memory: .full,
    ]

    init() {
        var levels = Self.defaults
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([String: AccessLevel].self, from: data) {
            for (key, level) in saved {
                if let connector = Connector(rawValue: key) { levels[connector] = level }
            }
        }
        self.levels = levels
    }

    func level(_ connector: Connector) -> AccessLevel {
        levels[connector] ?? .off
    }

    func set(_ level: AccessLevel, for connector: Connector) {
        levels[connector] = level
        let raw = Dictionary(uniqueKeysWithValues: levels.map { ($0.key.rawValue, $0.value) })
        UserDefaults.standard.set(try? JSONEncoder().encode(raw), forKey: Self.key)
    }

    func allows(_ tool: AgentTool) -> Bool {
        switch level(tool.connector) {
        case .off: false
        case .readOnly: tool.isRead
        case .full: true
        }
    }

    var enabledTools: [AgentTool] {
        AgentTool.allCases.filter(allows)
    }

    /// Describes the current access for Claude's context block.
    var summary: String {
        Connector.allCases.map { "\($0.title): \(level($0).title)" }.joined(separator: "; ")
    }
}
