import Foundation

/// Talks to the headless SvelteKit backend (apps/web). Auth is the server's
/// httpOnly cookie session (`myos_session`) — URLSession's shared cookie storage
/// persists and re-sends it automatically, so there's no token to manage.
struct APIError: LocalizedError {
    let status: Int
    let message: String
    var errorDescription: String? { message }
}

final class APIClient {
    /// Dev default is the local SvelteKit server. Override at runtime by setting
    /// the `myos.baseURL` UserDefaults key (e.g. your deployed HTTPS domain).
    static var baseURL: URL {
        if let s = UserDefaults.standard.string(forKey: "myos.baseURL"),
           let u = URL(string: s) { return u }
        return URL(string: "http://localhost:5173")!
    }

    private let session: URLSession
    /// AI calls (parse / vision / advice) can take longer than a state read —
    /// Gemini vision on a screenshot, or the weekly reasoning model. Give them room.
    private let aiSession: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init() {
        let cfg = URLSessionConfiguration.default
        cfg.httpCookieStorage = .shared
        cfg.httpCookieAcceptPolicy = .always
        cfg.httpShouldSetCookies = true
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.waitsForConnectivity = false
        cfg.timeoutIntervalForRequest = 15
        cfg.timeoutIntervalForResource = 30
        session = URLSession(configuration: cfg)

        let ai = cfg.copy() as! URLSessionConfiguration
        ai.timeoutIntervalForRequest = 90
        ai.timeoutIntervalForResource = 120
        aiSession = URLSession(configuration: ai)
    }

    // MARK: - Core

