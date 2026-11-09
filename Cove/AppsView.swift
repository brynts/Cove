import SwiftUI

struct AppsView: View {
    @EnvironmentObject private var library: AppLibrary
    @State private var search = ""
    @State private var scope: Scope = .user
    @State private var showLogs = false

    private enum Scope: String, CaseIterable, Identifiable {
        case user = "User"
        case system = "System"
        var id: String { rawValue }
    }

    private var rows: [InstalledApp] {
        let base = library.apps.filter { scope == .system ? $0.isSystem : !$0.isSystem }
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return base }
        return base.filter {
            $0.displayName.localizedCaseInsensitiveContains(q)
                || $0.bundleID.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if library.scanning && library.apps.isEmpty {
                    VStack(spacing: 14) {
                        ProgressView()
                        Text(library.status.isEmpty ? "Finding apps" : library.status)
                            .font(.headline)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = library.error, library.apps.isEmpty {
                    ContentUnavailableView {
                        Label("Could not list apps", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Try again") { library.refresh() }
                        Button("View log") { showLogs = true }
                    }
                } else if rows.isEmpty {
                    ContentUnavailableView(
                        scope == .user ? "No user apps" : "No system apps",
                        systemImage: "square.grid.2x2",
                        description: Text("Pull to refresh.")
                    )
                } else {
                    List(rows) { app in
                        NavigationLink {
                            AppDetailView(app: app)
                        } label: {
                            HStack(spacing: 12) {
                                AppIconView(
                                    bundleID: app.bundleID,
                                    name: app.displayName,
                                    revision: library.iconRevision
                                )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(app.displayName)
                                        .font(.headline)
                                    Text(app.bundleID)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .overlay(alignment: .top) {
                        if library.scanning {
                            Text(library.status)
                                .font(.footnote)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity)
                                .background(.bar)
                        }
                    }
                }
            }
            .navigationTitle("Apps")
            .navigationSubtitle(library.osLabel)
            .searchable(text: $search, prompt: "Name or bundle ID")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        ForEach(Scope.allCases) { option in
                            Button {
                                scope = option
                            } label: {
                                if option == scope {
                                    Label(option.rawValue, systemImage: "checkmark")
                                } else {
                                    Text(option.rawValue)
                                }
                            }
                        }
                    } label: {
                        Text(scope.rawValue)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showLogs = true } label: {
                        Image(systemName: "doc.text.magnifyingglass")
                    }
                    .accessibilityLabel("Log")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if library.scanning {
                        ProgressView()
                    } else {
                        Button { library.refresh() } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .accessibilityLabel("Refresh")
                    }
                }
            }
            .refreshable { library.refresh() }
            .sheet(isPresented: $showLogs) { LogsSheet() }
        }
    }
}
