import SwiftUI
import SwiftData
import PhotosUI
import UIKit

/// Photo → AI product analysis → editable review → save.
/// A scan is a lookup, not a meal log; saving one never touches daily calorie totals.
struct HealthScanCaptureView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var settingsList: [UserSettings]

    @State private var model = HealthScanAnalysisViewModel()
    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var draft: HealthScan?

    private var settings: UserSettings? { settingsList.first }

    var body: some View {
        NavigationStack {
            Group {
                if let draft {
                    HealthScanDraftEditor(scan: draft, providerUsed: model.providerUsed) {
                        context.insert(draft)
                        dismiss()
                    }
                } else {
                    setupAndAnalyze
                }
            }
            .navigationTitle("Health Scan")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDoneToolbar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private var setupAndAnalyze: some View {
        Form {
            Section {
                if let image = model.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }
                HStack {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button {
                            showCamera = true
                        } label: {
                            Label("Camera", systemImage: "camera")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("Library", systemImage: "photo")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .listRowBackground(Color.clear)
            } header: {
                Text("Product or Food")
            } footer: {
                Text("Photograph the packaging, ingredients list, or nutrition facts panel. This doesn't log anything you've eaten. It's just a lookup.")
            }

            Section {
                TextField("What's the product? e.g. \"Quaker chewy chocolate chip granola bar\"",
                          text: $model.productDescription, axis: .vertical)
                    .lineLimit(2...4)
                    .onChange(of: model.productDescription) {
                        if !model.productDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            model.phase = .ready
                        }
                    }
            } header: {
                Text("Or Describe It")
            } footer: {
                Text("No photo on hand? Type the product name and get the same health score, satiety score, and ingredient breakdown.")
            }

            Section {
                switch model.phase {
                case .analyzing:
                    HStack {
                        ProgressView()
                        Text("Scanning with \(model.providerUsed)…")
                            .foregroundStyle(.secondary)
                    }
                case .failed(let message):
                    VStack(alignment: .leading, spacing: 10) {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .foregroundStyle(.red)
                        Button("Retry") {
                            Task { await runAnalysis() }
                        }
                        .buttonStyle(.bordered)
                    }
                default:
                    Button {
                        Task { await runAnalysis() }
                    } label: {
                        Label("Scan Product", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.image == nil && model.productDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } footer: {
                if KeychainService.openRouterAPIKey != nil {
                    Text("Using OpenRouter (\(AIServiceFactory.modelName(settings: settings))). Nothing is saved until you review the result.")
                } else {
                    Text("No OpenRouter API key saved. Add one in Settings → AI Analysis to scan products.")
                }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in
                model.image = image
                model.phase = .ready
            }
            .ignoresSafeArea()
        }
        .onChange(of: photoItem) {
            Task {
                if let data = try? await photoItem?.loadTransferable(type: Data.self),
                   let image = UIImage.downsampled(from: data, maxDimension: 1600) {
                    model.image = image
                    model.phase = .ready
                }
            }
        }
    }

    private func runAnalysis() async {
        await model.analyze(settings: settings)
        if case .reviewing = model.phase {
            draft = model.makeDraft()
        }
    }
}
