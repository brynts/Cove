import SwiftUI

@main
struct CoveApp: App {
    @StateObject private var library = AppLibrary()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(library)
                .tint(CoveTheme.accent)
        }
    }
}
