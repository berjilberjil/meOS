import Foundation

// Free live/last stock prices via Yahoo Finance — no API key, no token, nothing to
// regenerate. Called directly from the app (native, no CORS). Covers NSE (ITC.NS),
// BSE (TCS.BO) and US (AAPL). Non-INR quotes are converted to INR using Yahoo's own
// FX rate (e.g. USDINR=X), so the portfolio stays in rupees.
enum MarketDataClient {
    struct Quote { let price: Double; let currency: String }

    /// Last price for each ticker, already converted to INR. Tickers Yahoo can't
    /// resolve (or that get momentarily rate-limited) are skipped, not fatal.
    static func pricesInINR(_ symbols: [String]) async throws -> [String: Double] {
        let syms = Array(Set(symbols.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }))
        guard !syms.isEmpty else { return [:] }

        var quotes: [String: Quote] = [:]
        for s in syms {
            if let q = try await quote(s) { quotes[s] = q }
        }
        guard !quotes.isEmpty else {
            throw MarketDataError.message("Couldn't fetch prices right now — Yahoo may be rate-limiting. Try again in a minute.")
        }

        // FX rates (currency → INR) for any non-INR quotes.
        var fx: [String: Double] = ["INR": 1]
        for cur in Set(quotes.values.map { $0.currency.uppercased() }).subtracting(["INR"]) {
            if let rate = try? await quote("\(cur)INR=X")?.price, rate > 0 { fx[cur] = rate }
        }

        var out: [String: Double] = [:]
        for (sym, q) in quotes {
            guard let rate = fx[q.currency.uppercased()] else { continue }  // no FX → skip
            out[sym] = q.price * rate
        }
        return out
    }

    // MARK: - Yahoo chart endpoint (no auth)

    private static func quote(_ symbol: String) async throws -> Quote? {
        guard let enc = symbol.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed),
              let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(enc)?interval=1d&range=1d")
        else { return nil }

        var req = URLRequest(url: url)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        // A browser UA — Yahoo blocks the default URLSession agent.
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36",
                     forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return nil  // 429 / not-found → skip this ticker, keep its old value
        }
        struct R: Decodable {
            struct Chart: Decodable { let result: [Item]? }
            struct Item: Decodable { let meta: Meta }
            struct Meta: Decodable { let regularMarketPrice: Double?; let currency: String? }
            let chart: Chart
        }
        guard let m = (try? JSONDecoder().decode(R.self, from: data))?.chart.result?.first?.meta,
              let p = m.regularMarketPrice else { return nil }
        return Quote(price: p, currency: (m.currency ?? "INR").uppercased())
    }
}

enum MarketDataError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let m) = self { return m }; return nil }
}
