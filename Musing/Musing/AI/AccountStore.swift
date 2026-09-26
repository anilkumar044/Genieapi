import AuthenticationServices
import Foundation

/// The person's account: Sign in with Apple session, consent to share content with the AI, and daily usage.
@MainActor
@Observable
final class AccountStore {
    private(set) var sessionToken: String?
    private(set) var usage: AIUsage?
    private(set) var hasConsented: Bool

    private static let consentKey = "aiConsentGiven"
    private static let sessionAccount = "session"
    private static let appleUserAccount = "appleUserID"

    var isSignedIn: Bool { sessionToken != nil }

    private var api: MusingAPI? { AIConfig.backendURL.map { MusingAPI(baseURL: $0) } }

    init() {
        sessionToken = Keychain.string(for: Self.sessionAccount)
        hasConsented = UserDefaults.standard.bool(forKey: Self.consentKey)
    }

    func setConsent(_ consented: Bool) {
        hasConsented = consented
        UserDefaults.standard.set(consented, forKey: Self.consentKey)
    }

    /// Finishes Sign in with Apple by trading Apple's identity token for a Musing session.
    func completeSignIn(with authorization: ASAuthorization) async throws {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let identityToken = String(data: tokenData, encoding: .utf8) else {
            throw APIError.invalidResponse
        }
        guard let api else { throw APIError.notConfigured }
        let code = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
        let response = try await api.signIn(identityToken: identityToken, authorizationCode: code)
        Keychain.set(credential.user, for: Self.appleUserAccount)
        setSession(response.sessionToken)
        await refreshUsage()
    }

    func signOut() {
        setSession(nil)
        Keychain.set(nil, for: Self.appleUserAccount)
        usage = nil
    }

    /// Deletes the account and its data on the server (App Store guideline 5.1.1(v)).
    func deleteAccount() async throws {
        guard let api else { throw APIError.notConfigured }
        guard let token = sessionToken else { throw APIError.unauthorized }
        try await api.deleteAccount(token: token)
        signOut()
        setConsent(false)
    }

    func refreshUsage() async {
        guard let api, let token = sessionToken else { return }
        do {
            usage = try await api.me(token: token).usage
        } catch APIError.unauthorized {
            signOut()
        } catch {
            // Usage is informational; keep the last known value.
        }
    }

    /// Sends the conversation to Claude for its next step.
    func agentTurn(messages: [WireMessage], tools: [String]) async throws -> AgentReply {
        guard let api else { throw APIError.notConfigured }
        guard let token = sessionToken else { throw APIError.unauthorized }
        do {
            let reply = try await api.agentTurn(messages: messages, tools: tools, token: token)
            usage = reply.usage
            return reply
        } catch APIError.unauthorized {
            signOut()
            throw APIError.unauthorized
        }
    }

    /// Signs in to the local dev server without Apple (Debug builds only).
    func devSignIn() async throws {
        guard let api else { throw APIError.notConfigured }
        let response = try await api.devSignIn()
        setSession(response.sessionToken)
        await refreshUsage()
    }

    /// Signs out if the person revoked Musing's access in Settings → Apple ID.
    func verifyAppleCredential() async {
        guard let userID = Keychain.string(for: Self.appleUserAccount) else { return }
        let state = await withCheckedContinuation { continuation in
            ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userID) { state, _ in
                continuation.resume(returning: state)
            }
        }
        if state == .revoked || state == .notFound {
            signOut()
        }
    }

    private func setSession(_ token: String?) {
        sessionToken = token
        Keychain.set(token, for: Self.sessionAccount)
    }
}
