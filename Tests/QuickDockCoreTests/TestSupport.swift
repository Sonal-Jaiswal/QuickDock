import Foundation
@testable import QuickDockCore

/// A unique temporary directory that is removed when the value is deinitialized.
final class TemporaryDirectory {
    let url: URL

    init() {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuickDockTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    @discardableResult
    func makeFile(_ name: String, contents: String = "hello") throws -> URL {
        let fileURL = url.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: fileURL)
        return fileURL
    }

    @discardableResult
    func makeFolder(_ name: String) throws -> URL {
        let folderURL = url.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        return folderURL
    }

    /// A minimal application bundle with an Info.plist.
    @discardableResult
    func makeApp(_ name: String, bundleID: String) throws -> URL {
        let appURL = url.appendingPathComponent("\(name).app", isDirectory: true)
        let contents = appURL.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": bundleID, "CFBundleName": name, "CFBundlePackageType": "APPL",
                                    "CFBundleExecutable": name]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        return appURL
    }
}

struct FakeApplications: ApplicationLocating {
    var installed: [String: URL] = [:]
    func applicationURL(forBundleIdentifier bundleIdentifier: String) -> URL? { installed[bundleIdentifier] }
}

struct FakeFileSystem: FileSystemQuerying {
    var existing: Set<String> = []
    var readable: Set<String> = []
    func fileExists(atPath path: String) -> Bool { existing.contains(path) }
    func isReadableFile(atPath path: String) -> Bool { readable.contains(path) }
}

/// Bookmarks that encode the path, with configurable staleness/failure.
struct FakeBookmarks: BookmarkProviding {
    var staleFor: Set<String> = []
    var redirect: [String: String] = [:]
    var failing: Set<String> = []

    func makeBookmark(for url: URL) throws -> Data { Data(("bm:" + url.path).utf8) }

    func resolveBookmark(_ data: Data) throws -> ResolvedBookmark {
        let path = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "bm:", with: "")
        if failing.contains(path) { throw CocoaError(.fileNoSuchFile) }
        let resolvedPath = redirect[path] ?? path
        return ResolvedBookmark(url: URL(fileURLWithPath: resolvedPath), isStale: staleFor.contains(path) || redirect[path] != nil)
    }
}

extension LaunchItem {
    static func website(_ address: String, name: String? = nil) -> LaunchItem {
        try! ItemFactory().makeWebsite(address: address, name: name)
    }

    static func app(_ name: String, bundleID: String?, path: String? = nil) -> LaunchItem {
        LaunchItem(name: name, target: .application(AppReference(bundleIdentifier: bundleID,
                                                                 path: path ?? "/Applications/\(name).app")))
    }

    static func file(_ path: String, name: String? = nil) -> LaunchItem {
        LaunchItem(name: name ?? (path as NSString).lastPathComponent, target: .file(FileReference(path: path)))
    }

    static func folder(_ path: String, name: String? = nil) -> LaunchItem {
        LaunchItem(name: name ?? (path as NSString).lastPathComponent, target: .folder(FileReference(path: path)))
    }
}
