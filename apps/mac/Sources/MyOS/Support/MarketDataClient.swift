import Foundation

// Free live/last stock prices via Yahoo Finance — no API key, no token, nothing to
// regenerate. Called directly from the app (native, no CORS). Covers NSE (ITC.NS),
// BSE (TCS.BO) and US (AAPL). Non-INR quotes are converted to INR using Yahoo's own
// FX rate (e.g. USDINR=X), so the portfolio stays in rupees.
//
// It uses Yahoo's BATCH quote endpoint: one request covers the whole portfolio,
// which avoids the per-symbol burst that trips Yahoo's aggressive IP rate limiter.
// The cookie + crumb handshake is cached and only re-done when it goes stale (401).
enum MarketDataClient {
    struct Quote { let price: Double; let currency: String }

    private static let ua = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"
    private static var cachedCrumb: String?

    /// Last price for each ticker, already converted to INR. Tickers Yahoo can't
    /// resolve are simply absent from the result.
    static func pricesInINR(_ symbols: [String]) async throws -> [String: Double] {
        let syms = Array(Set(symbols.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }))
        guard !syms.isEmpty else { return [:] }

        let quotes = try await batchQuotes(syms)
        guard !quotes.isEmpty else {
            throw MarketDataError.message("Couldn't fetch prices right now — Yahoo may be rate-limiting. Try again in a minute.")
        }

        // FX rates (currency → INR) for any non-INR quotes, in one more batch call.
        var fx: [String: Double] = ["INR": 1]
        let currencies = Set(quotes.values.map { $0.currency.uppercased() }).subtracting(["INR"])
        if !currencies.isEmpty {
            let fxQuotes = (try? await batchQuotes(currencies.map { "\($0)INR=X" })) ?? [:]
            for (pair, q) in fxQuotes {
                fx[pair.replacingOccurrences(of: "INR=X", with: "").uppercased()] = q.price
            }
        }

        var out: [String: Double] = [:]
        for (sym, q) in quotes {
            guard let rate = fx[q.currency.uppercased()] else { continue }  // no FX → skip
            out[sym] = q.price * rate
        }
        return out
    }

    // MARK: - Yahoo batch quote

    private static func batchQuotes(_ symbols: [String]) async throws -> [String: Quote] {
        // Try with the cached crumb; on 401 (stale), refresh once and retry.
        for attempt in 0..<2 {
            let crumb = try await ensureCrumb(force: attempt > 0)
            var comps = URLComponents(string: "https://query1.finance.yahoo.com/v7/finance/quote")!
            comps.queryItems = [
                URLQueryItem(name: "symbols", value: symbols.joined(separator: ",")),
                URLQueryItem(name: "crumb", value: crumb)
            ]
            guard let url = comps.url else { return [:] }
            var req = URLRequest(url: url)
            req.setValue(ua, forHTTPHeaderField: "User-Agent")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.timeoutInterval = 15

            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if code == 401 { cachedCrumb = nil; continue }         // stale crumb → refresh + retry
            guard (200..<300).contains(code) else { return [:] }   // 429 / error → nothing this round

            struct R: Decodable {
                struct QR: Decodable {
                    struct Q: Decodable { let symbol: String?; let regularMarketPrice: Double?; let currency: String? }
                    let result: [Q]?
                }
                let quoteResponse: QR
            }
            guard let result = (try? JSONDecoder().decode(R.self, from: data))?.quoteResponse.result else { return [:] }
            var out: [String: Quote] = [:]
            for q in result {
                if let s = q.symbol, let p = q.regularMarketPrice {
                    out[s] = Quote(price: p, currency: (q.currency ?? "INR").uppercased())
                }
            }
            return out
        }
        return [:]
    }

    /// Yahoo requires a consent cookie + a "crumb" token on the quote endpoint.
    /// Cached and reused; refreshed only when forced (after a 401).
    private static func ensureCrumb(force: Bool) async throws -> String {
        if !force, let c = cachedCrumb { return c }

        // 1) Hit a Yahoo host to receive the consent cookie (URLSession.shared stores it).
        var cookieReq = URLRequest(url: URL(string: "https://fc.yahoo.com/")!)
        cookieReq.setValue(ua, forHTTPHeaderField: "User-Agent")
        _ = try? await URLSession.shared.data(for: cookieReq)

        // 2) Exchange the cookie for a crumb.
        var crumbReq = URLRequest(url: URL(string: "https://query1.finance.yahoo.com/v1/test/getcrumb")!)
        crumbReq.setValue(ua, forHTTPHeaderField: "User-Agent")
        crumbReq.setValue("*/*", forHTTPHeaderField: "Accept")
        let (data, resp) = try await URLSession.shared.data(for: crumbReq)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code),
              let c = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !c.isEmpty, !c.localizedCaseInsensitiveContains("too many") else {
            throw MarketDataError.message("Yahoo is rate-limiting right now. Try again in a minute.")
        }
        cachedCrumb = c
        return c
    }
}

enum MarketDataError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let m) = self { return m }; return nil }
}
