import Foundation

enum AppDiscovery {
    static func scan(progress: (String) -> Void) -> Result<[InstalledApp], CoveFailure> {
        #if targetEnvironment(simulator)
        return .failure(CoveFailure(message: "Cove has to run on an iPhone. The simulator cannot open other app containers."))
        #endif

        let os = CoveOSLabel()
        CoveWriteLog("scan start \(os)")
        progress("Checking \(os)")
        guard CoveOSIsSupported() else {
            let message = "\(os) is outside iOS 26.0-26.7.2 and 27.0-27.2."
            CoveWriteLog(message)
            return .failure(CoveFailure(message: message))
        }
        if let group = CoveAppGroupContainer(), !group.isEmpty {
            CoveWriteLog("group \(group)")
        } else {
            CoveWriteLog("no app group. \(CoveProvisioningGroupsSummary())")
        }

        progress("Reading installed apps")
        if let listed = appsFromCatalog() {
            CoveWriteLog("scan done catalog \(listed.count)")
            return .success(listed)
        }

        progress("Listing application containers")
        let roots = [
            "/var/mobile/Containers/Data/Application",
            "/private/var/mobile/Containers/Data/Application"
        ]
        var containers: [String] = []
        var lastError = ""
        // iOS 27.0.1 does not issue a token for these parent folders.
        if os.hasPrefix("iOS 27") {
            CoveWriteLog("parent folder has no token on iOS 27, scanning inodes")
        } else {
            for root in roots {
                let listed = CoveListChildren(root)
                CoveWriteLog("list \(root) code=\(listed.code) count=\(listed.paths.count) \(listed.errorText)")
                if listed.code >= 0, !listed.paths.isEmpty {
                    containers = listed.paths
                    break
                }
                if !listed.errorText.isEmpty { lastError = listed.errorText }
            }
        }
        if containers.isEmpty {
            containers = leakContainers(roots: roots, progress: progress)
        }

        let folders = containers.filter {
            UUID(uuidString: URL(fileURLWithPath: $0).lastPathComponent) != nil
        }
        if folders.isEmpty {
            let message = lastError.isEmpty
                ? "No application containers were visible."
                : "No application containers were visible. \(lastError)"
            CoveWriteLog(message)
            return .failure(CoveFailure(message: message))
        }

        let known = loadCache()
        var byID: [String: InstalledApp] = [:]
        for (index, raw) in folders.enumerated() {
            progress("Reading apps \(index + 1)/\(folders.count)")
            let path = PathGuard.normalize(raw)
            let uuid = URL(fileURLWithPath: path).lastPathComponent
            let bundleID = CoveContainerIdentifier(path) ?? known[path]?.bundleID ?? uuid
            guard bundleID.contains(".") || UUID(uuidString: bundleID) != nil else { continue }
            let cachedName = known[path]?.name
            byID[bundleID] = InstalledApp(
                bundleID: bundleID,
                displayName: (cachedName?.isEmpty == false) ? cachedName! : pretty(bundleID),
                containerPath: path,
                isSystem: isSystem(bundleID)
            )
        }
        let apps = sorted(byID)
        saveCache(apps)
        CoveWriteLog("scan done \(apps.count)")
        if apps.isEmpty {
            return .failure(CoveFailure(message: "Containers were listed, but none had a bundle identifier."))
        }
        return .success(apps)
    }

    private static func appsFromCatalog() -> [InstalledApp]? {
        let catalog = CoveInstalledApplications()
        CoveWriteLog("catalog \(catalog.count) \(CoveCatalogStatus())")
        guard catalog.count > 0 else { return nil }
        var byID: [String: InstalledApp] = [:]
        var withPath = 0
        for entry in catalog {
            guard let bundleID = entry["bundleID"], bundleID.contains(".") else { continue }
            let rawName = entry["name"] ?? ""
            let rawPath = entry["container"] ?? ""
            let path = rawPath.isEmpty ? "" : PathGuard.normalize(rawPath)
            if !path.isEmpty { withPath += 1 }
            byID[bundleID] = InstalledApp(
                bundleID: bundleID,
                displayName: rawName.isEmpty ? pretty(bundleID) : rawName,
                containerPath: path,
                isSystem: isSystem(bundleID)
            )
        }
        CoveWriteLog("catalog apps=\(byID.count) paths=\(withPath)")
        let apps = sorted(byID).filter { !$0.containerPath.isEmpty }
        guard !apps.isEmpty else { return nil }
        saveCache(apps)
        return apps
    }

    private static func sorted(_ byID: [String: InstalledApp]) -> [InstalledApp] {
        byID.values.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    static func loadCachedApps() -> [InstalledApp] {
        loadCache().values.map {
            InstalledApp(
                bundleID: $0.bundleID,
                displayName: $0.name.isEmpty ? pretty($0.bundleID) : $0.name,
                containerPath: $0.path,
                isSystem: isSystem($0.bundleID)
            )
        }
        .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    static func remember(_ apps: [InstalledApp]) {
        saveCache(apps)
    }

    static func isSystem(_ bundleID: String) -> Bool {
        bundleID.hasPrefix("com.apple.") || bundleID.hasPrefix("systemgroup.")
    }

    static func pretty(_ bundleID: String) -> String {
        let last = bundleID.split(separator: ".").last.map(String.init) ?? bundleID
        guard let first = last.first else { return bundleID }
        return first.uppercased() + last.dropFirst()
    }

    private struct Cached {
        var bundleID: String
        var path: String
        var name: String
    }

    private static func cacheURL() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("cove-apps.tsv")
    }

    private static func loadCache() -> [String: Cached] {
        guard let text = try? String(contentsOf: cacheURL(), encoding: .utf8) else { return [:] }
        var map: [String: Cached] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 3, parts[0].contains(".") || UUID(uuidString: parts[0]) != nil, parts[1].hasPrefix("/") else { continue }
            map[parts[1]] = Cached(bundleID: parts[0], path: parts[1], name: parts[2])
        }
        return map
    }

    private static func saveCache(_ apps: [InstalledApp]) {
        let text = apps.map { "\($0.bundleID)\t\($0.containerPath)\t\($0.displayName)" }.joined(separator: "\n")
        try? text.write(to: cacheURL(), atomically: true, encoding: .utf8)
    }

    private static func leakContainers(roots: [String], progress: (String) -> Void) -> [String] {
        progress("Scanning inodes")
        let baseline = CoveBaselineInode()
        CoveWriteLog("leak baseline \(baseline)")
        guard baseline > 1 else { return [] }
        var usable: String?
        for root in roots {
            if CoveLeakRange(root, 1, 1) != nil {
                usable = root
                break
            }
        }
        guard let root = usable else {
            CoveWriteLog("leak statfs failed")
            return []
        }
        var found: [String] = []
        let step: UInt64 = 500_000
        var cursor: UInt64 = 1
        while cursor <= baseline {
            let end = min(baseline, cursor + step - 1)
            if let batch = CoveLeakRange(root, cursor, end) {
                found.append(contentsOf: batch)
            }
            progress("Scanning inodes \(Int((end * 100) / max(baseline, 1)))%")
            if end == baseline { break }
            cursor = end + 1
        }
        CoveWriteLog("leak found \(found.count) range 1-\(baseline)")
        return found
    }
}
