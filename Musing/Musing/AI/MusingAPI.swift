import Foundation

// MARK: - Wire types (mirror `Musing/backend/src/ai.ts`)

enum AIAction: String, Encodable {
    case summarize, organize, expand, handwriting, ask
    case photoNotes = "photo_notes"

    var progressLabel: String {
        switch self {
        case .summarize: "Summarizing board…"
        case .organize: "Organizing board…"
        case .expand: "Expanding idea…"
        case .handwriting: "Reading handwriting…"
        case .photoNotes: "Reading photo…"
        case .ask: "Thinking…"
        }
    }
}

struct AIRequest: Encodable {
    struct CardPayload: Encodable {
        let id: String
        let kind: String
        var text: String?
        var url: String?
        var linkTitle: String?
        var childTitle: String?
    }

    struct BoardPayload: Encodable {
        let title: String
        let cards: [CardPayload]
    }

    struct ImagePayload: Encodable {
        let mediaType: String
        let data: String
    }

    let action: AIAction
    let board: BoardPayload
    var focusCardId: String?
    var question: String?
    var image: ImagePayload?
}

struct AIResult: Decodable {
    struct Group: Decodable {
        let title: String
        let cardIds: [String]
    }

    var title: String?
    var summary: String?
    var groups: [Group]?
    var ideas: [String]?
    var text: String?
    var notes: [String]?
    var answer: String?
}

struct AIUsage: Decodable, Equatable {
    let used: Int
    let limit: Int
}

enum APIError: LocalizedError {
    case notConfigured
    case unauthorized
    case quotaExceeded(String)
    case server(code: String, message: String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "AI isn't set up yet. Deploy the backend and paste its URL into AIConfig.swift."
        case .unauthorized:
            "Please sign in again."
        case .quotaExceeded(let message):
            message
        case .server(_, let message):
            message
        case .invalidResponse:
            "The server sent an unexpected response."
        }
    }
}

// MARK: - Client

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

    struct AIResponse: Decodable {
        let result: AIResult
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

    func signIn(identityToken: String, authorizationCode: String?) async throws -> SignInResponse {
        let body = try JSONEncoder().encode(SignInBody(identityToken: identityToken, authorizationCode: authorizationCode))
        return try decode(await send("POST", "v1/auth/apple", body: body))
    }

    func me(token: String) async throws -> MeResponse {
        try decode(await send("GET", "v1/me", token: token))
    }

    func run(_ request: AIRequest, token: String) async throws -> AIResponse {
        try decode(await send("POST", "v1/ai", body: try JSONEncoder().encode(request), token: token))
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
        // Claude can take a while on bigger boards; the backend allows up to two minutes.
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
            if http.statusCode == 401 { throw APIError.unauthorized }
            if detail?.code == "quota_exceeded" {
                throw APIError.quotaExceeded(detail?.message ?? "You've reached today's AI limit.")
            }
            throw APIError.server(
                code: detail?.code ?? "http_\(http.statusCode)",
                message: detail?.message ?? "The server returned an error (\(http.statusCode))."
            )
        }
        return data
    }
}
