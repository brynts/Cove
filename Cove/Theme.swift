import SwiftUI

enum CoveTheme {
    static let accent = Color(red: 0.059, green: 0.431, blue: 0.420)
}

enum ByteText {
    static func string(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
}

struct Monogram: View {
    let text: String
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(CoveTheme.accent.opacity(0.16))
            Text(String(text.prefix(1)).uppercased())
                .font(.headline.weight(.semibold))
                .foregroundStyle(CoveTheme.accent)
        }
        .frame(width: 44, height: 44)
    }
}

struct AppIconView: View {
    let bundleID: String
    let name: String
    let revision: Int

    var body: some View {
        let _ = revision
        if let icon = AppIconStore.icon(for: bundleID) {
            Image(uiImage: icon)
                .resizable()
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            Monogram(text: name)
        }
    }
}
