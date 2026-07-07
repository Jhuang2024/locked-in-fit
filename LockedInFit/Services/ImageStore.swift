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

    /// Delete a batch of photos (nil/empty entries are skipped).
    static func deleteAll(_ relativePaths: [String?]) {
        for path in relativePaths { delete(path) }
    }

    /// Delete every stored photo whose filename starts with one of the given
    /// prefixes (e.g. "face", "body-front"). Belt-and-braces cleanup for
    /// "Delete All Looks Data" so no orphaned files survive.
    static func deleteAll(withPrefixes prefixes: [String]) {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for file in files where prefixes.contains(where: { file.lastPathComponent.hasPrefix($0 + "-") }) {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
