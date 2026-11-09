import Foundation
import Testing
@testable import QuickDockCore

@Suite("Item resolver")
struct ItemResolverTests {
    @Test("Apps resolve by path, then bundle ID, else not installed")
    func applications() {
        let movedURL = URL(fileURLWithPath: "/Applications/Utilities/Tool.app")
        let resolver = ItemResolver(fileSystem: FakeFileSystem(existing: ["/Applications/Safari.app"]),
                                    applications: FakeApplications(installed: ["com.x.tool": movedURL]),
                                    bookmarks: FakeBookmarks())

        let safari = resolver.resolve(LaunchItem.app("Safari", bundleID: "com.apple.Safari").target)
        #expect(safari.availability == .available)
        #expect(safari.updatedTarget == nil)

        let moved = resolver.resolve(LaunchItem.app("Tool", bundleID: "com.x.tool").target)
        #expect(moved.availability == .available)
        #expect(moved.url == movedURL)
        guard case .application(let updated)? = moved.updatedTarget else { Issue.record("expected update"); return }
        #expect(updated.path == movedURL.path)

        let gone = resolver.resolve(LaunchItem.app("Gone", bundleID: "com.x.gone").target)
        #expect(gone.availability == .applicationNotInstalled)
    }

    @Test("Moved files are followed through their bookmark and the path is updated")
    func movedFile() {
        let resolver = ItemResolver(fileSystem: FakeFileSystem(existing: ["/new/place.txt"]),
                                    applications: FakeApplications(),
                                    bookmarks: FakeBookmarks(redirect: ["/old/place.txt": "/new/place.txt"]))
        let target = ItemTarget.file(FileReference(path: "/old/place.txt", bookmark: Data("bm:/old/place.txt".utf8)))
        let resolution = resolver.resolve(target)
        #expect(resolution.availability == .available)
        #expect(resolution.url?.path == "/new/place.txt")
        guard case .file(let ref)? = resolution.updatedTarget else { Issue.record("expected update"); return }
        #expect(ref.path == "/new/place.txt")
        #expect(ref.bookmark == Data("bm:/new/place.txt".utf8)) // stale bookmark recreated
    }

    @Test("Deleted files are reported missing")
    func deletedFile() {
        let resolver = ItemResolver(fileSystem: FakeFileSystem(), applications: FakeApplications(),
                                    bookmarks: FakeBookmarks(failing: ["/gone.txt"]))
        let target = ItemTarget.file(FileReference(path: "/gone.txt", bookmark: Data("bm:/gone.txt".utf8)))
        #expect(resolver.resolve(target).availability == .missing)
    }

    @Test("Bookmark resolving to a deleted location is missing")
    func bookmarkToDeleted() {
        let resolver = ItemResolver(fileSystem: FakeFileSystem(), applications: FakeApplications(), bookmarks: FakeBookmarks())
        let target = ItemTarget.folder(FileReference(path: "/f", bookmark: Data("bm:/f".utf8)))
        #expect(resolver.resolve(target).availability == .missing)
    }

    @Test("Broken bookmark but readable path recovers and refreshes the bookmark")
    func brokenBookmarkReadablePath() {
        let resolver = ItemResolver(fileSystem: FakeFileSystem(existing: ["/a.txt"], readable: ["/a.txt"]),
                                    applications: FakeApplications(), bookmarks: FakeBookmarks(failing: ["/a.txt"]))
        let target = ItemTarget.file(FileReference(path: "/a.txt", bookmark: Data("bm:/a.txt".utf8)))
        let resolution = resolver.resolve(target)
        #expect(resolution.availability == .available)
        #expect(resolution.updatedTarget != nil)
    }

    @Test("Exists but unreadable without a bookmark needs access")
    func needsAccess() {
        let resolver = ItemResolver(fileSystem: FakeFileSystem(existing: ["/secret"]),
                                    applications: FakeApplications(), bookmarks: FakeBookmarks())
        #expect(resolver.resolve(.file(FileReference(path: "/secret"))).availability == .needsAccess)
    }

