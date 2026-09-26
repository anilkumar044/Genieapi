import Foundation

/// Connects the app to your Musing backend on AWS (see `Musing/backend/README.md`).
enum AIConfig {
    /// After `npx cdk deploy`, paste the `ApiUrl` output here,
    /// e.g. "https://abc123xyz.lambda-url.us-east-1.on.aws/". Leave empty to hide AI features' network calls.
    static let backendURLString = ""

    static var backendURL: URL? {
        let trimmed = backendURLString.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : URL(string: trimmed)
    }

    /// Shown to people before their content is shared (App Store guideline 5.1.2).
    static let providerDescription = "Anthropic's Claude, running on Amazon Bedrock (AWS)"
}
