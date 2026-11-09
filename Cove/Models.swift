import Foundation
import UIKit

enum AppIconStore {
    private static var icons: [String: UIImage] = [:]
    private static let lock = NSLock()

    static func set(_ icon: UIImage?, for bundleID: String) {
        guard let icon else { return }
        lock.lock()
        icons[bundleID] = icon
        lock.unlock()
    }

    static func icon(for bundleID: String) -> UIImage? {
        lock.lock()
        defer { lock.unlock() }
        return icons[bundleID]
    }
}

struct InstalledApp: Identifiable, Hashable {
    var id: String { bundleID }
    var bundleID: String
    var displayName: String
    var containerPath: String
    var isSystem: Bool

    var icon: UIImage? { AppIconStore.icon(for: bundleID) }
}

struct ContainerUsage {
    var caches: Int64
    var tmp: Int64
    var total: Int64 { caches + tmp }
}

struct CoveFailure: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}

enum AppTab: Hashable {
    case apps
    case cleaner
}

enum CoveWork {
    static let queue = DispatchQueue(label: "tr.sapu.cove.access")
}

enum PathGuard {
    static func normalize(_ path: String) -> String {
        var value = URL(fileURLWithPath: path).standardizedFileURL.path
        if value.hasPrefix("/var/") { value = "/private" + value }
        return value
    }

    static func isInside(root: String, path: String) -> Bool {
        let base = normalize(root)
        let item = normalize(path)
        return item == base || item.hasPrefix(base + "/")
    }

    static func isApplicationContainer(_ path: String) -> Bool {
        let value = normalize(path)
        guard value.contains("/Containers/Data/Application/") else { return false }
        return UUID(uuidString: URL(fileURLWithPath: value).lastPathComponent) != nil
    }
}