    @Test("Websites are always available")
    func websites() {
        let resolver = ItemResolver(fileSystem: FakeFileSystem(), applications: FakeApplications(), bookmarks: FakeBookmarks())
        #expect(resolver.resolve(LaunchItem.website("a.com").target).availability == .available)
    }

    @Test("System actions resolve via bundle ID or fallback path")
    func actions() {
        let resolver = ItemResolver(fileSystem: FakeFileSystem(existing: ["/System/Applications/Mission Control.app"]),
                                    applications: FakeApplications(), bookmarks: FakeBookmarks())
        #expect(resolver.resolve(.action(ActionReference(kind: .missionControl))).availability == .available)
        #expect(resolver.resolve(.action(ActionReference(kind: .takeScreenshot))).availability == .applicationNotInstalled)
        #expect(resolver.resolve(.action(ActionReference(kind: .copySnippet, text: "x"))).availability == .available)
    }

    @Test("Real bookmarks survive a rename on disk")
    func realBookmarks() throws {
        let dir = TemporaryDirectory()
        let original = try dir.makeFile("Original.txt")
        let item = try ItemFactory().makeItem(for: original)
        let renamed = dir.url.appendingPathComponent("Renamed.txt")
        try FileManager.default.moveItem(at: original, to: renamed)

        let resolution = ItemResolver(applications: FakeApplications()).resolve(item.target)
        #expect(resolution.availability == .available)
        #expect(resolution.url?.resolvingSymlinksInPath().path == renamed.resolvingSymlinksInPath().path)

        try FileManager.default.removeItem(at: renamed)
        #expect(ItemResolver(applications: FakeApplications()).resolve(item.target).availability == .missing)
    }
}

@Suite("Item factory")
struct ItemFactoryTests {
    @Test("Classifies apps, files and folders")
    func classification() throws {
        let dir = TemporaryDirectory()
        let factory = ItemFactory()

        let app = try factory.makeItem(for: try dir.makeApp("Sample Tool", bundleID: "com.example.sample"))
        #expect(app.kind == .application)
        #expect(app.name == "Sample Tool")
        guard case .application(let ref) = app.target else { Issue.record("not an app"); return }
        #expect(ref.bundleIdentifier == "com.example.sample")

        let file = try factory.makeItem(for: try dir.makeFile("Notes.txt"))
        #expect(file.kind == .file)
        #expect(file.target.fileReference?.bookmark != nil)

        let folder = try factory.makeItem(for: try dir.makeFolder("Projects"))
        #expect(folder.kind == .folder)
        #expect(folder.name == "Projects")
    }

    @Test("Missing paths throw")
    func missing() {
        #expect(throws: ItemFactory.FactoryError.self) {
            try ItemFactory().makeItem(for: URL(fileURLWithPath: "/definitely/not/here.txt"))
        }
    }

    @Test("Website names default to the site name", arguments: [
        ("github.com", "Github"), ("https://www.apple.com/mac", "Apple"), ("bbc.co.uk", "Bbc"), ("localhost:3000", "localhost"),
    ])
    func websiteNames(address: String, expected: String) throws {
        #expect(try ItemFactory().makeWebsite(address: address).name == expected)
    }

    @Test("Custom website name is used and trimmed")
    func customName() throws {
        #expect(try ItemFactory().makeWebsite(address: "a.com", name: "  Docs ").name == "Docs")
    }

    @Test("Long names are clamped")
    func clamp() throws {
        let item = try ItemFactory().makeWebsite(address: "a.com", name: String(repeating: "n", count: 500))
        #expect(item.name.count == ItemFactory.maximumNameLength)
    }
}

@Suite("System app paths")
struct SystemAppPathTests {
    @Test("Cryptex-hosted apps are stored at their /Applications location")
    func cryptexPath() throws {
        let cryptex = URL(fileURLWithPath: "/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app")
        guard FileManager.default.fileExists(atPath: "/Applications/Safari.app") else { return }
        let item = try ItemFactory().makeItem(for: cryptex)
        guard case .application(let app) = item.target else { Issue.record("expected app, got \(item.kind)"); return }
        #expect(app.path == "/Applications/Safari.app")
        #expect(app.bundleIdentifier == "com.apple.Safari")
    }
}
