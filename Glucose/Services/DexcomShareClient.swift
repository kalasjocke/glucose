import Foundation
import os

enum DexcomRegion: String, CaseIterable, Identifiable, Codable, Sendable {
    case ous
    case us

    var id: String { rawValue }

    var host: String {
        switch self {
        case .ous: return "shareous1.dexcom.com"
        case .us:  return "share2.dexcom.com"
        }
    }

    var label: String {
        switch self {
        case .ous: return "Outside US"
        case .us:  return "United States"
        }
    }
}

enum DexcomShareError: LocalizedError, Sendable {
    case missingCredentials
    case invalidCredentials
    case server(code: String, message: String)
    case http(status: Int, body: String)
    case decoding(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "Missing Dexcom Share credentials."
        case .invalidCredentials:
            return "Invalid Dexcom Share username or password."
        case .server(let code, let message):
            return "Dexcom server error: \(code) — \(message)"
        case .http(let status, _):
            return "Dexcom HTTP \(status)"
        case .decoding(let message):
            return "Could not decode Dexcom response: \(message)"
        case .network(let message):
            return "Network error: \(message)"
        }
    }
}

actor DexcomShareClient {
    static let applicationId = "d89443d2-327c-4a6f-89e5-496bbb0317db"
    static let userAgent = "Dexcom Share/3.0.2.11 CFNetwork/672.0.2 Darwin/14.0.0"

    private let log = Logger(subsystem: "se.kalasjocke.glucose", category: "DexcomShare")
    private let session: URLSession
    private var region: DexcomRegion
    private var credentials: KeychainStore.Credentials?
    private var sessionId: String?

    init(region: DexcomRegion = .ous, credentials: KeychainStore.Credentials? = nil) {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 15
        cfg.timeoutIntervalForResource = 30
        cfg.httpAdditionalHeaders = [
            "User-Agent": Self.userAgent,
            "Accept": "application/json"
        ]
        self.session = URLSession(configuration: cfg)
        self.region = region
        self.credentials = credentials
    }

    func setRegion(_ region: DexcomRegion) {
        if self.region != region {
            self.region = region
            self.sessionId = nil
        }
    }

    func setCredentials(_ creds: KeychainStore.Credentials?) {
        self.credentials = creds
        self.sessionId = nil
    }

    func authenticate() async throws {
        guard let creds = credentials else { throw DexcomShareError.missingCredentials }
        let accountId = try await postString(
            path: "/ShareWebServices/Services/General/AuthenticatePublisherAccount",
            body: [
                "accountName": creds.account,
                "password": creds.password,
                "applicationId": Self.applicationId
            ]
        )
        guard accountId != "00000000-0000-0000-0000-000000000000" else {
            throw DexcomShareError.invalidCredentials
        }
        let sid = try await postString(
            path: "/ShareWebServices/Services/General/LoginPublisherAccountById",
            body: [
                "accountId": accountId,
                "password": creds.password,
                "applicationId": Self.applicationId
            ]
        )
        guard sid != "00000000-0000-0000-0000-000000000000" else {
            throw DexcomShareError.invalidCredentials
        }
        self.sessionId = sid
        log.info("Authenticated, sessionId acquired")
    }

    func latestReadings(minutes: Int = 1440, maxCount: Int = 288) async throws -> [GlucoseReading] {
        do {
            return try await fetchReadings(minutes: minutes, maxCount: maxCount)
        } catch DexcomShareError.server(let code, _) where code == "SessionIdNotFound" || code == "SessionNotValid" {
            log.notice("Session expired, re-authenticating")
            sessionId = nil
            try await authenticate()
            return try await fetchReadings(minutes: minutes, maxCount: maxCount)
        } catch DexcomShareError.http(let status, _) where status == 500 {
            log.notice("HTTP 500 on read, re-authenticating once")
            sessionId = nil
            try await authenticate()
            return try await fetchReadings(minutes: minutes, maxCount: maxCount)
        }
    }

    private func fetchReadings(minutes: Int, maxCount: Int) async throws -> [GlucoseReading] {
        if sessionId == nil { try await authenticate() }
        guard let sid = sessionId else { throw DexcomShareError.invalidCredentials }
        var components = URLComponents()
        components.scheme = "https"
        components.host = region.host
        components.path = "/ShareWebServices/Services/Publisher/ReadPublisherLatestGlucoseValues"
        components.queryItems = [
            URLQueryItem(name: "sessionId", value: sid),
            URLQueryItem(name: "minutes", value: String(minutes)),
            URLQueryItem(name: "maxCount", value: String(maxCount))
        ]
        guard let url = components.url else { throw DexcomShareError.decoding("bad url") }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data("{}".utf8)

        let (data, response) = try await dataTask(req)
        guard let http = response as? HTTPURLResponse else {
            throw DexcomShareError.network("no http response")
        }
        if let err = parseShareError(data: data) { throw err }
        guard (200..<300).contains(http.statusCode) else {
            throw DexcomShareError.http(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        return try decodeReadings(data: data)
    }

    private func postString(path: String, body: [String: String]) async throws -> String {
        var components = URLComponents()
        components.scheme = "https"
        components.host = region.host
        components.path = path
        guard let url = components.url else { throw DexcomShareError.decoding("bad url") }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await dataTask(req)
        guard let http = response as? HTTPURLResponse else {
            throw DexcomShareError.network("no http response")
        }
        if let err = parseShareError(data: data) { throw err }
        guard (200..<300).contains(http.statusCode) else {
            throw DexcomShareError.http(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        // The endpoint returns a JSON-quoted UUID string: "ABCD-..."
        guard var raw = String(data: data, encoding: .utf8) else {
            throw DexcomShareError.decoding("non-utf8 response")
        }
        raw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("\"") && raw.hasSuffix("\"") {
            raw = String(raw.dropFirst().dropLast())
        }
        return raw
    }

    private func dataTask(_ req: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: req)
        } catch {
            throw DexcomShareError.network(error.localizedDescription)
        }
    }

    private func parseShareError(data: Data) -> DexcomShareError? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code = obj["Code"] as? String else {
            return nil
        }
        let message = obj["Message"] as? String ?? ""
        switch code {
        case "AccountPasswordInvalid", "SSO_AuthenticateAccountNotFound", "SSO_AuthenticatePasswordInvalid":
            return .invalidCredentials
        default:
            return .server(code: code, message: message)
        }
    }

    private func decodeReadings(data: Data) throws -> [GlucoseReading] {
        guard let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw DexcomShareError.decoding("expected array")
        }
        return array.compactMap { entry -> GlucoseReading? in
            guard let value = entry["Value"] as? Double else { return nil }
            guard let dt = entry["WT"] as? String ?? entry["ST"] as? String ?? entry["DT"] as? String else {
                return nil
            }
            guard let date = Self.parseDexcomDate(dt) else { return nil }
            let trend = TrendDirection(rawAny: entry["Trend"])
            return GlucoseReading(date: date, mgdl: value, trend: trend)
        }
        .sorted { $0.date < $1.date }
    }

    static func parseDexcomDate(_ s: String) -> Date? {
        // Format: /Date(1715419260000+0000)/  or /Date(1715419260000)/
        guard let openParen = s.firstIndex(of: "("),
              let closeParen = s.firstIndex(of: ")") else { return nil }
        var inner = s[s.index(after: openParen)..<closeParen]
        if let plus = inner.firstIndex(of: "+") {
            inner = inner[..<plus]
        } else if let minus = inner.firstIndex(of: "-") {
            inner = inner[..<minus]
        }
        guard let ms = Double(inner) else { return nil }
        return Date(timeIntervalSince1970: ms / 1000.0)
    }
}
