import SwiftUI

struct ChatView: View {
    @Environment(AgentController.self) private var agent
    @State private var draft = ""
    @State private var showSettings = false
    @State private var showHistory = false
    @FocusState private var inputFocused: Bool

    private static let suggestions = [
        "What's on my calendar tomorrow?",
        "Remind me to call Mom at 6pm",
        "Find a time for lunch with Sam next week",
        "Draft a thank-you email to my team",
    ]

    var body: some View {
        @Bindable var agent = agent
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if agent.conversation.messages.isEmpty {
                            emptyState
                        }
                        ForEach(agent.items) { item in
                            row(for: item)
                                .id(item.id)
                        }
                        if let status = agent.statusText {
                            StatusRow(text: status) { agent.stop() }
                                .id("status")
                        }
                        if let error = agent.errorMessage {
                            ErrorRow(message: error, canRetry: agent.canRetry) { agent.retry() }
                                .id("error")
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: agent.items.count) { scrollToBottom(proxy) }
                .onChange(of: agent.statusText) { scrollToBottom(proxy) }
                .onChange(of: agent.errorMessage) { scrollToBottom(proxy) }
                .onAppear { proxy.scrollTo("bottom") }
            }
            .safeAreaInset(edge: .bottom) { inputBar }
            .navigationTitle(agent.conversation.messages.isEmpty ? "Musing" : agent.conversation.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showHistory = true } label: { Image(systemName: "clock.arrow.circlepath") }
                        .accessibilityLabel("Chats")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                    Button { agent.newChat() } label: { Image(systemName: "square.and.pencil") }
                        .accessibilityLabel("New Chat")
                        .disabled(agent.conversation.messages.isEmpty)
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView().environment(agent).environment(agent.account)
            }
            .sheet(isPresented: $showHistory) {
                HistoryView().environment(agent)
            }
            .sheet(isPresented: $agent.needsSetup) {
                SetupView(onReady: agent.setupFinished, onCancel: agent.setupCancelled)
                    .environment(agent.account)
                    .interactiveDismissDisabled()
            }
        }
    }

    @ViewBuilder
    private func row(for item: ChatItem) -> some View {
        switch item {
        case .user(_, let text):
            UserBubble(text: text)
        case .assistant(_, let text):
            AssistantText(text: text)
        case .tool(let id, let tool, let outcome):
            if outcome?.status == .awaitingApproval, let tool {
                ApprovalCard(
                    tool: tool,
                    summary: outcome?.summary ?? "",
                    busy: agent.isWorking,
                    onApprove: { agent.approve(id) },
                    onDecline: { agent.decline(id) }
                )
            } else {
                ToolActivityRow(tool: tool, outcome: outcome)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 36))
                .foregroundStyle(.tint)
                .padding(.top, 40)
            Text("What can I do for you?")
                .font(.title2.bold())
            Text("I can check your calendar and reminders, find contacts, schedule things and draft messages — and I'll ask before doing anything.")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Self.suggestions, id: \.self) { suggestion in
                    Button {
                        agent.send(suggestion)
                    } label: {
                        Text(suggestion)
                            .font(.subheadline)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(.fill.tertiary, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Ask Musing to do something…", text: $draft, axis: .vertical)
                .lineLimit(1...6)
                .focused($inputFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .submitLabel(.send)
                .onSubmit(send)
            if agent.isWorking {
                Button { agent.stop() } label: {
                    Image(systemName: "stop.circle.fill").font(.system(size: 32))
                }
                .accessibilityLabel("Stop")
            } else {
                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 32))
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Send")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func send() {
        let text = draft
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !agent.isWorking else { return }
        draft = ""
        agent.send(text)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) }
    }
}

// MARK: - Rows

private struct UserBubble: View {
    let text: String

    var body: some View {
        HStack {
            Spacer(minLength: 48)
            Text(text)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .foregroundStyle(.white)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .textSelection(.enabled)
        }
    }
}

private struct AssistantText: View {
    let text: String

    var body: some View {
        Text(Self.markdown(text))
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }

    private static func markdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

private struct ToolActivityRow: View {
    let tool: AgentTool?
    let outcome: ToolOutcome?

    var body: some View {
        HStack(spacing: 8) {
            icon
                .frame(width: 18)
            Text(outcome?.summary ?? "Working…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var icon: some View {
        switch outcome?.status {
        case .running, .none, .awaitingApproval:
            ProgressView().controlSize(.small)
        case .done:
            Image(systemName: tool?.connector.systemImage ?? "checkmark.circle")
                .foregroundStyle(.green)
        case .declined:
            Image(systemName: "hand.raised.slash")
                .foregroundStyle(.secondary)
        case .failed:
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        }
    }
}

private struct ApprovalCard: View {
    let tool: AgentTool
    let summary: String
    let busy: Bool
    let onApprove: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Needs your OK", systemImage: "hand.raised.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: tool.connector.systemImage)
                    .font(.title3)
                    .foregroundStyle(.tint)
                Text(summary)
                    .font(.body.weight(.medium))
            }
            HStack {
                Button("Not Now", role: .cancel, action: onDecline)
                    .buttonStyle(.bordered)
                Spacer()
                Button(tool.approveTitle, action: onApprove)
                    .buttonStyle(.borderedProminent)
            }
            .disabled(busy)
        }
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.4), lineWidth: 1)
        }
    }
}

private struct StatusRow: View {
    let text: String
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ErrorRow: View {
    let message: String
    let canRetry: Bool
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(message, systemImage: "exclamationmark.bubble")
                .font(.subheadline)
                .foregroundStyle(.red)
            if canRetry {
                Button("Retry", action: onRetry)
                    .buttonStyle(.bordered)
            }
        }
    }
}
