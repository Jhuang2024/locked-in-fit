import Foundation

/// Which AI gateway served a request. OpenRouter is tried first (the app's
/// default provider); BazaarLink is the fallback, tried only if OpenRouter
/// has no key saved or its request fails.
enum AIGatewayProvider: CaseIterable {
    case openRouter
    case bazaarLink

    var displayName: String {
        switch self {
        case .openRouter: return "OpenRouter"
        case .bazaarLink: return "BazaarLink"
        }
    }

    var endpoint: URL {
        switch self {
        case .openRouter: return URL(string: "https://openrouter.ai/api/v1/chat/completions")!
        case .bazaarLink: return URL(string: "https://bazaarlink.ai/api/v1/chat/completions")!
        }
    }

    /// Model ID used when Settings has no explicit override: each gateway's
    /// own "route to an available free model automatically" ID, so ordinary
    /// AI analysis costs nothing by default no matter which provider ends
    /// up serving the request.
    var defaultFreeModel: String {
        switch self {
        case .openRouter: return "openrouter/free"
        case .bazaarLink: return "auto:free"
        }
    }

    var apiKey: String? {
        switch self {
        case .openRouter: return KeychainService.openRouterAPIKey
        case .bazaarLink: return KeychainService.bazaarLinkAPIKey
        }
    }

    /// Optional app-attribution headers OpenRouter's dashboard/rankings use;
    /// harmless to send, meaningless to BazaarLink.
    var extraHeaders: [String: String] {
        switch self {
        case .openRouter: return ["HTTP-Referer": "https://localhost/locked-in-fit", "X-Title": "Locked In Fit"]
        case .bazaarLink: return [:]
        }
    }

    func resolvedModel(override: String?) -> String {
        let trimmed = override?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? defaultFreeModel : trimmed
    }
}

/// Shared low-level POST + response-unwrapping for every AI-backed feature
/// in the app (meal analysis, health scans, appearance, workouts,
/// exercises). Tries each configured provider in `AIGatewayProvider`'s
/// order — OpenRouter, then BazaarLink — so a single provider having a bad
/// day, a revoked key, or a temporarily-unavailable model doesn't take
/// every AI feature down with it. A provider with no key saved is skipped
/// silently (not treated as a failure); the error surfaced to the caller is
/// whichever provider was actually tried last, or "no key saved at all" if
/// neither was configured.
enum AIGatewayClient {
    static func send(body: [String: Any], modelOverride: String?) async throws -> (content: String, provider: AIGatewayProvider, model: String) {
        var lastError: Error?
        var attemptedAny = false
        for provider in AIGatewayProvider.allCases {
            guard let apiKey = provider.apiKey else { continue }
            attemptedAny = true
            let model = provider.resolvedModel(override: modelOverride)
            var attemptBody = body
            attemptBody["model"] = model
            do {
                let content = try await sendOnce(body: attemptBody, apiKey: apiKey, provider: provider)
                return (content, provider, model)
            } catch {
                lastError = error
            }
        }
        guard attemptedAny else { throw FoodAIError.noAPIKey }
        throw lastError ?? FoodAIError.noAPIKey
    }

    private static func sendOnce(body: [String: Any], apiKey: String, provider: AIGatewayProvider) async throws -> String {
        var request = URLRequest(url: provider.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (field, value) in provider.extraHeaders {
            request.setValue(value, forHTTPHeaderField: field)
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw FoodAIError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw FoodAIError.network("No HTTP response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let snippet = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
            throw FoodAIError.invalidResponse("\(provider.displayName) HTTP \(http.statusCode). \(snippet)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw FoodAIError.invalidResponse("Missing choices/message/content in \(provider.displayName)'s response.")
        }
        return content
    }
}