    @discardableResult
    private func request(_ method: String, _ path: String, body: Encodable? = nil,
                         using session: URLSession? = nil) async throws -> Data {
        var req = URLRequest(url: Self.baseURL.appendingPathComponent(path))
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try encoder.encode(AnyEncodable(body))
        }
        let (data, response) = try await (session ?? self.session).data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw APIError(status: -1, message: "No response from server")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError(status: http.statusCode, message: Self.errorText(from: data, status: http.statusCode))
        }
        return data
    }

    private func get<T: Decodable>(_ path: String, as: T.Type) async throws -> T {
        try decoder.decode(T.self, from: try await request("GET", path))
    }

    // MARK: - Auth

    @discardableResult
    func login(username: String, password: String) async throws -> AuthUser {
        let data = try await request("POST", "api/auth/login", body: ["username": username, "password": password])
        return try decoder.decode(AuthUser.self, from: data)
    }

    @discardableResult
    func register(username: String, password: String) async throws -> AuthUser {
        let data = try await request("POST", "api/auth/register", body: ["username": username, "password": password])
        return try decoder.decode(AuthUser.self, from: data)
    }

    func me() async throws -> AuthUser { try await get("api/me", as: AuthUser.self) }

    func logout() async { _ = try? await request("POST", "api/auth/logout") }

    // MARK: - State

    func state() async throws -> AppStatePayload {
        let data = try await request("GET", "api/state")
        let value = try decoder.decode(AppStatePayload.self, from: data)
        Self.writeCache(data, "state.json")
        return value
    }

    /// Upsert one myos.* key. Fire-and-forget from callers.
    func putState(_ key: String, _ value: Encodable) async throws {
        _ = try await request("PUT", "api/state/\(key)", body: value)
    }

    // MARK: - AI

    func parse(text: String) async throws -> ParseResult {
        let data = try await request("POST", "api/parse", body: ["text": text], using: aiSession)
        return try decoder.decode(ParseResult.self, from: data)
    }

    /// Read one or more screenshots. mode: "transactions" or "portfolio".
    func parseImage(imagesBase64: [String], mediaType: String, mode: String) async throws -> ImageParseResult {
        let body = ImageRequest(images: imagesBase64, mediaType: mediaType, mode: mode)
        let data = try await request("POST", "api/parse-image", body: body, using: aiSession)
        return try decoder.decode(ImageParseResult.self, from: data)
    }

    /// Weekly portfolio review, grounded server-side in the finance principles.
    func advise(_ payload: AdviceRequest) async throws -> PortfolioAdvice {
        let data = try await request("POST", "api/advise", body: payload, using: aiSession)
        return try decoder.decode(PortfolioAdvice.self, from: data)
    }

    /// Mentor chat. Sends the conversation + a data snapshot + who the assistant
    /// should be (name / tone / custom style); returns the reply.
    func chat(messages: [ChatTurn], context: String, agent: AgentInfo) async throws -> String {
        let body = ChatRequest(messages: messages, context: context, agent: agent)
        let data = try await request("POST", "api/chat", body: body, using: aiSession)
        return try decoder.decode(ChatReply.self, from: data).reply
    }

    /// Today's "what to do now" mentor nudge from a data snapshot.
    func suggest(context: String) async throws -> SuggestResult {
        let data = try await request("POST", "api/suggest", body: ["context": context], using: aiSession)
        return try decoder.decode(SuggestResult.self, from: data)
    }

    /// Recent tech + finance news (Gemini search-grounded).
    func news() async throws -> NewsResult {
        let data = try await request("POST", "api/news", body: [String: String](), using: aiSession)
        return try decoder.decode(NewsResult.self, from: data)
    }

    /// Static anatomy body-map data (front/back SVG + muscle groups). Cached to disk.
    func anatomy() async throws -> AnatomyData {
        let data = try await request("GET", "api/anatomy")
        let value = try decoder.decode(AnatomyData.self, from: data)
        Self.writeCache(data, "anatomy.json")
        return value
    }
    func cachedAnatomy() -> AnatomyData? {
        guard let d = try? Data(contentsOf: Self.cacheDir.appendingPathComponent("anatomy.json")) else { return nil }
        return try? decoder.decode(AnatomyData.self, from: d)
    }

    /// Generate a weekly workout + meal plan from the goal, targets and library.
    func plan(_ req: PlanRequest) async throws -> GeneratedPlan {
        let data = try await request("POST", "api/plan", body: req, using: aiSession)
        return try decoder.decode(GeneratedPlan.self, from: data)
    }
    struct PlanRequest: Encodable {
        let goal: String
        let calories: Int
        let protein: Int
        let daysPerWeek: Int
        let foods: [String]
        let exercises: [String]
    }

    private struct ImageRequest: Encodable {
        let images: [String]
        let mediaType: String
        let mode: String
    }
    struct ChatTurn: Encodable { let role: String; let content: String }
    struct AgentInfo: Encodable { let name: String; let tone: String; let custom: String }
    private struct ChatRequest: Encodable { let messages: [ChatTurn]; let context: String; let agent: AgentInfo }
    private struct ChatReply: Decodable { let reply: String }

    // MARK: - Instant-relaunch cache

    private static let cacheDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("MyOS", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static func writeCache(_ data: Data, _ name: String) {
        try? data.write(to: cacheDir.appendingPathComponent(name), options: .atomic)
    }

    func cachedState() -> AppStatePayload? {
        guard let d = try? Data(contentsOf: Self.cacheDir.appendingPathComponent("state.json")) else { return nil }
        return try? decoder.decode(AppStatePayload.self, from: d)
    }

    func clearCache() {
        try? FileManager.default.removeItem(at: Self.cacheDir.appendingPathComponent("state.json"))
    }

    // MARK: - Helpers

    private static func errorText(from data: Data, status: Int) -> String {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let m = obj["message"] as? String { return m }
            if let e = obj["error"] as? [String: Any], let m = e["message"] as? String { return m }
        }
        return "Request failed (\(status))"
    }
}

/// Type-erasing wrapper so any `Encodable` can be encoded through a generic path.
struct AnyEncodable: Encodable {
    private let encodeFunc: (Encoder) throws -> Void
    init(_ wrapped: Encodable) { encodeFunc = wrapped.encode }
    func encode(to encoder: Encoder) throws { try encodeFunc(encoder) }
}
