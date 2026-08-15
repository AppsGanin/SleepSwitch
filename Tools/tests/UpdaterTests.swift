import Foundation

func runUpdaterTests() {
    Test.section("Updater: version comparison")
    Test.expect(Updater.isNewer("1.0.1", than: "1.0.0"), "1.0.1 is newer than 1.0.0")
    Test.expect(Updater.isNewer("1.10.0", than: "1.9.3"), "1.10.0 beats 1.9.3 — not a string compare")
    Test.expect(Updater.isNewer("2.0", than: "1.99.99"), "2.0 is newer than 1.99.99")
    Test.expect(Updater.isNewer("1.1", than: "1.0.9"), "uneven lengths: 1.1 is newer than 1.0.9")
    Test.expect(!Updater.isNewer("1.0.0", than: "1.0.0"), "equal versions are not newer")
    Test.expect(!Updater.isNewer("1.0.0", than: "1.0.1"), "an older version is not newer")
    Test.expect(!Updater.isNewer("1.0", than: "1.0.0"), "1.0 is not newer than 1.0.0")
    Test.expect(!Updater.isNewer("garbage", than: "1.0.0"), "garbage does not pass as a new version")

    Test.section("Updater: download source filter")
    Test.expect(Updater.isTrusted(URL(string: "https://github.com/AppsGanin/SleepSwitch/x.pkg")!),
                "github.com is allowed")
    Test.expect(Updater.isTrusted(URL(string: "https://objects.githubusercontent.com/a/b.pkg")!),
                "objects.githubusercontent.com is allowed")
    Test.expect(!Updater.isTrusted(URL(string: "http://github.com/a.pkg")!),
                "plain http is refused")
    Test.expect(!Updater.isTrusted(URL(string: "https://evil.com/a.pkg")!),
                "an unrelated host is refused")
    Test.expect(!Updater.isTrusted(URL(string: "https://github.com.evil.com/a.pkg")!),
                "the look-alike host github.com.evil.com is refused")
    Test.expect(!Updater.isTrusted(URL(string: "file:///tmp/a.pkg")!),
                "a local file is refused")
}

/// Only runs with --network. CI stays offline so a GitHub outage or a rate limit can
/// never turn the build red.
func runUpdaterNetworkTests() {
    Test.section("Updater: live request to GitHub")
    var finished = false

    Updater.fetchLatest { result in
        switch result {
        case .success(let release):
            Test.expect(!release.version.isEmpty, "version parsed: \(release.version)")
            Test.expect(release.version.first?.isNumber == true, "the leading “v” is stripped")
            Test.expect(release.package != nil,
                        "the release carries a .pkg: \(release.package?.lastPathComponent ?? "none")")
            if let package = release.package {
                Test.expect(Updater.isTrusted(package), "the package link points at GitHub")
            }
        case .failure(let error):
            Test.expect(false, "the request failed: \(error)")
        }
        finished = true
    }

    let deadline = Date().addingTimeInterval(30)
    while !finished && Date() < deadline {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.1))
    }
    Test.expect(finished, "an answer arrived within 30 seconds")
}
