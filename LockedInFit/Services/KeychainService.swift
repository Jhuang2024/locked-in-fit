import Foundation
import Security

/// Thin Keychain wrapper. Stores AI gateway API keys outside SwiftData/UserDefaults.
/// Both OpenRouter and BazaarLink keys can be saved at once — see
/// AIGatewayClient, which tries OpenRouter first and falls back to
/// BazaarLink, so either key alone (or both) keeps AI features working.
enum KeychainService {
    static let openRouterKeyAccount = "openrouter_api_key"
    static let bazaarLinkKeyAccount = "bazaarlink_api_key"
    // Nutritionix uses two credentials (App ID + App Key), sent as
    // x-app-id / x-app-key headers. Menu Checker uses them for official
    // restaurant/branded nutrition, falling back to the AI gateway estimate.
    static let nutritionixAppIDAccount = "nutritionix_app_id"
    static let nutritionixAppKeyAccount = "nutritionix_app_key"
    private static let service = "com.jerryhuang.LockedInFit"

    @discardableResult
    static func save(_ value: String, account: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func delete(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    static var openRouterAPIKey: String? {
        guard let key = read(account: openRouterKeyAccount),
              !key.isEmpty,
              key != "ENTER_OPENROUTER_API_KEY_HERE" else { return nil }
        return key
    }

    static var bazaarLinkAPIKey: String? {
        guard let key = read(account: bazaarLinkKeyAccount),
              !key.isEmpty,
              key != "ENTER_BAZAARLINK_API_KEY_HERE" else { return nil }
        return key
    }

    /// Whether AI features have anything to work with at all — either key
    /// alone is enough (see AIGatewayClient). Views use this instead of
    /// checking bazaarLinkAPIKey alone to gate AI-dependent UI.
    static var hasAnyAIKey: Bool {
        openRouterAPIKey != nil || bazaarLinkAPIKey != nil
    }

    static var nutritionixAppID: String? {
        guard let id = read(account: nutritionixAppIDAccount), !id.isEmpty,
              id != "ENTER_NUTRITIONIX_APP_ID_HERE" else { return nil }
        return id
    }

    static var nutritionixAppKey: String? {
        guard let key = read(account: nutritionixAppKeyAccount), !key.isEmpty,
              key != "ENTER_NUTRITIONIX_APP_KEY_HERE" else { return nil }
        return key
    }

    /// Both Nutritionix credentials must be present for its endpoints to work.
    static var hasNutritionixCredentials: Bool {
        nutritionixAppID != nil && nutritionixAppKey != nil
    }
}
