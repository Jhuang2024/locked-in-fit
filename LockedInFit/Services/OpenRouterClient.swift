import Foundation

/// Shared low-level POST + response-unwrapping for OpenRouter's chat completions API.
/// Used by every OpenRouter-backed AI service (meal analysis, health scan, ...).
enum OpenRouterClient {
    static let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

    static func send(body: [String: Any], apiKey: String) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://localhost/locked-in-fit", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("Locked In Fit", forHTTPHeaderField: "X-Title")
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
