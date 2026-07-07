import Foundation
import AuthenticationServices
import CryptoKit
import UIKit

enum GoogleCalendarError: LocalizedError {
    case notConfigured
    case notConnected
    case cancelled
    case network(String)
    case api(String)
    case tokenRefreshFailed

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Google Calendar isn't configured. Add your Google OAuth Client ID in Settings → Looks & Calendar."
        case .notConnected:
            return "Google Calendar isn't connected. Connect it in Settings → Looks & Calendar."
        case .cancelled:
            return "Sign-in was cancelled."
        case .network(let detail):
            return "Network request failed. \(detail)"
        case .api(let detail):
            return "Google Calendar error: \(detail)"
        case .tokenRefreshFailed:
            return "Google session expired. Reconnect Google Calendar in Settings."
        }
    }
}

/// Event payload for both appearance goals and workout sessions.
struct CalendarEventPayload {
    var title: String
    var description: String
    var start: Date
    var end: Date
    /// iCalendar RRULE (without the "RRULE:" prefix), e.g. "FREQ=WEEKLY;BYDAY=MO".
    var recurrenceRule: String?
    /// Popup reminder minutes before start; nil = calendar default.
    var reminderMinutes: Int?
}

/// Google Calendar integration, entirely optional and off by default.
///
/// Auth: OAuth 2.0 with PKCE through ASWebAuthenticationSession (the
/// system-browser flow Google requires for native apps). No client secret is
/// used or stored — iOS OAuth clients don't have one. Tokens live only in the
/// Keychain; SwiftData stores connection metadata (CalendarConnectionState).
/// Scope is the narrowest useful one: calendar.events (+ email for display).
@Observable
final class GoogleCalendarService: NSObject {
    static let shared = GoogleCalendarService()

    static let eventsScope = "https://www.googleapis.com/auth/calendar.events"
    private static let scopes = "openid email " + eventsScope

    // Keychain accounts (KeychainService applies its own service namespace).
    private static let clientIDAccount = "google_oauth_client_id"
    private static let accessTokenAccount = "google_access_token"
    private static let refreshTokenAccount = "google_refresh_token"
    private static let expiryAccount = "google_token_expiry"
    private static let emailAccount = "google_account_email"

    private(set) var isAuthenticating = false
    /// Strong reference for the duration of the browser flow — the session is
    /// dismissed immediately if it deallocates while presented.
    @ObservationIgnored private var activeAuthSession: ASWebAuthenticationSession?

    // MARK: - Configuration

    var clientID: String? {
        KeychainService.read(account: Self.clientIDAccount).flatMap { $0.isEmpty ? nil : $0 }
    }

    func saveClientID(_ id: String) {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        KeychainService.save(trimmed, account: Self.clientIDAccount)
    }

    var isConnected: Bool {
        KeychainService.read(account: Self.refreshTokenAccount)?.isEmpty == false
    }

    var connectedEmail: String? {
        KeychainService.read(account: Self.emailAccount).flatMap { $0.isEmpty ? nil : $0 }
    }

    // MARK: - Connect / disconnect

    /// Runs the full browser sign-in + consent flow. Returns the account email.
    @MainActor
    func connect() async throws -> String {
        guard let clientID else { throw GoogleCalendarError.notConfigured }
        isAuthenticating = true
        defer { isAuthenticating = false }

        let verifier = Self.randomURLSafeString(length: 64)
        let challenge = Self.codeChallenge(for: verifier)
        let scheme = Self.reversedClientScheme(clientID: clientID)
        let redirectURI = "\(scheme):/oauth2redirect"

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: Self.scopes),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        guard let authURL = components.url else { throw GoogleCalendarError.notConfigured }

