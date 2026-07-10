import SwiftUI
import SwiftData

/// AI Analysis settings: mode, BazaarLink key (Keychain), model, test, clear.
struct AISettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var settingsList: [UserSettings]

    @State private var apiKeyInput = ""
    @State private var testResult: String?
    @State private var testing = false
    @State private var keyStored = KeychainService.bazaarLinkAPIKey != nil

    private var settings: UserSettings? { settingsList.first }

    var body: some View {
        Form {
            Section {
                SecureField("sk-bl-…", text: $apiKeyInput)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                HStack {
                    Image(systemName: keyStored ? "checkmark.seal.fill" : "xmark.seal")
                        .foregroundStyle(keyStored ? .green : .secondary)
                    Text(keyStored ? "Key saved in Keychain" : "No key saved")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Save API Key") {
                    let trimmed = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty, trimmed != "ENTER_BAZAARLINK_API_KEY_HERE" else { return }
                    KeychainService.save(trimmed, account: KeychainService.bazaarLinkKeyAccount)
                    settings?.hasStoredAPIKey = true
                    apiKeyInput = ""
                    keyStored = true
                    testResult = nil
                }
                .disabled(apiKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Clear API Key", role: .destructive) {
                    KeychainService.delete(account: KeychainService.bazaarLinkKeyAccount)
                    settings?.hasStoredAPIKey = false
                    keyStored = false
                    testResult = "Key removed. AI analysis is unavailable until a key is saved."
                }
                .disabled(!keyStored)
            } header: {
                Text("BazaarLink API Key")
            } footer: {
                Text("Paste your BazaarLink key (starts with sk-bl-) once; it's stored in the iOS Keychain, never in the database or UserDefaults. Every AI feature (meal photos, descriptions, product scans, workout calories, appearance analysis) uses this key directly — there is no offline mock mode. Get a key at bazaarlink.ai.")
            }

            Section {
                if let settings {
                    @Bindable var settings = settings
                    TextField(AIServiceFactory.defaultModelName, text: $settings.aiModelName)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            } header: {
                Text("Model")
            } footer: {
                Text("Empty uses the default auto:free, which routes every request to a free BazaarLink model — zero cost. If photo features (meal photos, scans, appearance) error because the free model can't read images, enter a vision-capable model ID here instead, e.g. gpt-4o-mini (plain names, not OpenRouter's provider/model form).")
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
                .disabled(testing || !keyStored)
                if let testResult {
                    Text(testResult)
                        .font(.caption)
                        .foregroundStyle(testResult.hasPrefix("Connected") ? .green : .secondary)
                }
            }
        }
        .navigationTitle("AI Analysis")
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDoneToolbar()
        .onAppear { PerfLog.event("nav.aiSettings.appear") }
    }

    private func testConnection() async {
        testing = true
        defer { testing = false }
        let service = BazaarLinkFoodAIService(modelName: AIServiceFactory.modelName(settings: settings))
        do {
            testResult = try await service.testConnection()
        } catch {
            testResult = "Failed: \(error.localizedDescription)"
        }
    }
}
