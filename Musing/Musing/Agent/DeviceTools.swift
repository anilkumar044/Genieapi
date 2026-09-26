import Contacts
import EventKit
import MessageUI
import UIKit

/// What a tool returns to Claude.
struct ToolRunResult {
    var text: String
    var isError = false
    /// Replaces the chat's summary line once the tool has run, e.g. "Found 3 events".
    var summary: String?
}

enum ToolError: LocalizedError {
    case permissionDenied(String)
    case invalidInput(String)
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied(let what):
            "\(what) access is turned off for Musing. The person can allow it in the iPhone Settings app."
        case .invalidInput(let detail): "Invalid input: \(detail)"
        case .notFound(let detail): detail
        }
    }
}

// MARK: - Tool inputs

private struct DateRangeInput: Decodable { let start: String; let end: String }
private struct CreateEventInput: Decodable {
    let title: String; let start: String; let end: String
    let all_day: Bool?; let location: String?; let notes: String?
}
private struct ListRemindersInput: Decodable { let include_completed: Bool? }
private struct CreateReminderInput: Decodable { let title: String; let due: String?; let notes: String? }
private struct CompleteReminderInput: Decodable { let reminder_id: String }
private struct ContactsInput: Decodable { let query: String }
private struct EmailInput: Decodable { let to: [String]; let subject: String; let body: String }
private struct MessageInput: Decodable { let to: [String]; let body: String }
private struct LinkInput: Decodable { let url: String; let label: String }
private struct MemorySaveInput: Decodable { let fact: String }
private struct MemoryForgetInput: Decodable { let memory_id: String }

/// Runs Claude's tool calls on this iPhone: EventKit, Contacts, MessageUI and links.
@MainActor
final class DeviceTools {
    private let eventStore = EKEventStore()
    private let composer = ComposePresenter()
    private let memory: MemoryStore

    init(memory: MemoryStore) {
        self.memory = memory
    }

    // MARK: Describing calls for the chat

    /// One-line description of a tool call, shown in the chat and on approval cards.
    func summary(for tool: AgentTool, input: JSONValue) -> String {
        switch tool {
        case .calendarListEvents:
            return "Checking your calendar"
        case .calendarCreateEvent:
            guard let event = try? input.decode(as: CreateEventInput.self) else { return "Add an event to your calendar" }
            var text = "Add “\(event.title)” to your calendar"
            if let start = Self.parseDate(event.start) {
                text += " — " + (event.all_day == true
                    ? start.formatted(date: .abbreviated, time: .omitted)
                    : start.formatted(date: .abbreviated, time: .shortened))
            }
            if let location = event.location, !location.isEmpty { text += " at \(location)" }
            return text
        case .remindersList:
            return "Checking your reminders"
        case .remindersCreate:
            guard let reminder = try? input.decode(as: CreateReminderInput.self) else { return "Add a reminder" }
            var text = "Add reminder “\(reminder.title)”"
            if let due = reminder.due.flatMap(Self.parseDate) {
                text += " — \(due.formatted(date: .abbreviated, time: .shortened))"
            }
            return text
        case .remindersComplete:
            let id = (try? input.decode(as: CompleteReminderInput.self))?.reminder_id
            let title = id.flatMap { eventStore.calendarItem(withIdentifier: $0)?.title }
            return title.map { "Mark “\($0)” as done" } ?? "Mark a reminder as done"
        case .contactsSearch:
            let query = (try? input.decode(as: ContactsInput.self))?.query ?? ""
            return "Looking up “\(query)” in your contacts"
        case .composeEmail:
            guard let email = try? input.decode(as: EmailInput.self) else { return "Draft an email" }
            return "Email to \(email.to.joined(separator: ", ")) — “\(email.subject)”"
        case .composeMessage:
            guard let message = try? input.decode(as: MessageInput.self) else { return "Draft a text" }
            return "Text to \(message.to.joined(separator: ", ")): “\(message.body)”"
        case .openLink:
            guard let link = try? input.decode(as: LinkInput.self) else { return "Open a link" }
            let host = URL(string: link.url)?.host() ?? link.url
            return "Open \(link.label) (\(host))"
        case .memorySave:
            let fact = (try? input.decode(as: MemorySaveInput.self))?.fact ?? ""
            return "Remembered: \(fact)"
        case .memoryForget:
            return "Forgot a memory"
        }
    }

    // MARK: Running calls

