import Foundation
import UIKit

/// Saves meal/progress photos to Documents/Photos and loads them by relative path.
enum ImageStore {
    private static var directory: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Returns the relative path to store on the model.
    static func save(_ image: UIImage, prefix: String) -> String? {
        guard let data = image.resized(maxDimension: 1600).jpegData(compressionQuality: 0.8) else { return nil }
        let name = "\(prefix)-\(UUID().uuidString).jpg"
        do {
            try data.write(to: directory.appendingPathComponent(name))
            return name
        } catch {
            return nil
        }
    }

    static func load(_ relativePath: String?) -> UIImage? {
        guard let relativePath, !relativePath.isEmpty else { return nil }
        return UIImage(contentsOfFile: directory.appendingPathComponent(relativePath).path)
    }

    static func delete(_ relativePath: String?) {
        guard let relativePath, !relativePath.isEmpty else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(relativePath))
    }
}
