import Foundation

// Groww trade API — live market data (LTP). Called directly from the app (native,
// no CORS). Needs a Groww access token, which resets daily at 6 AM; the user pastes
// the current token in Settings. Docs: https://groww.in/trade-api/docs
enum GrowwClient {
    /// Last traded price for CASH-segment symbols (e.g. "NSE_ITC"). Returns a
    /// symbol → price map. Throws with a readable message on failure.
    static func ltp(symbols: [String], token: String) async throws -> [String: Double] {
        guard !symbols.isEmpty else { return [:] }
        var comps = URLComponents(string: "https://api.groww.in/v1/live-data/ltp")!
        comps.queryItems = [
            URLQueryItem(name: "segment", value: "CASH"),
            URLQueryItem(name: "exchange_symbols", value: symbols.joined(separator: ","))
        ]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("1.0", forHTTPHeaderField: "X-API-VERSION")
        req.timeoutInterval = 20

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw GrowwError.message("No response from Groww")
        }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 { throw GrowwError.message("Groww token invalid or expired — regenerate it (tokens reset daily at 6 AM).") }
            throw GrowwError.message("Groww error \(http.statusCode): \(bodyMessage(data))")
        }
        struct R: Decodable { let status: String?; let payload: [String: Double]? }
        let decoded = try JSONDecoder().decode(R.self, from: data)
        return decoded.payload ?? [:]
    }

    private static func bodyMessage(_ data: Data) -> String {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let m = obj["message"] as? String { return m }
            if let e = obj["error"] as? [String: Any], let m = e["message"] as? String { return m }
        }
        return String(data: data.prefix(140), encoding: .utf8) ?? "request failed"
    }
}

enum GrowwError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let m) = self { return m }; return nil }
}
