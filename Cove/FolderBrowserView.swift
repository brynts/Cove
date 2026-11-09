import SwiftUI

enum BrowseSort: String, CaseIterable, Identifiable {
    case name, date, size
    var id: String { rawValue }
    var title: String {
        switch self {
        case .name: return "Name"
        case .date: return "Date"
        case .size: return "Size"
        }
    }
}

struct FolderBrowserView: View {
    let title: String
    let path: String
    let root: String

    @State private var items: [BrowseItem] = []
    @State private var loading = true
    @State private var message: String?
    @State private var opening = false
    @State private var alive = true
    @State private var retained = false
    @State private var query = ""
    @State private var showHidden = false
    @State private var sort: BrowseSort = .name
    @State private var shareURL: URL?
    @State private var pendingDelete: BrowseItem?
    @State private var renameItem: BrowseItem?
    @State private var renameText = ""
    @State private var showNewFolder = false
    @State private var newFolderName = ""
    @State private var showNewFile = false
    @State private var newFileName = ""

    private var visible: [BrowseItem] {
        var list = items
        if !showHidden { list = list.filter { !$0.isHidden } }
        if !query.isEmpty {
            list = list.filter { $0.name.localizedCaseInsensitiveContains(query) }
        }
        switch sort {
        case .name:
            list.sort {
                if $0.isDirectory != $1.isDirectory { return $0.isDirectory && !$1.isDirectory }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        case .date:
            list.sort { ($0.modified ?? .distantPast) > ($1.modified ?? .distantPast) }
        case .size:
            list.sort { $0.size > $1.size }
        }
        return list
    }

    var body: some View {
        Group {
            if loading && items.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if visible.isEmpty {
                ContentUnavailableView(
                    query.isEmpty ? "Empty folder" : "No matches",
                    systemImage: "folder",
                    description: Text(message ?? "")
                )
            } else {
                List(visible) { item in
                    row(item)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { pendingDelete = item } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            Button { share(item) } label: { Label("Share", systemImage: "square.and.arrow.up") }
                            Button {
                                BrowseClipboard.sourcePath = item.path
                                BrowseClipboard.sourceRoot = root
                                BrowseClipboard.cut = false
                            } label: { Label("Copy", systemImage: "doc.on.doc") }
                            Button {
                                renameItem = item
                                renameText = item.name
                            } label: { Label("Rename", systemImage: "pencil") }
                        }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search this folder")
        .toolbar { toolbar }
        .onAppear(perform: open)
        .onDisappear(perform: close)
        .sheet(isPresented: Binding(get: { shareURL != nil }, set: { if !$0 { shareURL = nil } })) {
            if let shareURL { ActivityShareView(items: [shareURL]) }
        }
        .alert("Folder", isPresented: Binding(get: { message != nil && !items.isEmpty }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
        .alert("New folder", isPresented: $showNewFolder) {
            TextField("Name", text: $newFolderName)
            Button("Create") { run { try FileOps.createFolder(named: newFolderName, in: path, root: root) } }
            Button("Cancel", role: .cancel) {}
        }
        .alert("New file", isPresented: $showNewFile) {
            TextField("Name", text: $newFileName)
            Button("Create") { run { try FileOps.createFile(named: newFileName, in: path, root: root) } }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename", isPresented: Binding(get: { renameItem != nil }, set: { if !$0 { renameItem = nil } })) {
            TextField("Name", text: $renameText)
            Button("Save") { renameCurrent() }
            Button("Cancel", role: .cancel) { renameItem = nil }
        }
        .confirmationDialog(
            "Delete \(pendingDelete?.name ?? "this item")?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { deleteCurrent() }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    newFolderName = "New Folder"
                    showNewFolder = true
                } label: { Label("New folder", systemImage: "folder.badge.plus") }
                Button {
                    newFileName = "untitled.txt"
                    showNewFile = true
                } label: { Label("New file", systemImage: "doc.badge.plus") }
                Menu("Sort") {
                    ForEach(BrowseSort.allCases) { option in
                        Button { sort = option } label: {
                            if sort == option { Label(option.title, systemImage: "checkmark") }
                            else { Text(option.title) }
                        }
                    }
                }
                Button { showHidden.toggle() } label: {
                    Label(showHidden ? "Hide hidden" : "Show hidden", systemImage: showHidden ? "eye.slash" : "eye")
                }
                if BrowseClipboard.hasItem && BrowseClipboard.sourceRoot == root {
                    Button { run { try FileOps.paste(into: path, root: root) } } label: {
                        Label("Paste", systemImage: "doc.on.clipboard")
                    }
                }
                Button(action: reload) { Label("Refresh", systemImage: "arrow.clockwise") }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    @ViewBuilder
    private func row(_ item: BrowseItem) -> some View {
        if item.isDirectory {
            NavigationLink {
                FolderBrowserView(title: item.name, path: item.path, root: root)
            } label: {
                label(item)
            }
        } else {
            NavigationLink {
                FilePreviewView(name: item.name, path: item.path, root: root)
            } label: {
                label(item)
            }
        }
    }

    private func label(_ item: BrowseItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon(for: item))
                .foregroundStyle(item.isDirectory ? CoveTheme.accent : .secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).lineLimit(1)
                Text(meta(item))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func icon(for item: BrowseItem) -> String {
        if item.isSymlink { return "link" }
        if item.isDirectory { return "folder.fill" }
        return "doc"
    }

    private func meta(_ item: BrowseItem) -> String {
        if item.isDirectory { return "Folder" }
        return ByteText.string(item.size)
    }

    private func open() {
        alive = true
        if retained {
            reload()
            return
        }
        if opening { return }
        opening = true
        loading = true
        let root = root
        CoveWork.queue.async {
            do {
                try GrantPool.shared.retain(root)
                DispatchQueue.main.async {
                    opening = false
                    if alive {
                        retained = true
                        reload()
                    } else {
                        CoveWork.queue.async { GrantPool.shared.release(root) }
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    opening = false
                    loading = false
                    message = error.localizedDescription
                }
            }
        }
    }

    private func close() {
        alive = false
        guard retained else { return }
        retained = false
        let root = root
        CoveWork.queue.async { GrantPool.shared.release(root) }
    }

    private func reload() {
        loading = true
        let path = path
        let root = root
        CoveWork.queue.async {
            do {
                let listed = try FileOps.list(path: path, root: root)
                DispatchQueue.main.async {
                    items = listed
                    loading = false
                    if listed.isEmpty == false { message = nil }
                }
            } catch {
                DispatchQueue.main.async {
                    loading = false
                    message = error.localizedDescription
                }
            }
        }
    }

    private func run(_ body: @escaping () throws -> Void) {
        let root = root
        CoveWork.queue.async {
            do {
                try body()
                DispatchQueue.main.async { reload() }
            } catch {
                DispatchQueue.main.async { message = error.localizedDescription }
            }
        }
        _ = root
    }

    private func deleteCurrent() {
        guard let item = pendingDelete else { return }
        pendingDelete = nil
        run { try FileOps.delete(item.path, root: root) }
    }

    private func renameCurrent() {
        guard let item = renameItem else { return }
        let name = renameText
        renameItem = nil
        run { try FileOps.rename(item.path, to: name, root: root) }
    }

    private func share(_ item: BrowseItem) {
        let path = item.path
        let root = root
        CoveWork.queue.async {
            do {
                let url = try FileOps.copyForShare(path, root: root)
                DispatchQueue.main.async { shareURL = url }
            } catch {
                DispatchQueue.main.async { message = error.localizedDescription }
            }
        }
    }
}

struct ActivityShareView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
