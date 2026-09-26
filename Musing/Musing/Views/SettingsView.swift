import SwiftUI

/// Connectors, memory, account and data controls.
struct SettingsView: View {
    @Environment(AgentController.self) private var agent
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDeleteAccount = false
    @State private var confirmDeleteChats = false
    @State private var isDeleting = false
    @State private var errorMessage: String? = nil

    private var account: AccountStore { agent.account }
    private var connectors: ConnectorSettings { agent.connectors }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(Connector.allCases) { connector in
                        ConnectorRow(connector: connector, connectors: connectors)
                    }
                } header: {
                    Text("Connectors")
                } footer: {
                    Text("“Read only” lets Musing look things up but not change anything. Actions always need your approval, and iOS asks for permission the first time Musing uses each app.")
                }

                Section("Memory") {
                    NavigationLink {
                        MemoryListView(memory: agent.memory)
                    } label: {
                        LabeledContent("Saved memories", value: "\(agent.memory.memories.count)")
                    }
                }

                Section("Account") {
                    if account.isSignedIn {
                        if let usage = account.usage {
                            LabeledContent("Assistant steps today", value: "\(usage.used) of \(usage.limit)")
                        }
                        Button("Sign Out") { account.signOut() }
                    } else {
                        SignInButtons {}
                    }
                }

                Section {
                    Toggle("Allow sharing with the AI", isOn: Binding(
                        get: { account.hasConsented },
                        set: { account.setConsent($0) }
                    ))
                } header: {
                    Text("Data sharing")
                } footer: {
                    DataSharingExplanation(compact: true)
                }

                Section {
                    Button("Delete All Chats", role: .destructive) { confirmDeleteChats = true }
                    if account.isSignedIn {
                        Button("Delete Account", role: .destructive) { confirmDeleteAccount = true }
                            .disabled(isDeleting)
                    }
                } footer: {
                    Text("Deleting your account removes it and its usage records from Musing's server and revokes Sign in with Apple. Chats and memories on this iPhone are deleted separately.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await account.refreshUsage() }
            .confirmationDialog("Delete all chats on this iPhone?", isPresented: $confirmDeleteChats, titleVisibility: .visible) {
                Button("Delete All Chats", role: .destructive) {
                    agent.store.deleteAll()
                    agent.newChat()
                }
            }
            .confirmationDialog("Delete your Musing account?", isPresented: $confirmDeleteAccount, titleVisibility: .visible) {
                Button("Delete Account", role: .destructive) {
                    isDeleting = true
                    Task {
                        defer { isDeleting = false }
                        do {
                            try await account.deleteAccount()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
            }
            .alert("Couldn't Delete Account", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }
}

private struct ConnectorRow: View {
    let connector: Connector
    let connectors: ConnectorSettings

    var body: some View {
        Picker(selection: Binding(
            get: { connectors.level(connector) },
            set: { connectors.set($0, for: connector) }
        )) {
            ForEach(connector.levels) { level in
                Text(level.title).tag(level)
            }
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(connector.title)
                    Text(connector.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: connector.systemImage)
            }
        }
        .pickerStyle(.menu)
    }
}

private struct MemoryListView: View {
    let memory: MemoryStore
    @State private var draft = ""

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("Add something to remember", text: $draft)
                        .onSubmit(add)
                    Button("Add", action: add)
                        .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } footer: {
                Text("Musing uses these in every chat. Tell it “remember that…” or add them here.")
            }
            Section {
                if memory.memories.isEmpty {
                    Text("Nothing saved yet").foregroundStyle(.secondary)
                }
                ForEach(memory.memories) { item in
                    Text(item.text)
                }
                .onDelete { offsets in
                    for index in offsets { _ = memory.remove(id: memory.memories[index].id) }
                }
            }
        }
        .navigationTitle("Memories")
        .toolbar {
            if !memory.memories.isEmpty { EditButton() }
        }
    }

    private func add() {
        guard !draft.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        memory.add(draft)
        draft = ""
    }
}

/// Past chats.
struct HistoryView: View {
    @Environment(AgentController.self) private var agent
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if agent.store.conversations.isEmpty {
                    Text("No chats yet").foregroundStyle(.secondary)
                }
                ForEach(agent.store.conversations) { conversation in
                    Button {
                        agent.open(conversation.id)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(conversation.title)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                            Text(conversation.updatedAt.formatted(.relative(presentation: .named)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    let ids = offsets.map { agent.store.conversations[$0].id }
                    for id in ids { agent.deleteConversation(id) }
                }
            }
            .navigationTitle("Chats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
