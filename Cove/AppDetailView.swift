import SwiftUI

struct AppDetailView: View {
    let app: InstalledApp

    private var folders: [(String, String, String)] {
        let root = app.containerPath as NSString
        return [
            ("Documents", "doc.fill", root.appendingPathComponent("Documents")),
            ("Library", "books.vertical.fill", root.appendingPathComponent("Library")),
            ("Caches", "internaldrive", root.appendingPathComponent("Library/Caches")),
            ("Preferences", "switch.2", root.appendingPathComponent("Library/Preferences")),
            ("tmp", "clock", root.appendingPathComponent("tmp"))
        ]
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    AppIconView(bundleID: app.bundleID, name: app.displayName, revision: 0)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.displayName).font(.headline)
                        Text(app.bundleID)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
            Section("Container") {
                NavigationLink {
                    FolderBrowserView(title: "Container", path: app.containerPath, root: app.containerPath)
                } label: {
                    Label("Browse all files", systemImage: "folder")
                }
                Text(app.containerPath)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Section("Folders") {
                ForEach(folders, id: \.2) { name, symbol, path in
                    NavigationLink {
                        FolderBrowserView(title: name, path: path, root: app.containerPath)
                    } label: {
                        Label(name, systemImage: symbol)
                    }
                }
            }
        }
        .navigationTitle(app.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }
}
