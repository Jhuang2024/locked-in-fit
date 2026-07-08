import Foundation

/// Atomic, versioned JSON read/write for the cross-app shared container.
/// Every operation is best-effort: a missing container, missing file, or
/// corrupt JSON all resolve to "no data" rather than an error callers have
/// to handle, since the whole integration is optional by design and must
/// never affect LockedInFit's own local storage.
enum SharedContextStore {
    private static let locator: SharedContainerLocating = AppGroupContainerLocator()

    private static let lockedInFitFilename = "lockedinfit_public_context_v1.json"
    private static let socialClimberFilename = "socialclimber_public_context_v1.json"

    @discardableResult
    static func writeLockedInFitContext(_ context: LockedInFitPublicContext) -> Bool {
        write(context, filename: lockedInFitFilename)
    }

    static func readSocialClimberContext() -> SocialClimberPublicContext? {
        read(SocialClimberPublicContext.self, filename: socialClimberFilename)
    }

    // MARK: - Generic helpers

    private static func write<T: Encodable>(_ value: T, filename: String) -> Bool {
        guard let containerURL = locator.containerURL else { return false }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value) else { return false }
        do {
            try FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true)
            // Write to a temp file first, then replace atomically so a reader
            // (Social Climber) never observes a partially-written file.
            let destination = containerURL.appendingPathComponent(filename)
            let temp = containerURL.appendingPathComponent(filename + ".tmp-\(UUID().uuidString)")
            try data.write(to: temp, options: .atomic)
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temp)
            return true
        } catch {
            return false
        }
    }

    private static func read<T: Decodable>(_ type: T.Type, filename: String) -> T? {
        guard let containerURL = locator.containerURL else { return nil }
        let url = containerURL.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(T.self, from: data)
    }
}
