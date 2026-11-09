import SwiftUI

struct RootTabView: View {
    @State private var tab: AppTab = .apps

    var body: some View {
        TabView(selection: $tab) {
            Tab("Apps", systemImage: "square.grid.2x2.fill", value: AppTab.apps) {
                AppsView()
            }
            Tab("Cleaner", systemImage: "sparkles", value: AppTab.cleaner) {
                CleanerView()
            }
        }
        .tint(CoveTheme.accent)
    }
}
