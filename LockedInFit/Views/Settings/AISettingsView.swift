import SwiftUI
import SwiftData

/// AI Analysis settings: two gateway keys (Keychain), one shared model
/// override, test, clear. AIGatewayClient tries OpenRouter first, falling
/// back to BazaarLink, so either key alone (or both) keeps every AI
/// feature working — a provider having a bad day doesn't take AI analysis
/// down with it.
struct AISettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var settingsList: [UserSettings]

    @State private var openRouterKeyInput = ""
    @State private var openRouterKeyStored = KeychainService.openRouterAPIKey != nil
    @State private var bazaarLinkKeyInput = ""
    @State private var bazaarLinkKeyStored = KeychainService.bazaarLinkAPIKey != nil
    @State private var testResult: String?
    @State private var testing = false

    private var settings: UserSettings? { settingsList.first }
    private var anyKeyStored: Bool { openRouterKeyStored || bazaarLinkKeyStored }

    var body: some View {
        Form {
            Section {
                SecureField("sk-or-…", text: $openRouterKeyInput)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                HStack {
                    Image(systemName: openRouterKeyStored ? "checkmark.seal.fill" : "xmark.seal")
                        .foregroundStyle(openRouterKeyStored ? .green : .secondary)
                    Text(openRouterKeyStored ? "Key saved in Keychain" : "No key saved")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Save API Key") {
                    let trimmed = openRouterKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    KeychainService.save(trimmed, account: KeychainService.openRouterKeyAccount)
                    settings?.hasStoredAPIKey = true
                    openRouterKeyInput = ""
                    openRouterKeyStored = true
                    testResult = nil
                }
                .disabled(openRouterKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Clear API Key", role: .destructive) {
                    KeychainService.delete(account: KeychainService.openRouterKeyAccount)
                    settings?.hasStoredAPIKey = anyKeyStoredAfterClear
                    openRouterKeyStored = false
                    testResult = nil
                }
                .disabled(!openRouterKeyStored)
            } header: {
                Text("OpenRouter API Key — default")
            } footer: {
                Text("Tried first for every AI feature. Paste your OpenRouter key (starts with sk-or-) once; it's stored in the iOS Keychain, never in the database or UserDefaults. Get a key at openrouter.ai.")
            }

            Section {
                SecureField("sk-bl-…", text: $bazaarLinkKeyInput)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                HStack {
                    Image(systemName: bazaarLinkKeyStored ? "checkmark.seal.fill" : "xmark.seal")
                        .foregroundStyle(bazaarLinkKeyStored ? .green : .secondary)
                    Text(bazaarLinkKeyStored ? "Key saved in Keychain" : "No key saved")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Save API Key") {
                    let trimmed = bazaarLinkKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty, trimmed != "ENTER_BAZAARLINK_API_KEY_HERE" else { return }
                    KeychainService.save(trimmed, account: KeychainService.bazaarLinkKeyAccount)
                    settings?.hasStoredAPIKey = true
                    bazaarLinkKeyInput = ""
                    bazaarLinkKeyStored = true
                    testResult = nil
                }
                .disabled(bazaarLinkKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Clear API Key", role: .destructive) {
                    KeychainService.delete(account: KeychainService.bazaarLinkKeyAccount)
                    settings?.hasStoredAPIKey = anyKeyStoredAfterClear
                    bazaarLinkKeyStored = false
                    testResult = nil
                }
                .disabled(!bazaarLinkKeyStored)
            } header: {
                Text("BazaarLink API Key — fallback")
            } footer: {
                Text("Used only if OpenRouter has no key saved, or an OpenRouter request fails. Paste your BazaarLink key (starts with sk-bl-) once. Get a key at bazaarlink.ai. Every AI feature (meal photos, descriptions, product scans, workout calories, appearance analysis) uses whichever key actually works — there is no offline mock mode.")
            }

            Section {
                if let settings {
                    @Bindable var settings = settings
                    TextField("Leave blank for automatic free routing", text: $settings.aiModelName)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            } header: {
                Text("Model")
            } footer: {
                Text("Empty routes every request to a free model automatically — OpenRouter's openrouter/free or BazaarLink's auto:free, whichever provider ends up serving the request — zero cost. If photo features (meal photos, scans, appearance) error because the free model can't read images, enter a vision-capable model ID here instead, e.g. gpt-4o-mini. Note OpenRouter model IDs use a provider/model form (openai/gpt-4o-mini) while BazaarLink uses plain names (gpt-4o-mini); an override is tried as-is on whichever provider answers, so pick an ID that's valid on the provider you expect to use.")
            }

            Section {
                Button {
                    Task { await testConnection() }
                } label: {
                    if testing {
                        HStack { ProgressView(); Text("Testing…") }
                    } else {
                        Label("Test Connection", systemImage: "bolt.horizontal")
                    }
                }
                .disabled(testing || !anyKeyStored)
                if let testResult {
                    Text(testResult)
                        .font(.caption)
                        .foregroundStyle(testResult.hasPrefix("Connected") ? .green : .secondary)
                }
            } footer: {
                Text("Tries OpenRouter first, then BazaarLink, and reports which one actually answered.")
            }
        }
        .navigationTitle("AI Analysis")
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDoneToolbar()
        .onAppear { PerfLog.event("nav.aiSettings.appear") }
    }

    private var anyKeyStoredAfterClear: Bool {
        KeychainService.openRouterAPIKey != nil || KeychainService.bazaarLinkAPIKey != nil
    }

    private func testConnection() async {
        testing = true
        defer { testing = false }
        let service = BazaarLinkFoodAIService(modelOverride: AIServiceFactory.modelName(settings: settings))
        do {
            testResult = try await service.testConnection()
        } catch {
            testResult = "Failed: \(error.localizedDescription)"
        }
    }

}
