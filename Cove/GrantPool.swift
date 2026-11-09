import Foundation

final class GrantPool {
    static let shared = GrantPool()
    private var entries: [String: (handle: Int64, count: Int)] = [:]
    private let lock = NSLock()

    func retain(_ root: String) throws {
        let key = PathGuard.normalize(root)
        lock.lock()
        if var entry = entries[key] {
            entry.count += 1
            entries[key] = entry
            lock.unlock()
            return
        }
        lock.unlock()

        let handle = CoveGrant(key)
        guard handle >= 0 else {
            throw CoveFailure(message: CoveDescribeGrant(handle))
        }

        lock.lock()
        if var entry = entries[key] {
            entry.count += 1
            entries[key] = entry
            lock.unlock()
            CoveRelease(handle)
            return
        }
        entries[key] = (handle, 1)
        lock.unlock()
    }

    func release(_ root: String) {
        let key = PathGuard.normalize(root)
        lock.lock()
        guard var entry = entries[key] else {
            lock.unlock()
            return
        }
        entry.count -= 1
        if entry.count <= 0 {
            entries.removeValue(forKey: key)
            lock.unlock()
            CoveRelease(entry.handle)
        } else {
            entries[key] = entry
            lock.unlock()
        }
    }
}
