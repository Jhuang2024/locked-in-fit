import Foundation

/// Shared low-level POST + response-unwrapping for BazaarLink's chat completions API.
/// Used by every BazaarLink-backed AI service (meal analysis, health scan, ...).
enum BazaarLinkClient {
    static let endpoint = URL(string: "https://bazaarlink.ai/api/v1/chat/completions")!

    static func send(body: [String: Any], apiKey: String) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // No HTTP-Referer/X-Title here: those were OpenRouter-specific
        // app-attribution headers from before the BazaarLink migration;
        // BazaarLink's OpenAI-compatible API just takes the Bearer key.
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
            throw FoodAIError.invalidResponse("HTTP \(http.statusCode). \(snippet)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw FoodAIError.invalidResponse("Missing choices/message/content in response.")
        }
        return content
    }
}
