import SwiftUI

@main
struct MusingApp: App {
    @State private var agent: AgentController

    init() {
        _agent = State(initialValue: AgentController(
            store: ConversationStore(),
            account: AccountStore(),
            connectors: ConnectorSettings(),
            memory: MemoryStore()
        ))
    }

    var body: some Scene {
        WindowGroup {
            ChatView()
                .environment(agent)
                .environment(agent.account)
                .task { await agent.account.verifyAppleCredential() }
        }
    }
}