    func run(_ tool: AgentTool, input: JSONValue) async -> ToolRunResult {
        do {
            switch tool {
            case .calendarListEvents: return try await listEvents(input.decode())
            case .calendarCreateEvent: return try await createEvent(input.decode())
            case .remindersList: return try await listReminders(input.decode())
            case .remindersCreate: return try await createReminder(input.decode())
            case .remindersComplete: return try await completeReminder(input.decode())
            case .contactsSearch: return try await searchContacts(input.decode())
            case .composeEmail: return try await composeEmail(input.decode())
            case .composeMessage: return try await composeMessage(input.decode())
            case .openLink: return try await openLink(input.decode())
            case .memorySave:
                let input: MemorySaveInput = try input.decode()
                let saved = memory.add(input.fact)
                return ToolRunResult(text: "Saved memory \(saved.id).", summary: "Remembered: \(saved.text)")
            case .memoryForget:
                let input: MemoryForgetInput = try input.decode()
                guard let removed = memory.remove(id: input.memory_id) else { throw ToolError.notFound("No memory with that id.") }
                return ToolRunResult(text: "Forgot memory \(removed.id).", summary: "Forgot: \(removed.text)")
            }
        } catch let error as DecodingError {
            return ToolRunResult(text: "Invalid input for \(tool.rawValue): \(error)", isError: true, summary: "Couldn't read the request")
        } catch {
            return ToolRunResult(text: error.localizedDescription, isError: true, summary: error.localizedDescription)
        }
    }

    // MARK: Calendar

