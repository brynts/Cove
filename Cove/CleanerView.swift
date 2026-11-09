import SwiftUI

struct CleanerView: View {
    @EnvironmentObject private var library: AppLibrary
    @State private var usage: [String: ContainerUsage] = [:]
    @State private var selected = Set<String>()
    @State private var measuring = false
    @State private var busy = false
    @State private var progress = ""
    @State private var cleanCaches = true
    @State private var cleanTmp = true
    @State private var ask = false
    @State private var message: String?
    @State private var storage = DeviceStorage.current()

    private var apps: [InstalledApp] {
        library.apps.filter { !$0.isSystem }
    }

    private var selectedBytes: Int64 {
        selected.reduce(0) { partial, id in
            partial + (usage[id]?.total ?? 0)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Storage")
                            Spacer()
                            Text("\(storage.freeLabel) free")
                                .foregroundStyle(.secondary)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.secondary.opacity(0.2))
                                Capsule()
                                    .fill(CoveTheme.accent)
                                    .frame(width: max(geo.size.width * storage.fraction, 4))
                            }
                        }
                        .frame(height: 8)
                        Text("\(storage.usedLabel) of \(storage.totalLabel) used")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    HStack {
                        Text("Clear")
                        Spacer()
                        chip("Caches", isOn: $cleanCaches)
                        chip("tmp", isOn: $cleanTmp)
                    }
                } footer: {
                    Text("Documents and preferences stay. Only cache and temporary files are removed.")
                }

                Section {
                    if apps.isEmpty {
                        Text(library.scanning ? (library.status.isEmpty ? "Finding apps" : library.status) : "No user apps yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(apps) { app in
                            Button { toggle(app.bundleID) } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: selected.contains(app.bundleID) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selected.contains(app.bundleID) ? CoveTheme.accent : .secondary)
                                        .font(.title3)
                                    AppIconView(bundleID: app.bundleID, name: app.displayName, revision: library.iconRevision)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(app.displayName)
                                            .foregroundStyle(.primary)
                                        Text(detail(app.bundleID))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(busy)
                        }
                    }
                } header: {
                    Text(measuring ? progress : "User apps")
                }
            }
            .navigationTitle("Cleaner")
            .navigationSubtitle(library.osLabel)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(selected.isEmpty ? "Select all" : "Deselect") {
                        if selected.isEmpty {
                            selected = Set(apps.map(\.bundleID))
                        } else {
                            selected.removeAll()
                        }
                    }
                    .disabled(apps.isEmpty || busy)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if measuring || busy || library.scanning {
                        ProgressView()
                    } else {
                        Button(action: measure) {
                            Image(systemName: "arrow.clockwise")
                        }
                        .accessibilityLabel("Measure")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: { ask = true }) {
                    Text(buttonTitle)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selected.isEmpty || busy || measuring || (!cleanCaches && !cleanTmp))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.bar)
            }
            .onAppear {
                storage = DeviceStorage.current()
                if usage.isEmpty, !apps.isEmpty, !library.scanning { measure() }
            }
            .onChange(of: library.scanning) { _, scanning in
                if !scanning, usage.isEmpty, !apps.isEmpty { measure() }
            }
            .confirmationDialog("Clean selected apps?", isPresented: $ask, titleVisibility: .visible) {
                Button("Clean", role: .destructive, action: clean)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(confirmText)
            }
            .alert("Cleaner", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(message ?? "")
            }
        }
    }

    private var buttonTitle: String {
        if busy { return progress }
        let count = selected.count
        return "Clean \(count) app\(count == 1 ? "" : "s") (\(ByteText.string(selectedBytes)))"
    }

    private var confirmText: String {
        var parts: [String] = []
        if cleanCaches { parts.append("Caches") }
        if cleanTmp { parts.append("tmp") }
        return "Removes \(parts.joined(separator: " and ")) (\(ByteText.string(selectedBytes))) from \(selected.count) app\(selected.count == 1 ? "" : "s"). Documents are kept."
    }

    private func detail(_ id: String) -> String {
        guard let item = usage[id] else { return measuring ? "Measuring" : "Not measured" }
        return "Caches \(ByteText.string(item.caches)) · tmp \(ByteText.string(item.tmp))"
    }

    private func toggle(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func chip(_ title: String, isOn: Binding<Bool>) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isOn.wrappedValue ? CoveTheme.accent.opacity(0.18) : Color.secondary.opacity(0.12), in: Capsule())
                .foregroundStyle(isOn.wrappedValue ? CoveTheme.accent : .secondary)
        }
        .buttonStyle(.plain)
    }

    private func measure() {
        let targets = apps
        guard !targets.isEmpty else { return }
        measuring = true
        progress = "Measuring"
        CoveWork.queue.async {
            for (index, app) in targets.enumerated() {
                let value = Self.measureOne(app.containerPath)
                DispatchQueue.main.async {
                    if let value { usage[app.bundleID] = value }
                    progress = "Measuring \(index + 1)/\(targets.count)"
                }
            }
            DispatchQueue.main.async {
                measuring = false
                storage = DeviceStorage.current()
            }
        }
    }

    private func clean() {
        let targets = apps.filter { selected.contains($0.bundleID) }
        let caches = cleanCaches
        let tmp = cleanTmp
        busy = true
        CoveWork.queue.async {
            var removed = 0
            var failed: [String] = []
            for (index, app) in targets.enumerated() {
                DispatchQueue.main.async { progress = "Cleaning \(index + 1)/\(targets.count)" }
                do {
                    removed += try Self.cleanOne(app.containerPath, caches: caches, tmp: tmp)
                    let value = Self.measureOne(app.containerPath)
                    DispatchQueue.main.async {
                        if let value { usage[app.bundleID] = value }
                    }
                } catch {
                    failed.append(app.displayName)
                    CoveWriteLog("clean failed \(app.bundleID) \(error.localizedDescription)")
                }
            }
            DispatchQueue.main.async {
                busy = false
                storage = DeviceStorage.current()
                selected.removeAll()
                if failed.isEmpty {
                    message = "Removed \(removed) item\(removed == 1 ? "" : "s")."
                } else {
                    message = "Removed \(removed) items. Failed: \(failed.joined(separator: ", "))."
                }
            }
        }
    }

    private static func measureOne(_ container: String) -> ContainerUsage? {
        guard PathGuard.isApplicationContainer(container) else { return nil }
        let handle = CoveGrant(container)
        guard handle >= 0 else { return nil }
        defer { CoveRelease(handle) }
        let root = container as NSString
        return ContainerUsage(
            caches: FileOps.directorySize(root.appendingPathComponent("Library/Caches")),
            tmp: FileOps.directorySize(root.appendingPathComponent("tmp"))
        )
    }

    private static func cleanOne(_ container: String, caches: Bool, tmp: Bool) throws -> Int {
        guard PathGuard.isApplicationContainer(container) else {
            throw CoveFailure(message: "Refusing to clean a path that is not an app container.")
        }
        let handle = CoveGrant(container)
        guard handle >= 0 else { throw CoveFailure(message: CoveDescribeGrant(handle)) }
        defer { CoveRelease(handle) }
        var removed = 0
        let root = container as NSString
        if caches { removed += try FileOps.emptyDirectory(root.appendingPathComponent("Library/Caches")) }
        if tmp { removed += try FileOps.emptyDirectory(root.appendingPathComponent("tmp")) }
        CoveWriteLog("cleaned \(container) items=\(removed)")
        return removed
    }
}

struct DeviceStorage {
    var used: Int64
    var total: Int64
    var free: Int64 { max(total - used, 0) }
    var fraction: Double {
        guard total > 0 else { return 0 }
        return min(Double(used) / Double(total), 1)
    }
    var usedLabel: String { ByteText.string(used) }
    var totalLabel: String { ByteText.string(total) }
    var freeLabel: String { ByteText.string(free) }

    static func current() -> DeviceStorage {
        let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [
            .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey
        ])
        let total = Int64(values?.volumeTotalCapacity ?? 0)
        let available = values?.volumeAvailableCapacityForImportantUsage ?? 0
        return DeviceStorage(used: max(total - available, 0), total: total)
    }
}