        defer { activeAuthSession = nil }
        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: scheme) { url, error in
                if let url {
                    continuation.resume(returning: url)
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: GoogleCalendarError.cancelled)
                } else {
                    continuation.resume(throwing: GoogleCalendarError.network(error?.localizedDescription ?? "Unknown sign-in error."))
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            activeAuthSession = session
            if !session.start() {
                continuation.resume(throwing: GoogleCalendarError.network("Couldn't start the sign-in session."))
            }
        }

        guard let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value else {
            throw GoogleCalendarError.api("Google didn't return an authorization code.")
        }

        let email = try await exchangeCode(code, clientID: clientID, verifier: verifier, redirectURI: redirectURI)
        return email
    }

    /// Best-effort token revocation, then clears everything from the Keychain.
    func disconnect() async {
        if let token = KeychainService.read(account: Self.refreshTokenAccount), !token.isEmpty {
            var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/revoke")!)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = "token=\(token)".data(using: .utf8)
            _ = try? await URLSession.shared.data(for: request)
        }
        KeychainService.delete(account: Self.accessTokenAccount)
        KeychainService.delete(account: Self.refreshTokenAccount)
        KeychainService.delete(account: Self.expiryAccount)
        KeychainService.delete(account: Self.emailAccount)
    }

    // MARK: - Events API

    /// Creates an event on the primary calendar and returns its event ID.
    func createEvent(_ payload: CalendarEventPayload) async throws -> String {
        let token = try await validAccessToken()
        let url = URL(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events")!
        let json = try await sendJSON(eventBody(payload), to: url, method: "POST", token: token)
        guard let id = json["id"] as? String else {
            throw GoogleCalendarError.api("Event created but no ID returned.")
        }
        return id
    }

    func updateEvent(id: String, payload: CalendarEventPayload) async throws {
        let token = try await validAccessToken()
        guard let url = URL(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events/\(id)") else {
            throw GoogleCalendarError.api("Invalid event ID.")
        }
        _ = try await sendJSON(eventBody(payload), to: url, method: "PATCH", token: token)
    }

    /// Deletes an app-created event. 404/410 (already gone) is treated as success.
    func deleteEvent(id: String) async throws {
        let token = try await validAccessToken()
        guard let url = URL(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events/\(id)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await dataOrNetworkError(for: request)
        if let http = response as? HTTPURLResponse,
           !(200..<300).contains(http.statusCode), http.statusCode != 404, http.statusCode != 410 {
            throw GoogleCalendarError.api("HTTP \(http.statusCode). \(String(data: data, encoding: .utf8)?.prefix(160) ?? "")")
        }
    }

    private func eventBody(_ payload: CalendarEventPayload) -> [String: Any] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let timeZone = TimeZone.current.identifier
        var body: [String: Any] = [
            "summary": payload.title,
            "description": payload.description,
            "start": ["dateTime": formatter.string(from: payload.start), "timeZone": timeZone],
            "end": ["dateTime": formatter.string(from: payload.end), "timeZone": timeZone]
        ]
        if let rule = payload.recurrenceRule, !rule.isEmpty {
            body["recurrence"] = ["RRULE:\(rule)"]
        }
        if let minutes = payload.reminderMinutes {
            body["reminders"] = ["useDefault": false,
                                 "overrides": [["method": "popup", "minutes": minutes]]]
        }
        return body
    }

    private func sendJSON(_ body: [String: Any], to url: URL, method: String, token: String) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await dataOrNetworkError(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GoogleCalendarError.network("No HTTP response.")
        }
        if http.statusCode == 401 { throw GoogleCalendarError.tokenRefreshFailed }
        guard (200..<300).contains(http.statusCode) else {
            throw GoogleCalendarError.api("HTTP \(http.statusCode). \(String(data: data, encoding: .utf8)?.prefix(160) ?? "")")
        }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    // MARK: - Tokens

    /// Returns a fresh access token, refreshing if within a minute of expiry.
    func validAccessToken() async throws -> String {
        guard let refreshToken = KeychainService.read(account: Self.refreshTokenAccount),
              !refreshToken.isEmpty else { throw GoogleCalendarError.notConnected }
        if let token = KeychainService.read(account: Self.accessTokenAccount), !token.isEmpty,
           let expiryString = KeychainService.read(account: Self.expiryAccount),
           let expiry = Double(expiryString),
           Date(timeIntervalSince1970: expiry) > Date().addingTimeInterval(60) {
            return token
        }
        guard let clientID else { throw GoogleCalendarError.notConfigured }
        let response = try await tokenRequest(parameters: [
            "client_id": clientID,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ])
        guard let accessToken = response["access_token"] as? String else {
            throw GoogleCalendarError.tokenRefreshFailed
        }
        storeTokens(accessToken: accessToken,
                    refreshToken: nil,
                    expiresIn: response["expires_in"] as? Double ?? 3500)
        return accessToken
    }

    private func exchangeCode(_ code: String, clientID: String, verifier: String, redirectURI: String) async throws -> String {
        let response = try await tokenRequest(parameters: [
            "client_id": clientID,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI
        ])
        guard let accessToken = response["access_token"] as? String,
              let refreshToken = response["refresh_token"] as? String else {
            throw GoogleCalendarError.api("Google didn't return tokens. Make sure the client ID is an iOS OAuth client.")
        }
        storeTokens(accessToken: accessToken,
                    refreshToken: refreshToken,
                    expiresIn: response["expires_in"] as? Double ?? 3500)
        let email = Self.email(fromIDToken: response["id_token"] as? String) ?? "Google account"
        KeychainService.save(email, account: Self.emailAccount)
        return email
    }

    private func tokenRequest(parameters: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = parameters
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        let (data, response) = try await dataOrNetworkError(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let snippet = String(data: data, encoding: .utf8)?.prefix(160) ?? ""
            throw GoogleCalendarError.api("Token request failed. \(snippet)")
        }
        return json
    }

    private func storeTokens(accessToken: String, refreshToken: String?, expiresIn: Double) {
        KeychainService.save(accessToken, account: Self.accessTokenAccount)
        if let refreshToken {
            KeychainService.save(refreshToken, account: Self.refreshTokenAccount)
        }
        let expiry = Date().addingTimeInterval(expiresIn).timeIntervalSince1970
        KeychainService.save(String(expiry), account: Self.expiryAccount)
    }

    private func dataOrNetworkError(for request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await URLSession.shared.data(for: request)
        } catch {
            throw GoogleCalendarError.network(error.localizedDescription)
        }
    }

    // MARK: - Small helpers

    /// "123-abc.apps.googleusercontent.com" → "com.googleusercontent.apps.123-abc".
    static func reversedClientScheme(clientID: String) -> String {
        let suffix = ".apps.googleusercontent.com"
        let base = clientID.hasSuffix(suffix) ? String(clientID.dropLast(suffix.count)) : clientID
        return "com.googleusercontent.apps.\(base)"
    }

    private static func randomURLSafeString(length: Int) -> String {
        let charset = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
        return String((0..<length).map { _ in charset.randomElement()! })
    }

    private static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func email(fromIDToken idToken: String?) -> String? {
        guard let idToken else { return nil }
        let segments = idToken.split(separator: ".")
        guard segments.count >= 2 else { return nil }
        var payload = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["email"] as? String
    }
}

