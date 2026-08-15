import Foundation

// Tests for Sources/Updater.swift, compiled together with it:
//   ./Tools/run-tests.sh [--network]
// Without --network only the pure functions run — that is what CI executes, so a GitHub
// outage or a rate limit can never turn the build red.

var failures = 0

func expect(_ condition: Bool, _ description: String) {
    if condition {
        print("  ok    \(description)")
    } else {
        print("  FAIL  \(description)")
        failures += 1
    }
}

print("Version comparison")
expect(Updater.isNewer("1.0.1", than: "1.0.0"), "1.0.1 is newer than 1.0.0")
expect(Updater.isNewer("1.10.0", than: "1.9.3"), "1.10.0 beats 1.9.3 — not a string compare")
expect(Updater.isNewer("2.0", than: "1.99.99"), "2.0 is newer than 1.99.99")
expect(Updater.isNewer("1.1", than: "1.0.9"), "uneven lengths: 1.1 is newer than 1.0.9")
expect(!Updater.isNewer("1.0.0", than: "1.0.0"), "equal versions are not newer")
expect(!Updater.isNewer("1.0.0", than: "1.0.1"), "an older version is not newer")
expect(!Updater.isNewer("1.0", than: "1.0.0"), "1.0 is not newer than 1.0.0")
expect(!Updater.isNewer("garbage", than: "1.0.0"), "garbage does not pass as a new version")

print("Download source filter")
expect(Updater.isTrusted(URL(string: "https://github.com/AppsGanin/SleepSwitch/x.pkg")!),
       "github.com is allowed")
expect(Updater.isTrusted(URL(string: "https://objects.githubusercontent.com/a/b.pkg")!),
       "objects.githubusercontent.com is allowed")
expect(!Updater.isTrusted(URL(string: "http://github.com/a.pkg")!),
       "plain http is refused")
expect(!Updater.isTrusted(URL(string: "https://evil.com/a.pkg")!),
       "an unrelated host is refused")
expect(!Updater.isTrusted(URL(string: "https://github.com.evil.com/a.pkg")!),
       "the look-alike host github.com.evil.com is refused")
expect(!Updater.isTrusted(URL(string: "file:///tmp/a.pkg")!),
       "a local file is refused")

if CommandLine.arguments.contains("--network") {
    print("Live request to GitHub")
    var finished = false

    Updater.fetchLatest { result in
        switch result {
        case .success(let release):
            expect(!release.version.isEmpty, "version parsed: \(release.version)")
            expect(release.version.first?.isNumber == true, "the leading “v” is stripped")
            expect(release.package != nil,
                   "the release carries a .pkg: \(release.package?.lastPathComponent ?? "none")")
            if let package = release.package {
                expect(Updater.isTrusted(package), "the package link points at GitHub")
            }
        case .failure(let error):
            expect(false, "the request failed: \(error)")
        }
        finished = true
    }

    let deadline = Date().addingTimeInterval(30)
    while !finished && Date() < deadline {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.1))
    }
    expect(finished, "an answer arrived within 30 seconds")
}

print(failures == 0 ? "\nAll checks passed." : "\nFailures: \(failures)")
exit(failures == 0 ? 0 : 1)
