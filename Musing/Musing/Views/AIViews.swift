import AuthenticationServices
import SwiftUI

/// First-run AI setup: explains what's shared and with whom, asks for consent, then Sign in with Apple.
struct AISetupView: View {
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
                    Text("AI in Musing")
                        .font(.largeTitle.bold())
                    Text("Summarize or organize a board, expand a note, read handwriting, turn photos into notes, or ask a question about your board.")
                        .foregroundStyle(.secondary)

                    DataSharingExplanation()

                    if !account.hasConsented {
                        Button {
                            account.setConsent(true)
                            if account.isSignedIn { onReady() }
                        } label: {
                            Text("Allow AI Actions")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    } else if !account.isSignedIn {
                        AppleSignInButton(onSignedIn: onReady)
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

/// Manage the AI account: usage, sharing consent, sign out, and account deletion.
struct AIAccountView: View {
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false
    @State private var isDeleting = false
    @State private var errorMessage: String? = nil

    var body: some View {
        NavigationStack {
            Form {
                if account.isSignedIn {
                    Section("Today") {
                        if let usage = account.usage {
                            LabeledContent("AI actions used", value: "\(usage.used) of \(usage.limit)")
                            ProgressView(value: Double(usage.used), total: Double(max(usage.limit, 1)))
                        } else {
                            Text("Usage unavailable").foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Section {
                        AppleSignInButton {}
                    } footer: {
                        Text("Sign in to use AI actions.")
                    }
                }

                Section {
                    Toggle("Allow AI actions", isOn: Binding(
                        get: { account.hasConsented },
                        set: { account.setConsent($0) }
                    ))
                } header: {
                    Text("Data sharing")
                } footer: {
                    DataSharingExplanation(compact: true)
                }

                if account.isSignedIn {
                    Section {
                        Button("Sign Out") { account.signOut() }
                        Button("Delete Account", role: .destructive) { confirmDelete = true }
                            .disabled(isDeleting)
                    } footer: {
                        Text("Deleting your account removes your account and usage records from Musing's server and revokes Sign in with Apple. Your boards stay on this iPhone.")
                    }
                }
            }
            .navigationTitle("AI Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await account.refreshUsage() }
            .confirmationDialog("Delete your AI account?", isPresented: $confirmDelete, titleVisibility: .visible) {
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

private struct DataSharingExplanation: View {
    var compact = false

    var body: some View {
        if compact {
            Text("When you run an AI action, the current board's text — and the sketch or photo you chose — is sent to Musing's server and processed by \(AIConfig.providerDescription). Nothing is sent otherwise.")
        } else {
            VStack(alignment: .leading, spacing: 14) {
                Label {
                    Text("When you run an AI action, the current board's text — and the sketch or photo you chose — is sent to Musing's server and processed by \(AIConfig.providerDescription).")
                } icon: {
                    Image(systemName: "arrow.up.doc")
                }
                Label("Nothing is sent until you tap an AI action. Your boards otherwise stay on this iPhone.", systemImage: "iphone")
                Label("Sign in with Apple keeps usage fair. You can delete your account anytime from AI Account.", systemImage: "person.crop.circle")
            }
            .font(.subheadline)
        }
    }
}

private struct AppleSignInButton: View {
    @Environment(AccountStore.self) private var account
    @Environment(\.colorScheme) private var colorScheme
    var onSignedIn: () -> Void
    @State private var isWorking = false
    @State private var errorMessage: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = []
            } onCompletion: { result in
                switch result {
                case .success(let authorization):
                    isWorking = true
                    Task {
                        defer { isWorking = false }
                        do {
                            try await account.completeSignIn(with: authorization)
                            onSignedIn()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                case .failure(let error):
                    if (error as? ASAuthorizationError)?.code != .canceled {
                        errorMessage = error.localizedDescription
                    }
                }
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 50)
            .disabled(isWorking)
            .overlay { if isWorking { ProgressView() } }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }
}
