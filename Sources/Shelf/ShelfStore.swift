import AppKit

/// The files currently parked on the shelf.
///
/// Items are references, never copies: dropping a file here does not move or
/// duplicate it, and dragging one off hands the destination the original URL to
/// do with as it likes.
final class ShelfStore: ObservableObject {

    struct Item: Identifiable, Equatable {
        let id = UUID()
        let url: URL
        let name: String
        let icon: NSImage
        let byteSize: Int64?

        var sizeText: String? {
            byteSize.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
        }

        static func == (lhs: Item, rhs: Item) -> Bool { lhs.url == rhs.url }
    }

    @Published private(set) var items: [Item] = []

    private let defaultsKey = "Shelf.items"

    init() { load() }

    // MARK: Contents

    func add(_ urls: [URL]) {
        var updated = items
        for url in urls {
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let item = Self.makeItem(url)
            // Re-dropping something already here moves it to the front rather
            // than stacking a second copy.
            updated.removeAll { $0.url == item.url }
            updated.insert(item, at: 0)
        }
        items = updated
        persist()
    }

    func remove(_ item: Item) {
        items.removeAll { $0 == item }
        persist()
    }

    func clear() {
        items = []
        persist()
    }

    func revealInFinder(_ item: Item) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    /// Drops entries whose file has since been moved, renamed, or deleted.
    func pruneMissing() {
        let live = items.filter { FileManager.default.fileExists(atPath: $0.url.path) }
        guard live.count != items.count else { return }
        items = live
        persist()
    }

    // MARK: Storage

    /// Normalises here and nowhere else, so an item loaded from disk compares
    /// equal to the same file dropped again. Standardising only on the way in
    /// meant a re-drop after a relaunch produced a duplicate row.
    private static func makeItem(_ raw: URL) -> Item {
        let url = raw.standardizedFileURL
        // Read attributes through the symlink, not of it. Several things in
        // /Applications are links, and reporting the link's own size showed a
        // dragged app as "54 bytes".
        let target = url.resolvingSymlinksInPath()
        let values = try? target.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
        let isDirectory = values?.isDirectory ?? false
        return Item(url: url,
                    name: url.lastPathComponent,
                    icon: NSWorkspace.shared.icon(forFile: url.path),
                    byteSize: isDirectory ? nil : values?.fileSize.map(Int64.init))
    }

    private func load() {
        let paths = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
        items = paths
            .filter { FileManager.default.fileExists(atPath: $0) }
            .map { Self.makeItem(URL(fileURLWithPath: $0)) }
    }

    private func persist() {
        UserDefaults.standard.set(items.map(\.url.path), forKey: defaultsKey)
    }
}
