import Foundation

struct BrowseItem: Identifiable, Hashable {
    var id: String { path }
    var name: String
    var path: String
    var isDirectory: Bool
    var isSymlink: Bool
    var size: Int64
    var modified: Date?

    var isHidden: Bool { name.hasPrefix(".") }
}

enum BrowseClipboard {
    static var sourcePath: String?
    static var sourceRoot: String?
    static var cut = false
    static var hasItem: Bool { sourcePath != nil }
}

enum FileOps {
    static func list(path: String, root: String) throws -> [BrowseItem] {
        guard PathGuard.isInside(root: root, path: path) else {
            throw CoveFailure(message: "That path is outside this container.")
        }
        if let items = try? read(path) { return items }
        let handle = CoveGrant(path)
        guard handle >= 0 else { throw CoveFailure(message: CoveDescribeGrant(handle)) }
        defer { CoveRelease(handle) }
        return try read(path)
    }

    static func delete(_ path: String, root: String) throws {
        guard PathGuard.isInside(root: root, path: path), path != PathGuard.normalize(root) else {
            throw CoveFailure(message: "Refusing to delete that path.")
        }
        try FileManager.default.removeItem(atPath: path)
    }

    static func rename(_ path: String, to name: String, root: String) throws {
        let cleaned = try safeName(name)
        guard PathGuard.isInside(root: root, path: path) else {
            throw CoveFailure(message: "That path is outside this container.")
        }
        let folder = (path as NSString).deletingLastPathComponent
        let dest = (folder as NSString).appendingPathComponent(cleaned)
        guard PathGuard.isInside(root: root, path: dest) else {
            throw CoveFailure(message: "The new name leaves the container.")
        }
        if FileManager.default.fileExists(atPath: dest) {
            throw CoveFailure(message: "A file with that name already exists.")
        }
        try FileManager.default.moveItem(atPath: path, toPath: dest)
    }

    static func createFolder(named name: String, in folder: String, root: String) throws {
        let cleaned = try safeName(name)
        let dest = (folder as NSString).appendingPathComponent(cleaned)
        guard PathGuard.isInside(root: root, path: dest) else {
            throw CoveFailure(message: "That folder would leave the container.")
        }
        try FileManager.default.createDirectory(atPath: dest, withIntermediateDirectories: false)
    }

    static func createFile(named name: String, in folder: String, root: String) throws {
        let cleaned = try safeName(name)
        let dest = (folder as NSString).appendingPathComponent(cleaned)
        guard PathGuard.isInside(root: root, path: dest) else {
            throw CoveFailure(message: "That file would leave the container.")
        }
        if FileManager.default.fileExists(atPath: dest) {
            throw CoveFailure(message: "A file with that name already exists.")
        }
        guard FileManager.default.createFile(atPath: dest, contents: Data()) else {
            throw CoveFailure(message: "Could not create the file.")
        }
    }

    static func paste(into folder: String, root: String) throws {
        guard let source = BrowseClipboard.sourcePath,
              BrowseClipboard.sourceRoot == root,
              PathGuard.isInside(root: root, path: source),
              PathGuard.isInside(root: root, path: folder)
        else { throw CoveFailure(message: "Nothing to paste in this container.") }
        let name = (source as NSString).lastPathComponent
        var dest = (folder as NSString).appendingPathComponent(name)
        var n = 2
        while FileManager.default.fileExists(atPath: dest) {
            let base = (name as NSString).deletingPathExtension
            let ext = (name as NSString).pathExtension
            let next = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
            dest = (folder as NSString).appendingPathComponent(next)
            n += 1
        }
        if BrowseClipboard.cut {
            try FileManager.default.moveItem(atPath: source, toPath: dest)
            BrowseClipboard.sourcePath = nil
        } else {
            try FileManager.default.copyItem(atPath: source, toPath: dest)
        }
    }

    static func readData(at path: String, root: String, limit: Int) throws -> Data {
        guard PathGuard.isInside(root: root, path: path) else {
            throw CoveFailure(message: "That path is outside this container.")
        }
        let url = URL(fileURLWithPath: path)
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        if let size = values.fileSize, size > limit {
            throw CoveFailure(message: "This file is too large to preview.")
        }
        return try Data(contentsOf: url)
    }

    static func write(_ data: Data, to path: String, root: String) throws {
        guard PathGuard.isInside(root: root, path: path) else {
            throw CoveFailure(message: "That path is outside this container.")
        }
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    static func copyForShare(_ path: String, root: String) throws -> URL {
        guard PathGuard.isInside(root: root, path: path) else {
            throw CoveFailure(message: "That path is outside this container.")
        }
        let name = (path as NSString).lastPathComponent
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(atPath: path, toPath: dest.path)
        return dest
    }

    static func directorySize(_ path: String) -> Int64 {
        var total: Int64 = 0
        var stack = [path]
        let fm = FileManager.default
        while let current = stack.popLast() {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: current, isDirectory: &isDir) else { continue }
            guard let children = try? fm.contentsOfDirectory(atPath: current) else { continue }
            for name in children {
                let child = (current as NSString).appendingPathComponent(name)
                let url = URL(fileURLWithPath: child)
                let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .fileSizeKey])
                if values?.isSymbolicLink == true { continue }
                if values?.isDirectory == true {
                    stack.append(child)
                } else {
                    total += Int64(values?.fileSize ?? 0)
                }
            }
            if !isDir.boolValue { break }
        }
        return total
    }

    static func emptyDirectory(_ path: String) throws -> Int {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        if !fm.fileExists(atPath: path, isDirectory: &isDir) {
            try fm.createDirectory(atPath: path, withIntermediateDirectories: true)
            return 0
        }
        let children = try fm.contentsOfDirectory(atPath: path)
        for name in children {
            try fm.removeItem(atPath: (path as NSString).appendingPathComponent(name))
        }
        return children.count
    }

    private static func read(_ path: String) throws -> [BrowseItem] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [
                .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey
            ],
            options: []
        )
        return urls.map { url in
            let values = try? url.resourceValues(forKeys: [
                .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey
            ])
            return BrowseItem(
                name: url.lastPathComponent,
                path: url.path,
                isDirectory: values?.isDirectory == true && values?.isSymbolicLink != true,
                isSymlink: values?.isSymbolicLink == true,
                size: Int64(values?.fileSize ?? 0),
                modified: values?.contentModificationDate
            )
        }
    }

    private static func safeName(_ name: String) throws -> String {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned != ".", cleaned != "..",
              !cleaned.contains("/"), !cleaned.contains(":")
        else { throw CoveFailure(message: "That name is not allowed.") }
        return cleaned
    }
}
