import Foundation
import SwiftData
import AuthenticationServices
import UIKit

@MainActor @Observable
final class WHOOPService: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = WHOOPService()
    private let tokenAccount = "whoop_tokens_v2"
    private var authenticationSession: ASWebAuthenticationSession?
    var syncing = false
    var connecting = false
    var message: String?
    var lastSync: Date? { UserDefaults.standard.object(forKey: "whoopLastSync") as? Date }
    var isConnected: Bool { tokens != nil }
    var brokerURL: String {
        get { UserDefaults.standard.string(forKey: "whoopBrokerURL") ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "whoopBrokerURL") }
    }

    struct Tokens: Codable {
        let accessToken: String
        let refreshToken: String?
        let expiresAt: Date
    }
    private var tokens: Tokens? {
        guard let text = KeychainService.read(account: tokenAccount), let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Tokens.self, from: data)
    }
    private func save(_ value: Tokens) throws {
        let data = try JSONEncoder().encode(value)
        guard let text = String(data: data, encoding: .utf8), KeychainService.save(text, account: tokenAccount) else {
            throw WHOOPError.storage
        }
    }
    private func endpoint(_ path: String) throws -> URL {
        guard let base = URL(string: brokerURL), base.scheme == "https", base.host != nil,
              base.user == nil, base.password == nil, base.query == nil, base.fragment == nil else {
            throw WHOOPError.broker
        }
        return base.appendingPathComponent(path)
    }

    func connect(context: ModelContext) async {
        guard !connecting, !syncing else { return }
        connecting = true; message = nil
        defer { connecting = false; authenticationSession = nil }
        do {
            let state = UUID().uuidString + UUID().uuidString
            var url = URLComponents(url: try endpoint("authorize"), resolvingAgainstBaseURL: false)!
            url.queryItems = [URLQueryItem(name: "state", value: state)]
            let callback: URL = try await withCheckedThrowingContinuation { continuation in
                let session = ASWebAuthenticationSession(url: url.url!, callbackURLScheme: "lockedinfit-whoop") { callback, error in
                    if let error { continuation.resume(throwing: error) }
                    else if let callback { continuation.resume(returning: callback) }
                    else { continuation.resume(throwing: WHOOPError.authorization) }
                }
                session.presentationContextProvider = self
                authenticationSession = session
                if !session.start() { continuation.resume(throwing: WHOOPError.authorization) }
            }
            let fields = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
            guard callback.scheme == "lockedinfit-whoop", callback.host == "callback",
                  fields.first(where: { $0.name == "state" })?.value == state,
                  let ticket = fields.first(where: { $0.name == "ticket" })?.value else { throw WHOOPError.authorization }
            let response = try await brokerRequest("exchange", body: ["ticket": ticket, "state": state])
            try save(parseTokens(response))
            await sync(context: context, days: 30)
        } catch { message = error.localizedDescription }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }

    private func brokerRequest(_ path: String, body: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: try endpoint(path))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw WHOOPError.authorization }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw WHOOPError.response }
        return object
    }
    private func parseTokens(_ response: [String: Any]) throws -> Tokens {
        guard let access = response["access_token"] as? String, !access.isEmpty,
              let expires = response["expires_in"] as? Double, expires > 0 else { throw WHOOPError.response }
        return Tokens(accessToken: access, refreshToken: response["refresh_token"] as? String,
                      expiresAt: Date().addingTimeInterval(expires))
    }
    private func accessToken(forceRefresh: Bool = false) async throws -> String {
        guard let current = tokens else { throw WHOOPError.authorization }
        if !forceRefresh, current.expiresAt.timeIntervalSinceNow > 120 { return current.accessToken }
        guard let refresh = current.refreshToken else { throw WHOOPError.authorization }
        let renewed = try parseTokens(await brokerRequest("refresh", body: ["refresh_token": refresh]))
        try save(renewed)
        return renewed.accessToken
    }

    private func get(_ path: String, query: [URLQueryItem] = [], retry: Bool = true) async throws -> [String: Any] {
        var url = URLComponents(string: "https://api.prod.whoop.com/developer/v2/\(path)")!
        if !query.isEmpty { url.queryItems = query }
        var request = URLRequest(url: url.url!)
        request.timeoutInterval = 30
        request.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw WHOOPError.response }
        if http.statusCode == 401, retry {
            _ = try await accessToken(forceRefresh: true)
            return try await get(path, query: query, retry: false)
        }
        if http.statusCode == 429 { throw WHOOPError.rateLimit }
        guard (200..<300).contains(http.statusCode) else { throw WHOOPError.http(http.statusCode) }
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw WHOOPError.response }
        return value
    }

    private func collection(_ path: String, start: Date) async throws -> [[String: Any]] {
        var records: [[String: Any]] = []
        var token: String?
        var seen = Set<String>()
        repeat {
            var query = [URLQueryItem(name: "limit", value: "25"),
                         URLQueryItem(name: "start", value: ISO8601DateFormatter().string(from: start))]
            if let token { query.append(URLQueryItem(name: "nextToken", value: token)) }
            let response = try await get(path, query: query)
            guard let page = response["records"] as? [[String: Any]] else { throw WHOOPError.response }
            records.append(contentsOf: page)
            token = response["next_token"] as? String
            if token == "" { token = nil }
            if let token, !seen.insert(token).inserted { throw WHOOPError.response }
        } while token != nil
        return records
    }

    func syncIfNeeded(context: ModelContext) async {
        guard isConnected, !connecting, lastSync == nil || Date().timeIntervalSince(lastSync!) > 900 else { return }
        await sync(context: context, days: 7)
    }

    func sync(context: ModelContext, days: Int = 30) async {
        guard isConnected, !syncing else { return }
        syncing = true; message = nil
        defer { syncing = false }
        do {
            let start = Calendar.current.date(byAdding: .day, value: -days, to: .now)!
            // Sequential requests also serialize rotating refresh tokens.
            let cycles = try await collection("cycle", start: start)
            let recovery = try await collection("recovery", start: start)
            let sleep = try await collection("activity/sleep", start: start)
            let workouts = try await collection("activity/workout", start: start)
            let body = try await get("user/measurement/body")
            var cycleDates: [String: Date] = [:]
            for cycle in cycles {
                if let id = cycle["id"] as? NSNumber, let date = WHOOPData.date(cycle["start"]) { cycleDates[id.stringValue] = date }
            }
            var dtos: [ExportImportService.WHOOPDTO] = []
            for (kind, values) in [("cycle", cycles), ("recovery", recovery), ("sleep", sleep), ("workout", workouts), ("body", [body])] {
                for payload in values {
                    guard let key = WHOOPData.identifier(kind: kind, payload: payload),
                          let date = WHOOPData.recordDate(kind: kind, payload: payload, cycles: cycleDates) else { throw WHOOPError.response }
                    let json = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
                    dtos.append(.init(key: key, kind: kind, date: date, json: json, syncedAt: .now))
                }
            }
            try Self.upsert(dtos, context: context)
            try context.save()
            UserDefaults.standard.set(Date(), forKey: "whoopLastSync")
            message = "Synced \(dtos.count) WHOOP records."
            BackupService.scheduleBackupSoon(container: context.container)
        } catch { message = "WHOOP sync failed: \(error.localizedDescription)" }
    }

    nonisolated static func upsert(_ records: [ExportImportService.WHOOPDTO], context: ModelContext) throws {
        let existing = try context.fetch(FetchDescriptor<WHOOPRecord>())
        var byKey: [String: WHOOPRecord] = [:]
        for record in existing {
            if let kept = byKey[record.key] {
                if record.syncedAt > kept.syncedAt { context.delete(kept); byKey[record.key] = record }
                else { context.delete(record) }
            } else { byKey[record.key] = record }
        }
        for dto in records {
            if let record = byKey[dto.key] {
                guard dto.syncedAt >= record.syncedAt else { continue }
                record.json = dto.json; record.date = dto.date; record.syncedAt = dto.syncedAt
            } else {
                let record = WHOOPRecord(key: dto.key, kind: dto.kind, date: dto.date, json: dto.json)
                record.syncedAt = dto.syncedAt
                context.insert(record); byKey[dto.key] = record
            }
        }
    }

    func disconnect() async {
        guard !syncing, !connecting else { return }
        syncing = true
        defer { syncing = false }
        do {
            let token = try await accessToken()
            var request = URLRequest(url: URL(string: "https://api.prod.whoop.com/developer/v2/user/access")!)
            request.httpMethod = "DELETE"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 204 || http.statusCode == 401 else { throw WHOOPError.response }
            guard KeychainService.delete(account: tokenAccount) else { throw WHOOPError.storage }
            message = "Disconnected. Imported history is still saved on this device."
        } catch { message = "Disconnect failed: \(error.localizedDescription)" }
    }
}

enum WHOOPError: LocalizedError {
    case broker, authorization, storage, response, rateLimit, http(Int)
    var errorDescription: String? {
        switch self {
        case .broker: return "Enter the HTTPS URL of your WHOOP connector server."
        case .authorization: return "WHOOP authorization failed. Reconnect your account."
        case .storage: return "Could not save WHOOP credentials to Keychain."
        case .response: return "WHOOP returned an incomplete response. Your saved history was retained."
        case .rateLimit: return "WHOOP rate limit reached. Try syncing later."
        case .http(let code): return "WHOOP request failed (HTTP \(code))."
        }
    }
}