    private func requireCalendarAccess() async throws {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: return
        case .notDetermined:
            guard try await eventStore.requestFullAccessToEvents() else { throw ToolError.permissionDenied("Calendar") }
        default:
            throw ToolError.permissionDenied("Calendar")
        }
    }

    private func listEvents(_ input: DateRangeInput) async throws -> ToolRunResult {
        try await requireCalendarAccess()
        guard let start = Self.parseDate(input.start), let end = Self.parseDate(input.end), end > start else {
            throw ToolError.invalidInput("start and end must be ISO 8601 times with end after start")
        }
        let cappedEnd = min(end, start.addingTimeInterval(62 * 24 * 3600))
        let predicate = eventStore.predicateForEvents(withStart: start, end: cappedEnd, calendars: nil)
        let events = eventStore.events(matching: predicate).sorted { $0.startDate < $1.startDate }
        guard !events.isEmpty else { return ToolRunResult(text: "No events in that range.", summary: "No events found") }
        let lines = events.prefix(100).map { event in
            var line = "- \(event.title ?? "Untitled") | "
            line += event.isAllDay
                ? "all day \(Self.isoDay(event.startDate))"
                : "\(Self.iso(event.startDate)) → \(Self.iso(event.endDate))"
            if let location = event.location, !location.isEmpty { line += " | at \(location)" }
            line += " | calendar: \(event.calendar.title)"
            return line
        }
        let more = events.count > 100 ? "\n(\(events.count - 100) more not shown)" : ""
        return ToolRunResult(
            text: lines.joined(separator: "\n") + more,
            summary: "Found \(events.count) event\(events.count == 1 ? "" : "s")"
        )
    }

    private func createEvent(_ input: CreateEventInput) async throws -> ToolRunResult {
        try await requireCalendarAccess()
        guard let start = Self.parseDate(input.start), let end = Self.parseDate(input.end) else {
            throw ToolError.invalidInput("start and end must be ISO 8601")
        }
        let event = EKEvent(eventStore: eventStore)
        event.title = input.title
        event.isAllDay = input.all_day ?? false
        event.startDate = start
        event.endDate = max(end, start)
        event.location = input.location
        event.notes = input.notes
        event.calendar = eventStore.defaultCalendarForNewEvents
        try eventStore.save(event, span: .thisEvent)
        return ToolRunResult(
            text: "Created event “\(input.title)” on calendar \(event.calendar?.title ?? "default").",
            summary: "Added “\(input.title)” to your calendar"
        )
    }

    // MARK: Reminders

    private func requireRemindersAccess() async throws {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess: return
        case .notDetermined:
            guard try await eventStore.requestFullAccessToReminders() else { throw ToolError.permissionDenied("Reminders") }
        default:
            throw ToolError.permissionDenied("Reminders")
        }
    }

    private struct ReminderInfo {
        let id: String
        let title: String
        let due: Date?
        let completed: Bool
        let list: String
    }

    private func listReminders(_ input: ListRemindersInput) async throws -> ToolRunResult {
        try await requireRemindersAccess()
        let predicate = input.include_completed == true
            ? eventStore.predicateForReminders(in: nil)
            : eventStore.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        let reminders: [ReminderInfo] = await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                let infos = (reminders ?? []).map { reminder in
                    ReminderInfo(
                        id: reminder.calendarItemIdentifier,
                        title: reminder.title ?? "Untitled",
                        due: reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) },
                        completed: reminder.isCompleted,
                        list: reminder.calendar?.title ?? ""
                    )
                }
                continuation.resume(returning: infos)
            }
        }
        guard !reminders.isEmpty else { return ToolRunResult(text: "No reminders.", summary: "No reminders found") }
        let lines = reminders.prefix(100).map { reminder in
            var line = "- [id \(reminder.id)] \(reminder.title)"
            if let due = reminder.due { line += " | due \(Self.iso(due))" }
            if reminder.completed { line += " | completed" }
            line += " | list: \(reminder.list)"
            return line
        }
        return ToolRunResult(
            text: lines.joined(separator: "\n"),
            summary: "Found \(reminders.count) reminder\(reminders.count == 1 ? "" : "s")"
        )
    }

    private func createReminder(_ input: CreateReminderInput) async throws -> ToolRunResult {
        try await requireRemindersAccess()
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = input.title
        reminder.notes = input.notes
        reminder.calendar = eventStore.defaultCalendarForNewReminders()
        if let dueText = input.due {
            guard let due = Self.parseDate(dueText) else { throw ToolError.invalidInput("due must be ISO 8601") }
            reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due)
            reminder.addAlarm(EKAlarm(absoluteDate: due))
        }
        try eventStore.save(reminder, commit: true)
        return ToolRunResult(text: "Created reminder “\(input.title)”.", summary: "Added reminder “\(input.title)”")
    }

    private func completeReminder(_ input: CompleteReminderInput) async throws -> ToolRunResult {
        try await requireRemindersAccess()
        guard let reminder = eventStore.calendarItem(withIdentifier: input.reminder_id) as? EKReminder else {
            throw ToolError.notFound("No reminder with that id. List reminders again to get current ids.")
        }
        reminder.isCompleted = true
        try eventStore.save(reminder, commit: true)
        return ToolRunResult(text: "Completed “\(reminder.title ?? "")”.", summary: "Completed “\(reminder.title ?? "reminder")”")
    }

    // MARK: Contacts

    private func searchContacts(_ input: ContactsInput) async throws -> ToolRunResult {
        let store = CNContactStore()
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized, .limited: break
        case .notDetermined:
            guard try await store.requestAccess(for: .contacts) else { throw ToolError.permissionDenied("Contacts") }
        default:
            throw ToolError.permissionDenied("Contacts")
        }
        let query = input.query
        // Contacts lookups are synchronous; keep them off the main thread.
        let lines: [String] = try await Task.detached {
            let keys = [
                CNContactGivenNameKey, CNContactFamilyNameKey, CNContactOrganizationNameKey,
                CNContactPhoneNumbersKey, CNContactEmailAddressesKey,
            ] as [CNKeyDescriptor]
            let contacts = try store.unifiedContacts(matching: CNContact.predicateForContacts(matchingName: query), keysToFetch: keys)
            return contacts.prefix(20).map { contact in
                let name = [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " ")
                var line = "- \(name.isEmpty ? contact.organizationName : name)"
                let phones = contact.phoneNumbers.map { $0.value.stringValue }
                let emails = contact.emailAddresses.map { $0.value as String }
                if !phones.isEmpty { line += " | phone: \(phones.joined(separator: ", "))" }
                if !emails.isEmpty { line += " | email: \(emails.joined(separator: ", "))" }
                return line
            }
        }.value
        guard !lines.isEmpty else {
            return ToolRunResult(text: "No contacts match “\(query)”.", summary: "No contacts found for “\(query)”")
        }
        return ToolRunResult(
            text: lines.joined(separator: "\n"),
            summary: "Found \(lines.count) contact\(lines.count == 1 ? "" : "s")"
        )
    }

    // MARK: Drafts & links

    private func composeEmail(_ input: EmailInput) async -> ToolRunResult {
        let outcome = await composer.composeEmail(to: input.to, subject: input.subject, body: input.body)
        return ToolRunResult(text: outcome.resultText, summary: outcome.summary)
    }

    private func composeMessage(_ input: MessageInput) async -> ToolRunResult {
        let outcome = await composer.composeMessage(to: input.to, body: input.body)
        return ToolRunResult(text: outcome.resultText, summary: outcome.summary)
    }

    private func openLink(_ input: LinkInput) async throws -> ToolRunResult {
        guard let url = URL(string: input.url), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            throw ToolError.invalidInput("only http and https links can be opened")
        }
        let opened = await UIApplication.shared.open(url)
        return opened
            ? ToolRunResult(text: "Opened \(input.url) on the phone.", summary: "Opened \(input.label)")
            : ToolRunResult(text: "The link couldn't be opened.", isError: true, summary: "Couldn't open \(input.label)")
    }

    // MARK: Dates

    static func parseDate(_ text: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        let dayOnly = ISO8601DateFormatter()
        dayOnly.formatOptions = [.withFullDate]
        dayOnly.timeZone = .current
        return plain.date(from: text) ?? withFraction.date(from: text) ?? dayOnly.date(from: text)
    }

    static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    static func isoDay(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        formatter.formatOptions = [.withFullDate]
        return formatter.string(from: date)
    }
}

