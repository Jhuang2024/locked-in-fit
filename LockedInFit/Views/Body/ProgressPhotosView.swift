import SwiftUI
import SwiftData
import PhotosUI
import UIKit

struct ProgressPhotosView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ProgressPhoto.date, order: .reverse) private var photos: [ProgressPhoto]
    @State private var showNew = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if photos.isEmpty {
                    EmptyStateView(systemImage: "photo.on.rectangle", title: "No progress photos yet",
                                   message: "Take front, side, and back photos every few weeks. The scale lies; photos don't.")
                }
                ForEach(photos) { photo in
                    ProgressPhotoCard(photo: photo)
                        .contextMenu {
                            Button(role: .destructive) {
                                ImageStore.delete(photo.frontPhotoPath)
                                ImageStore.delete(photo.sidePhotoPath)
                                ImageStore.delete(photo.backPhotoPath)
                                context.delete(photo)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Progress Photos")
        .toolbar {
            Button { showNew = true } label: { Image(systemName: "plus") }
        }
        .sheet(isPresented: $showNew) { NewProgressPhotoView() }
    }
}

struct NewProgressPhotoView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var date = Date()
    @State private var notes = ""
    @State private var front: UIImage?
    @State private var side: UIImage?
    @State private var back: UIImage?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }
                Section("Photos") {
                    PhotoSlotPicker(label: "Front", image: $front)
                    PhotoSlotPicker(label: "Side", image: $side)
                    PhotoSlotPicker(label: "Back", image: $back)
                }
                Section("Notes") {
                    TextField("e.g. end of week 4", text: $notes, axis: .vertical)
                }
            }
            .navigationTitle("New Progress Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let photo = ProgressPhoto(
                            date: date,
                            frontPhotoPath: front.flatMap { ImageStore.save($0, prefix: "front") },
                            sidePhotoPath: side.flatMap { ImageStore.save($0, prefix: "side") },
                            backPhotoPath: back.flatMap { ImageStore.save($0, prefix: "back") },
                            notes: notes)
                        context.insert(photo)
                        dismiss()
                    }
                    .disabled(front == nil && side == nil && back == nil && notes.isEmpty)
                }
            }
        }
    }
}

struct PhotoSlotPicker: View {
    let label: String
    @Binding var image: UIImage?
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button { showCamera = true } label: { Image(systemName: "camera") }
                    .buttonStyle(.bordered)
            }
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Image(systemName: "photo")
            }
            .buttonStyle(.bordered)
        }
        .onChange(of: pickerItem) {
            Task {
                if let data = try? await pickerItem?.loadTransferable(type: Data.self) {
                    image = UIImage(data: data)
                }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image = $0 }
                .ignoresSafeArea()
        }
    }
}
