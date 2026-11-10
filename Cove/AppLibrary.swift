import Foundation
import UIKit

@MainActor
final class AppLibrary: ObservableObject {
    @Published var apps: [InstalledApp] = []
    @Published var scanning = false
    @Published var status = ""
    @Published var error: String?
    @Published var iconRevision = 0
    @Published var osLabel = ""

    init() {
        osLabel = CoveOSLabel()
        apps = AppDiscovery.loadCachedApps()
        refresh()
    }

    func refresh() {
        guard !scanning else { return }
        scanning = true
        error = nil
        status = "Finding apps"
        CoveWork.queue.async {
            let outcome = AppDiscovery.scan { text in
                DispatchQueue.main.async { self.status = text }
            }
            DispatchQueue.main.async {
                self.scanning = false
                switch outcome {
                case .success(let list):
                    self.apps = list
                    self.error = nil
                    self.status = "\(list.count) apps"
                    self.enrichFromBundles()
                case .failure(let failure):
                    self.status = ""
                    if self.apps.isEmpty {
                        self.error = failure.message
                    } else {
                        self.error = "\(failure.message) Showing the last list."
                    }
                }
            }
        }
    }

    private func enrichFromBundles() {
        let targets = apps
        DispatchQueue.global(qos: .utility).async {
            var records = self.loadBundleCache()
            let missing = targets.filter { records[$0.bundleID] == nil }
            if !missing.isEmpty {
                let found = self.scanBundleIndex()
                for (id, path) in found where records[id] == nil {
                    records[id] = BundleRecord(path: path, name: "")
                }
                self.saveBundleCache(records)
            }
            var icons = 0
            for app in targets {
                let cachedIcon = self.cachedIcon(app.bundleID)
                var icon = cachedIcon
                var name = records[app.bundleID]?.name ?? ""
                if icon == nil, let path = records[app.bundleID]?.path, let info = CoveInspectBundle(path) {
                    if let data = info["icon"] as? Data, let image = UIImage(data: data), image.size.width >= 16 {
                        icon = image
                        self.storeIcon(image, bundleID: app.bundleID)
                    }
                    if let found = info["name"] as? String, !found.isEmpty {
                        name = found
                        records[app.bundleID]?.name = found
                    }
                }
                if icon == nil, let data = CoveSystemIconPNG(app.bundleID),
                   let image = UIImage(data: data), image.size.width >= 16 {
                    icon = image
                    self.storeIcon(image, bundleID: app.bundleID)
                }
                if let icon {
                    icons += 1
                    AppIconStore.set(icon, for: app.bundleID)
                }
                let display = name
                DispatchQueue.main.async {
                    if !display.isEmpty, let index = self.apps.firstIndex(where: { $0.bundleID == app.bundleID }) {
                        var copy = self.apps[index]
                        let generated = AppDiscovery.pretty(copy.bundleID)
                        if copy.displayName == generated || copy.displayName == copy.bundleID {
                            copy.displayName = display
                            self.apps[index] = copy
                        }
                    }
                    self.iconRevision += 1
                }
            }
            self.saveBundleCache(records)
            CoveWriteLog("icons \(icons)/\(targets.count)")
            DispatchQueue.main.async {
                self.apps.sort {
                    $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                }
                AppDiscovery.remember(self.apps)
                if !self.scanning { self.status = "\(self.apps.count) apps" }
            }
        }
    }

    private func scanBundleIndex() -> [String: String] {
        let roots = [
            "/var/containers/Bundle/Application",
            "/private/var/containers/Bundle/Application"
        ]
        let baseline = CoveBaselineInode()
        guard baseline > 1 else { return [:] }
        var root: String?
        for candidate in roots where CoveLeakAppInfoPlists(candidate, 1, 1) != nil {
            root = candidate
            break
        }
        guard let root else {
            CoveWriteLog("bundle statfs failed")
            return [:]
        }
        var infos: [String] = []
        let step: UInt64 = 500_000
        var cursor: UInt64 = 1
        while cursor <= baseline {
            let end = min(baseline, cursor + step - 1)
            if let batch = CoveLeakAppInfoPlists(root, cursor, end) {
                infos.append(contentsOf: batch)
            }
            let percent = Int((end * 100) / max(baseline, 1))
            DispatchQueue.main.async { self.status = "Reading app bundles \(percent)%" }
            if end == baseline { break }
            cursor = end + 1
        }
        CoveWriteLog("bundle plists \(infos.count)")
        var map: [String: String] = [:]
        for plist in infos {
            let appPath = URL(fileURLWithPath: plist).deletingLastPathComponent().path
            guard appPath.hasSuffix(".app") else { continue }
            guard let info = CoveInspectBundle(appPath),
                  let id = info["bundleID"] as? String, id.contains(".") else { continue }
            map[id] = appPath
        }
        return map
    }

    private struct BundleRecord {
        var path: String
        var name: String
    }

    private func cacheURL() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("cove-bundles.tsv")
    }

    private func iconURL(_ bundleID: String) -> URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("icons", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safe = bundleID.replacingOccurrences(of: "/", with: "_")
        return dir.appendingPathComponent(safe + ".png")
    }

    private func cachedIcon(_ bundleID: String) -> UIImage? {
        guard let data = try? Data(contentsOf: iconURL(bundleID)) else { return nil }
        return UIImage(data: data)
    }

    private func storeIcon(_ image: UIImage, bundleID: String) {
        guard let data = image.pngData() else { return }
        try? data.write(to: iconURL(bundleID), options: .atomic)
    }

    private func loadBundleCache() -> [String: BundleRecord] {
        guard let text = try? String(contentsOf: cacheURL(), encoding: .utf8) else { return [:] }
        var map: [String: BundleRecord] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 2, parts[0].contains("."), parts[1].hasSuffix(".app") else { continue }
            map[parts[0]] = BundleRecord(path: parts[1], name: parts.count >= 3 ? parts[2] : "")
        }
        return map
    }

    private func saveBundleCache(_ records: [String: BundleRecord]) {
        let text = records
            .sorted { $0.key < $1.key }
            .map { "\($0.key)\t\($0.value.path)\t\($0.value.name)" }
            .joined(separator: "\n")
        try? text.write(to: cacheURL(), atomically: true, encoding: .utf8)
    }
}
