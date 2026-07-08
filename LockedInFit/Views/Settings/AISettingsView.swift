import SwiftUI
import SwiftData

/// AI Analysis settings: mode, OpenRouter key (Keychain), model, test, clear.
struct AISettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var settingsList: [UserSettings]

    @State private var apiKeyInput = ""
    @State private var testResult: String?
    @State private var testing = false
    @State private var keyStored = KeychainService.openRouterAPIKey != nil

    private var settings: UserSettings? { settingsList.first }

    var body: some View {
        Form {
            Section {
                SecureField("ENTER_OPENROUTER_API_KEY_HERE", text: $apiKeyInput)
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
                    guard !trimmed.isEmpty, trimmed != "ENTER_OPENROUTER_API_KEY_HERE" else { return }
                    KeychainService.save(trimmed, account: KeychainService.openRouterKeyAccount)
                    settings?.hasStoredAPIKey = true
                    apiKeyInput = ""
                    keyStored = true
                    testResult = nil
                }
                .disabled(apiKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Clear API Key", role: .destructive) {
                    KeychainService.delete(account: KeychainService.openRouterKeyAccount)
                    settings?.hasStoredAPIKey = false
                    keyStored = false
                    testResult = "Key removed. AI analysis is unavailable until a key is saved."
                }
                .disabled(!keyStored)
            } header: {
                Text("OpenRouter API Key")
            } footer: {
                Text("Paste your OpenRouter key once; it's stored in the iOS Keychain, never in the database or UserDefaults. Every AI feature (meal photos, descriptions, product scans, workout calories, appearance analysis) uses this key directly — there is no offline mock mode. Get a key at openrouter.ai.")
            }

            Section {
                if let settings {
                    @Bindable var settings = settings
                    TextField("openai/gpt-4o-mini", text: $settings.aiModelName)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            } header: {
                Text("Model")
            } footer: {
                Text("Any OpenRouter vision-capable model ID, e.g. openai/gpt-4o-mini, anthropic/claude-sonnet-4.5, google/gemini-2.5-flash.")
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
        .onAppear { PerfLog.event("nav.aiSettings.appear") }
    }

    private func testConnection() async {
        testing = true
        defer { testing = false }
        let model = settings?.aiModelName ?? "openai/gpt-4o-mini"
        let service = OpenRouterFoodAIService(modelName: model.isEmpty ? "openai/gpt-4o-mini" : model)
        do {
            testResult = try await service.testConnection()
        } catch {
            testResult = "Failed: \(error.localizedDescription)"
        }
    }
}
