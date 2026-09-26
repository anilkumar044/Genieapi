import AuthenticationServices
import SwiftUI

/// First-run setup: explains what's shared and with whom, asks for consent, then signs in.
struct SetupView: View {
    @Environment(AccountStore.self) private var account
    var onReady: () -> Void
    var onCancel: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 44))
                        .foregroundStyle(.tint)
                    Text("Meet Musing")
                        .font(.largeTitle.bold())
                    Text("Your personal assistant. Ask it to plan your day, schedule things, set reminders, find people, and draft emails and texts. It always asks before taking an action.")
                        .foregroundStyle(.secondary)

                    DataSharingExplanation()

                    if !account.hasConsented {
                        Button {
                            account.setConsent(true)
                            if account.isSignedIn { onReady() }
                        } label: {
                            Text("Agree and Continue")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    } else if !account.isSignedIn {
                        SignInButtons(onSignedIn: onReady)
                    }
                }
                .padding(24)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not Now", action: onCancel)
                }
            }
        }
    }
}

/// Sign in with Apple, plus a developer sign-in when running against the local dev server.
struct SignInButtons: View {
    @Environment(AccountStore.self) private var account
    @Environment(\.colorScheme) private var colorScheme
    var onSignedIn: () -> Void
    @State private var isWorking = false
    @State private var errorMessage: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = []
            } onCompletion: { result in
                switch result {
                case .success(let authorization):
                    run { try await account.completeSignIn(with: authorization) }
                case .failure(let error):
                    if (error as? ASAuthorizationError)?.code != .canceled {
                        errorMessage = error.localizedDescription
                    }
                }
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 50)

            #if DEBUG
            if AIConfig.isLocalDevServer {
                Button {
                    run { try await account.devSignIn() }
                } label: {
                    Label("Developer Sign-In (local server)", systemImage: "hammer")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            #endif

            if isWorking { ProgressView().frame(maxWidth: .infinity) }
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .disabled(isWorking)
    }

    private func run(_ work: @escaping () async throws -> Void) {
        isWorking = true
        errorMessage = nil
        Task {
            defer { isWorking = false }
            do {
                try await work()
                onSignedIn()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct DataSharingExplanation: View {
    var compact = false

    var body: some View {
        if compact {
            Text("Your messages, and the calendar, reminder and contact details the assistant looks up for you, are sent to Musing's server and processed by \(AIConfig.providerDescription). Chats and memories are stored on this iPhone.")
        } else {
            VStack(alignment: .leading, spacing: 14) {
                Label {
                    Text("Your messages, and the calendar, reminder and contact details Musing looks up to help you, are sent to Musing's server and processed by \(AIConfig.providerDescription).")
                } icon: {
                    Image(systemName: "arrow.up.message")
                }
                Label("Musing asks before every action: adding events or reminders, opening links, or preparing an email or text, which you send yourself.", systemImage: "hand.raised")
                Label("You choose what Musing can use in Settings → Connectors. Chats and memories stay on this iPhone.", systemImage: "switch.2")
                Label("Sign-in keeps usage fair. You can delete your account anytime in Settings.", systemImage: "person.crop.circle")
            }
            .font(.subheadline)
        }
    }
}
