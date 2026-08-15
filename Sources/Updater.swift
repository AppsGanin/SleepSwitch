import Foundation

// MARK: - Обновления с GitHub

/// Приложение не подписано сертификатом Apple, поэтому оно не подменяет себя само.
/// Максимум, что делает обновление, — скачивает установщик из релиза и отдаёт его
/// системному Installer, где пользователь проходит обычную авторизацию.
enum Updater {
    static let releasesPage = URL(string: "https://github.com/AppsGanin/SleepSwitch/releases")!
    private static let latestAPI = URL(
        string: "https://api.github.com/repos/AppsGanin/SleepSwitch/releases/latest")!

    struct Release {
        let version: String
        let page: URL
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

    /// Ходим только на GitHub и только по https — включая промежуточные редиректы,
    /// на которые уводит ссылка на ассет релиза.
    static func isTrusted(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
        return host == "github.com"
            || host.hasSuffix(".github.com")
            || host.hasSuffix(".githubusercontent.com")
    }

    private final class RedirectGuard: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            let allowed = request.url.map(Updater.isTrusted) ?? false
            completionHandler(allowed ? request : nil)
        }
    }

    private static let guardDelegate = RedirectGuard()
    private static let session = URLSession(configuration: .ephemeral,
                                            delegate: guardDelegate,
                                            delegateQueue: nil)

    private static func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("SleepSwitch/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        return request
    }

    static func fetchLatest(completion: @escaping (Result<Release, Failure>) -> Void) {
        session.dataTask(with: request(latestAPI)) { data, _, error in
            let result: Result<Release, Failure>
            if let error {
                result = .failure(.network(error.localizedDescription))
            } else if let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tag = json["tag_name"] as? String {
                let page = (json["html_url"] as? String).flatMap(URL.init(string:)) ?? releasesPage
                let assets = json["assets"] as? [[String: Any]] ?? []
                let packages = assets.compactMap { asset -> URL? in
                    guard let name = asset["name"] as? String, name.hasSuffix(".pkg"),
                          let link = asset["browser_download_url"] as? String,
                          let url = URL(string: link), isTrusted(url) else { return nil }
                    return url
                }
                result = .success(Release(version: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag,
                                          page: page,
                                          package: packages.first))
            } else {
                result = .failure(.malformed)
            }
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }

    /// Скачивает пакет во временную папку и возвращает путь к нему.
    static func download(_ url: URL, completion: @escaping (Result<URL, Failure>) -> Void) {
        guard isTrusted(url) else {
            DispatchQueue.main.async { completion(.failure(.noPackage)) }
            return
        }
        session.downloadTask(with: request(url)) { location, response, error in
            let result: Result<URL, Failure>
            if let error {
                result = .failure(.network(error.localizedDescription))
            } else if let location,
                      (response as? HTTPURLResponse)?.statusCode == 200 {
                let name = url.lastPathComponent.isEmpty ? "SleepSwitch.pkg" : url.lastPathComponent
                let target = URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent("SleepSwitch-update", isDirectory: true)
                do {
                    try? FileManager.default.removeItem(at: target)
                    try FileManager.default.createDirectory(at: target,
                                                            withIntermediateDirectories: true)
                    let destination = target.appendingPathComponent(name)
                    try FileManager.default.moveItem(at: location, to: destination)
                    result = .success(destination)
                } catch {
                    result = .failure(.network(error.localizedDescription))
                }
            } else {
                result = .failure(.malformed)
            }
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }

    /// «1.10.0» новее «1.9.3»: сравниваем числами по компонентам, а не строками.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let left = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let right = current.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0 ..< max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a > b }
        }
        return false
    }
}
