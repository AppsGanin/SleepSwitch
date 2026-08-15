import Foundation

/// Talks to the GitHub releases API and fetches the installer package.
///
/// Network only — deciding what to show and when belongs to `UpdateCoordinator`, which
/// keeps this half free of AppKit and testable on its own (`Tools/test-updater.swift`).
enum Updater {
    static let releasesPage = URL(string: "https://github.com/AppsGanin/SleepSwitch/releases")!

    private static let latestReleaseAPI = URL(
        string: "https://api.github.com/repos/AppsGanin/SleepSwitch/releases/latest")!

    private static let requestTimeout: TimeInterval = 15

    struct Release {
        let version: String
        let page: URL
        /// Absent when a release carries no `.pkg`, in which case the page is the fallback.
        let package: URL?
    }

    enum Failure: Error {
        case network(String)
        case malformed
        case noPackage
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// GitHub over https and nothing else — redirects included, since an asset link
    /// bounces through a separate download host.
    static func isTrusted(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
        return host == "github.com"
            || host.hasSuffix(".github.com")
            || host.hasSuffix(".githubusercontent.com")
    }

    /// `"1.10.0"` is newer than `"1.9.3"`: compare component by component as numbers,
    /// never as strings.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let left = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let right = current.split(separator: ".").map { Int($0) ?? 0 }

        for index in 0 ..< max(left.count, right.count) {
            let candidatePart = index < left.count ? left[index] : 0
            let currentPart = index < right.count ? right[index] : 0
            if candidatePart != currentPart { return candidatePart > currentPart }
        }
        return false
    }

    static func fetchLatest(completion: @escaping (Result<Release, Failure>) -> Void) {
        session.dataTask(with: request(for: latestReleaseAPI)) { data, _, error in
            let result: Result<Release, Failure>
            if let error {
                result = .failure(.network(error.localizedDescription))
            } else if let data, let release = parseRelease(data) {
                result = .success(release)
            } else {
                result = .failure(.malformed)
            }
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }

    /// Downloads the package into a temporary directory and hands back its path.
    static func download(_ url: URL, completion: @escaping (Result<URL, Failure>) -> Void) {
        guard isTrusted(url) else {
            DispatchQueue.main.async { completion(.failure(.noPackage)) }
            return
        }

        session.downloadTask(with: request(for: url)) { location, response, error in
            let result: Result<URL, Failure>
            if let error {
                result = .failure(.network(error.localizedDescription))
            } else if let location, (response as? HTTPURLResponse)?.statusCode == 200 {
                result = Result { try store(location, named: url.lastPathComponent) }
                    .mapError { Failure.network($0.localizedDescription) }
            } else {
                result = .failure(.malformed)
            }
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }

    // MARK: - Parsing

    private static func parseRelease(_ data: Data) -> Release? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String else { return nil }

        let page = (json["html_url"] as? String).flatMap(URL.init(string:)) ?? releasesPage
        let assets = json["assets"] as? [[String: Any]] ?? []
        let packages = assets.compactMap { asset -> URL? in
            guard let name = asset["name"] as? String, name.hasSuffix(".pkg"),
                  let link = asset["browser_download_url"] as? String,
                  let url = URL(string: link), isTrusted(url) else { return nil }
            return url
        }

        return Release(version: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag,
                       page: page,
                       package: packages.first)
    }

    private static func store(_ downloaded: URL, named name: String) throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("SleepSwitch-update", isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let destination = directory
            .appendingPathComponent(name.isEmpty ? "SleepSwitch.pkg" : name)
        try FileManager.default.moveItem(at: downloaded, to: destination)
        return destination
    }

    // MARK: - Session

    /// URLSession follows redirects on its own, so the allow-list has to be enforced on
    /// every hop rather than on the original URL alone.
    private final class RedirectGuard: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            let allowed = request.url.map(Updater.isTrusted) ?? false
            completionHandler(allowed ? request : nil)
        }
    }

    private static let redirectGuard = RedirectGuard()

    private static let session = URLSession(configuration: .ephemeral,
                                            delegate: redirectGuard,
                                            delegateQueue: nil)

    private static func request(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("SleepSwitch/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = requestTimeout
        return request
    }
}
