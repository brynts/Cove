import SwiftUI
import UIKit

struct FilePreviewView: View {
    let name: String
    let path: String
    let root: String

    @State private var text = ""
    @State private var image: UIImage?
    @State private var note = "Loading"
    @State private var editable = false
    @State private var suppressEdit = false
    @State private var dirty = false
    @State private var message: String?
    @State private var shareURL: URL?

    var body: some View {
        Group {
            if let image {
                ScrollView {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding()
                }
            } else if editable {
                TextEditor(text: $text)
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal, 8)
                    .onChange(of: text) { _, _ in
                        if suppressEdit { suppressEdit = false; return }
                        dirty = true
                    }
            } else if !text.isEmpty {
                ScrollView {
                    Text(text)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
            } else {
                ContentUnavailableView("No preview", systemImage: "doc", description: Text(note))
            }
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if editable {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .disabled(!dirty)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { share() } label: { Image(systemName: "square.and.arrow.up") }
                    .accessibilityLabel("Share")
            }
        }
        .onAppear(perform: load)
        .sheet(isPresented: Binding(get: { shareURL != nil }, set: { if !$0 { shareURL = nil } })) {
            if let shareURL { ActivityShareView(items: [shareURL]) }
        }
        .alert("File", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }

    private func load() {
        let path = path
        let root = root
        CoveWork.queue.async {
            do {
                let data = try Self.readPreview(path: path, root: root)
                let ext = (path as NSString).pathExtension.lowercased()
                if ["png", "jpg", "jpeg", "heic", "heif", "gif", "webp", "bmp"].contains(ext),
                   let picture = UIImage(data: data) {
                    DispatchQueue.main.async { image = picture }
                    return
                }
                if let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
                   let pretty = plistText(plist) {
                    DispatchQueue.main.async {
                        text = pretty
                        editable = false
                        dirty = false
                        note = ""
                    }
                    return
                }
                if data.contains(0) {
                    DispatchQueue.main.async { note = "Binary file, \(ByteText.string(Int64(data.count)))." }
                    return
                }
                guard let string = String(data: data, encoding: .utf8) else {
                    DispatchQueue.main.async { note = "This file is not UTF-8 text." }
                    return
                }
                DispatchQueue.main.async {
                    suppressEdit = true
                    text = string
                    editable = true
                    dirty = false
                }
            } catch {
                DispatchQueue.main.async { note = error.localizedDescription }
            }
        }
    }

    private func save() {
        let body = text
        let path = path
        let root = root
        CoveWork.queue.async {
            do {
                let bodyData = Data(body.utf8)
                let handle = CoveGrant(path)
                defer { if handle >= 0 { CoveRelease(handle) } }
                try FileOps.write(bodyData, to: path, root: root)
                DispatchQueue.main.async {
                    dirty = false
                    message = "Saved."
                }
            } catch {
                DispatchQueue.main.async { message = error.localizedDescription }
            }
        }
    }

    private func share() {
        let path = path
        let root = root
        CoveWork.queue.async {
            do {
                let handle = CoveGrant(path)
                defer { if handle >= 0 { CoveRelease(handle) } }
                let url = try FileOps.copyForShare(path, root: root)
                DispatchQueue.main.async { shareURL = url }
            } catch {
                DispatchQueue.main.async { message = error.localizedDescription }
            }
        }
    }

    private static func readPreview(path: String, root: String) throws -> Data {
        if let data = try? FileOps.readData(at: path, root: root, limit: 1_500_000) {
            return data
        }
        let handle = CoveGrant(path)
        defer { if handle >= 0 { CoveRelease(handle) } }
        return try FileOps.readData(at: path, root: root, limit: 1_500_000)
    }

    private func plistText(_ value: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(value) || value is NSDictionary || value is NSArray else {
            return String(describing: value)
        }
        guard let data = try? PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0),
              let string = String(data: data, encoding: .utf8)
        else { return nil }
        return string
    }
}