// MARK: - Mail & Messages

/// Presents the system email and message composers, so the person reviews and sends drafts themselves.
@MainActor
final class ComposePresenter: NSObject, MFMailComposeViewControllerDelegate, MFMessageComposeViewControllerDelegate {
    struct Outcome {
        let resultText: String
        let summary: String
    }

    private var continuation: CheckedContinuation<Outcome, Never>?

    func composeEmail(to recipients: [String], subject: String, body: String) async -> Outcome {
        guard MFMailComposeViewController.canSendMail() else {
            // No Mail account (e.g. the Simulator): hand the draft to the default mail app instead.
            var components = URLComponents()
            components.scheme = "mailto"
            components.path = recipients.joined(separator: ",")
            components.queryItems = [URLQueryItem(name: "subject", value: subject), URLQueryItem(name: "body", value: body)]
            if let url = components.url, await UIApplication.shared.open(url) {
                return Outcome(resultText: "Opened the draft in the person's mail app; they will send it themselves.",
                               summary: "Opened the email draft")
            }
            UIPasteboard.general.string = body
            return Outcome(resultText: "No mail app is set up on this phone. The email text was copied to the clipboard.",
                           summary: "No mail app — copied the email text")
        }
        let controller = MFMailComposeViewController()
        controller.setToRecipients(recipients)
        controller.setSubject(subject)
        controller.setMessageBody(body, isHTML: false)
        controller.mailComposeDelegate = self
        return await present(controller)
    }

    func composeMessage(to recipients: [String], body: String) async -> Outcome {
        guard MFMessageComposeViewController.canSendText() else {
            UIPasteboard.general.string = body
            return Outcome(resultText: "Messages isn't available on this device. The text was copied to the clipboard.",
                           summary: "Messages unavailable — copied the text")
        }
        let controller = MFMessageComposeViewController()
        controller.recipients = recipients
        controller.body = body
        controller.messageComposeDelegate = self
        return await present(controller)
    }

    private func present(_ controller: UIViewController) async -> Outcome {
        guard let presenter = Self.topViewController() else {
            return Outcome(resultText: "The draft couldn't be shown.", summary: "Couldn't show the draft")
        }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            presenter.present(controller, animated: true)
        }
    }

    private func finish(_ controller: UIViewController, _ outcome: Outcome) {
        controller.dismiss(animated: true)
        continuation?.resume(returning: outcome)
        continuation = nil
    }

    nonisolated func mailComposeController(
        _ controller: MFMailComposeViewController,
        didFinishWith result: MFMailComposeResult,
        error: Error?
    ) {
        MainActor.assumeIsolated {
            let outcome: Outcome = switch result {
            case .sent: Outcome(resultText: "The person sent the email.", summary: "Email sent")
            case .saved: Outcome(resultText: "The person saved the email as a draft without sending.", summary: "Email saved as draft")
            case .cancelled: Outcome(resultText: "The person closed the draft without sending.", summary: "Email not sent")
            default: Outcome(resultText: "The email couldn't be sent.", summary: "Email failed")
            }
            finish(controller, outcome)
        }
    }

    nonisolated func messageComposeViewController(
        _ controller: MFMessageComposeViewController,
        didFinishWith result: MessageComposeResult
    ) {
        MainActor.assumeIsolated {
            let outcome: Outcome = switch result {
            case .sent: Outcome(resultText: "The person sent the text.", summary: "Text sent")
            case .cancelled: Outcome(resultText: "The person closed the draft without sending.", summary: "Text not sent")
            default: Outcome(resultText: "The text couldn't be sent.", summary: "Text failed")
            }
            finish(controller, outcome)
        }
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
