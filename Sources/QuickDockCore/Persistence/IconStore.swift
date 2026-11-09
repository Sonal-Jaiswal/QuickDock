import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Stores custom item icons as small PNG files in `Application Support/QuickDock/Icons`.
public final class IconStore: @unchecked Sendable {
    public enum IconError: Error, LocalizedError {
        case unreadableImage
        case writeFailed

        public var errorDescription: String? {
            switch self {
            case .unreadableImage: return "That image couldn’t be read. Choose a PNG, JPEG, HEIC or ICNS file."
            case .writeFailed: return "The icon couldn’t be saved."
            }
        }
    }

    /// Icons are downscaled to this edge length (pixels), enough for Retina at the largest size.
    public static let maximumPixelSize = 256
    /// Upper bound for icon data accepted from imported configurations.
    public static let maximumImportedBytes = 1_000_000

    public let directory: URL
    private let fileManager: FileManager

    public init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
    }

    /// Only names QuickDock generates are accepted, which prevents path traversal
    /// through crafted configuration files.
    public static func isValidFileName(_ name: String) -> Bool {
        guard name.hasSuffix(".png") else { return false }
        return UUID(uuidString: String(name.dropLast(4))) != nil
    }

    public func url(for fileName: String) -> URL? {
        guard Self.isValidFileName(fileName) else { return nil }
        return directory.appendingPathComponent(fileName)
    }

    public func data(for fileName: String) -> Data? {
        url(for: fileName).flatMap { try? Data(contentsOf: $0) }
    }

    /// Downscales any image ImageIO can read to a PNG and stores it. Returns the new file name.
    public func importImage(at sourceURL: URL) throws -> String {
        guard let data = try? Data(contentsOf: sourceURL) else { throw IconError.unreadableImage }
        return try storeImageData(data)
    }

    /// Validates, downscales and stores image data. Returns the new file name.
    public func storeImageData(_ data: Data) throws -> String {
        guard let png = Self.normalizedPNG(from: data) else { throw IconError.unreadableImage }
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let name = UUID().uuidString + ".png"
            try png.write(to: directory.appendingPathComponent(name), options: [.atomic])
            return name
        } catch {
            throw IconError.writeFailed
        }
    }

    public func delete(_ fileName: String) {
        guard let url = url(for: fileName) else { return }
        try? fileManager.removeItem(at: url)
    }

    /// Deletes icon files no item references any more.
    public func removeUnused(keeping referenced: Set<String>) {
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else { return }
        for name in names where Self.isValidFileName(name) && !referenced.contains(name) {
            try? fileManager.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    public func deleteAll() {
        try? fileManager.removeItem(at: directory)
    }

    /// Decodes `data` as an image and re-encodes it as a PNG no larger than `maximumPixelSize`.
    /// Re-encoding also strips any metadata from user-supplied images.
    public static func normalizedPNG(from data: Data) -> Data? {
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
