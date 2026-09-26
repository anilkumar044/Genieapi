import Foundation

struct AIUsage: Decodable, Equatable {
    let used: Int
    let limit: Int
}

/// One message on the wire: role + Claude content blocks.
struct WireMessage: Encodable {
    let role: String
    let content: [JSONValue]
}

struct AgentReply: Decodable {
    let content: [JSONValue]
    let stopReason: String?
    let usage: AIUsage
}

enum APIError: LocalizedError {
    case notConfigured
    case unauthorized
    case quotaExceeded(String)
    case conversationInvalid(String)
    case server(code: String, message: String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "The assistant isn't connected to a server yet. Deploy the backend and paste its URL into AIConfig.swift."
        case .unauthorized:
            "Please sign in again."
        case .quotaExceeded(let message), .conversationInvalid(let message):
            message
        case .server(_, let message):
            message
        case .invalidResponse:
            "The server sent an unexpected response."
        }
    }
}

/// Talks to the Musing backend (a Lambda function URL in front of Claude on Amazon Bedrock).
struct MusingAPI {
    let baseURL: URL
    var session: URLSession = .shared

    struct SignInResponse: Decodable {
        let sessionToken: String
        let expiresAt: String
        let userId: String
    }

    struct MeResponse: Decodable {
        let userId: String
        let usage: AIUsage
    }

    private struct ErrorBody: Decodable {
        struct Detail: Decodable {
            let code: String
            let message: String
        }
        let error: Detail
    }

    private struct SignInBody: Encodable {
        let identityToken: String
        let authorizationCode: String?
    }

    private struct AgentBody: Encodable {
        let messages: [WireMessage]
        let tools: [String]
    }

    func signIn(identityToken: String, authorizationCode: String?) async throws -> SignInResponse {
        let body = try JSONEncoder().encode(SignInBody(identityToken: identityToken, authorizationCode: authorizationCode))
        return try decode(await send("POST", "v1/auth/apple", body: body))
    }

    /// Local dev server only.
    func devSignIn() async throws -> SignInResponse {
        try decode(await send("POST", "v1/auth/dev", body: Data("{}".utf8)))
    }

    func me(token: String) async throws -> MeResponse {
        try decode(await send("GET", "v1/me", token: token))
    }

    func agentTurn(messages: [WireMessage], tools: [String], token: String) async throws -> AgentReply {
        let body = try JSONEncoder().encode(AgentBody(messages: messages, tools: tools))
        return try decode(await send("POST", "v1/agent", body: body, token: token))
    }

    func deleteAccount(token: String) async throws {
        _ = try await send("DELETE", "v1/account", token: token)
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.invalidResponse
        }
    }

    private func send(_ method: String, _ path: String, body: Data? = nil, token: String? = nil) async throws -> Data {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        // A step with thinking can take a while; the backend allows up to two minutes.
        request.timeoutInterval = 150
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let detail = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error
            let message = detail?.message ?? "The server returned an error (\(http.statusCode))."
            switch (http.statusCode, detail?.code ?? "") {
            case (401, _): throw APIError.unauthorized
            case (_, "quota_exceeded"): throw APIError.quotaExceeded(message)
            case (_, "conversation_invalid"), (_, "conversation_too_long"): throw APIError.conversationInvalid(message)
            default: throw APIError.server(code: detail?.code ?? "http_\(http.statusCode)", message: message)
            }
        }
        return data
    }
}