extension GoogleCalendarService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
        return window ?? ASPresentationAnchor()
    }
}

// MARK: - Event payload builders

extension CalendarEventPayload {
    /// Payload for an approved long-term appearance suggestion.
    static func forSuggestion(_ suggestion: AppearanceSuggestion,
                              start: Date,
                              durationMinutes: Int = 30,
                              recurrenceRule: String?,
                              reminderMinutes: Int?) -> CalendarEventPayload {
        let source = suggestion.sourceKindRaw.capitalized
        let description = """
        Source: \(source) suggestion
        \(suggestion.explanation)

        Expected impact: \(suggestion.expectedImpact)

        Created by LockedInFit
        """
        return CalendarEventPayload(
            title: "LockedInFit: \(suggestion.title)",
            description: description,
            start: start,
            end: start.addingTimeInterval(Double(durationMinutes) * 60),
            recurrenceRule: recurrenceRule,
            reminderMinutes: reminderMinutes)
    }

    /// Weekly recurring payload for a workout schedule session.
    static func forSession(_ session: WorkoutScheduleSession,
                           schedule: WorkoutSchedule,
                           reminderMinutes: Int) -> CalendarEventPayload? {
        guard let start = session.date else { return nil }
        let exercises = session.plannedExercises
            .map { "• \($0.name): \($0.summary)" }
            .joined(separator: "\n")
        let description = """
        \(schedule.title)
        \(exercises)

        \(schedule.progressionNote)

        Created by LockedInFit
        """
        var rule = "FREQ=WEEKLY;BYDAY=\(Weekday.rruleCode(session.weekday))"
        if let endDate = schedule.endDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            rule += ";UNTIL=\(formatter.string(from: endDate))"
        }
        return CalendarEventPayload(
            title: "LockedInFit Workout: \(session.title)",
            description: description,
            start: start,
            end: start.addingTimeInterval(Double(session.estimatedDurationMinutes) * 60),
            recurrenceRule: rule,
            reminderMinutes: reminderMinutes)
    }
}
