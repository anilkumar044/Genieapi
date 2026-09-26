import Foundation

/// Connects the app to the Musing backend (see `Musing/backend/README.md`).
enum AIConfig {
    /// Your deployed backend: after `npx cdk deploy`, paste the `ApiUrl` output here,
    /// e.g. "https://abc123xyz.lambda-url.us-east-1.on.aws/".
    static let deployedURLString = ""

    /// Debug builds talk to the local dev server (`npm run dev` in `backend/`) unless a deployed URL is set.
    /// The Simulator reaches your Mac as `localhost`; a physical iPhone needs your Mac's network address instead.
    static let localDevURLString = "http://localhost:8787/"

    static var backendURL: URL? {
        let deployed = deployedURLString.trimmingCharacters(in: .whitespaces)
        if !deployed.isEmpty { return URL(string: deployed) }
        #if DEBUG
        return URL(string: localDevURLString)
        #else
        return nil
        #endif
    }

    /// True when talking to the local dev server, which allows signing in without Apple.
    static var isLocalDevServer: Bool {
        guard let host = backendURL?.host() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host.hasSuffix(".local")
    }

    /// Shown to people before their content is shared (App Store guideline 5.1.2).
    static let providerDescription = "Anthropic's Claude, running on Amazon Bedrock (AWS)"
}
