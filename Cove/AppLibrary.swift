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

    private var lookedUp = Set<String>()

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
                    self.enrichStore()
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

    private func enrichStore() {
        let targets = apps.filter { !$0.isSystem && !lookedUp.contains($0.bundleID) }
        guard !targets.isEmpty else { return }
        DispatchQueue.global(qos: .utility).async {
            for app in targets {
                DispatchQueue.main.async { self.lookedUp.insert(app.bundleID) }
                guard let hit = Self.itunesLookup(bundleID: app.bundleID) else { continue }
                if let icon = hit.icon { AppIconStore.set(icon, for: app.bundleID) }
                DispatchQueue.main.async {
                    if let index = self.apps.firstIndex(where: { $0.bundleID == app.bundleID }) {
                        var copy = self.apps[index]
                        copy.displayName = hit.name
                        self.apps[index] = copy
                        self.apps.sort {
                            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                        }
                        AppDiscovery.remember(self.apps)
                    }
                    self.iconRevision += 1
                }
            }
        }
    }

    private static func itunesLookup(bundleID: String) -> (name: String, icon: UIImage?)? {
        let nameKey = "cove.itunes.name.\(bundleID)"
        let artKey = "cove.itunes.art.\(bundleID)"
        if let stored = UserDefaults.standard.string(forKey: nameKey), !stored.isEmpty {
            return (stored, icon(from: UserDefaults.standard.string(forKey: artKey)))
        }
        for country in ["id", "us"] {
            var comps = URLComponents(string: "https://itunes.apple.com/lookup")
            comps?.queryItems = [
                URLQueryItem(name: "bundleId", value: bundleID),
                URLQueryItem(name: "country", value: country)
            ]
            guard let url = comps?.url else { continue }
            var request = URLRequest(url: url, timeoutInterval: 6)
            request.cachePolicy = .returnCacheDataElseLoad
            guard let data = try? URLSession.shared.syncData(request),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]],
                  let first = results.first
            else { continue }
            let name = (first["trackName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let name, !name.isEmpty else { continue }
            let art = (first["artworkUrl100"] as? String) ?? (first["artworkUrl60"] as? String)
            UserDefaults.standard.set(name, forKey: nameKey)
            if let art { UserDefaults.standard.set(art, forKey: artKey) }
            return (name, icon(from: art))
        }
        return nil
    }

    private static func icon(from urlString: String?) -> UIImage? {
        guard let urlString, let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 6)
        request.cachePolicy = .returnCacheDataElseLoad
        guard let data = try? URLSession.shared.syncData(request),
              let image = UIImage(data: data),
              image.size.width >= 16
        else { return nil }
        return image
    }
}

private extension URLSession {
    func syncData(_ request: URLRequest) throws -> Data {
        var result: Result<Data, Error> = .failure(URLError(.badServerResponse))
        let sem = DispatchSemaphore(value: 0)
        let task = dataTask(with: request) { data, _, error in
            if let data, error == nil {
                result = .success(data)
            } else {
                result = .failure(error ?? URLError(.badServerResponse))
            }
            sem.signal()
        }
        task.resume()
        _ = sem.wait(timeout: .now() + request.timeoutInterval + 1)
        return try result.get()
    }
}
