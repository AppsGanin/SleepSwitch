import AppKit
import UserNotifications

/// Owns the update story: the daily check, the notification, the dialog and the download.
///
/// The app never replaces itself. It downloads the `.pkg` and hands it to the system
/// Installer, so an upgrade goes through the same authenticated flow as a fresh install.
/// That matters because these builds carry only an ad-hoc signature — there is nothing
/// for the app to verify, so the decision stays with the user and the system.
final class UpdateCoordinator: NSObject, UNUserNotificationCenterDelegate {
    private enum Timing {
        /// Right after login the network is often not up yet.
        static let firstCheckDelay: TimeInterval = 10
        static let pollInterval: TimeInterval = 6 * 3600
        static let minimumGapBetweenChecks: TimeInterval = 24 * 3600
    }

    private enum Notify {
        static let category = "update"
        static let download = "download"
        static let skip = "skip"
    }

    private var timer: Timer?

    func start() {
        registerNotificationCategory()

        DispatchQueue.main.asyncAfter(deadline: .now() + Timing.firstCheckDelay) { [weak self] in
            self?.checkIfDue()
        }
        timer = Timer.scheduledTimer(withTimeInterval: Timing.pollInterval,
                                     repeats: true) { [weak self] _ in
            self?.checkIfDue()
        }
    }

    /// Driven by the menu item: always answers, even when there is nothing new.
    func checkNow() {
        check(automatic: false)
    }

    private func checkIfDue() {
        guard Preferences.autoCheckUpdates else { return }
        if let last = Preferences.lastUpdateCheck,
           Date().timeIntervalSince(last) < Timing.minimumGapBetweenChecks {
            return
        }
        check(automatic: true)
    }

    private func check(automatic: Bool) {
        Updater.fetchLatest { [weak self] result in
            guard let self else { return }

            // Only a real answer counts as a check. Otherwise one attempt without a
            // network would eat a whole day and the update would surface tomorrow.
            if case .success = result {
                Preferences.lastUpdateCheck = Date()
            }

            switch result {
            case .success(let release)
                where Updater.isNewer(release.version, than: Updater.currentVersion):
                self.present(release, automatic: automatic)

            case .success:
                guard !automatic else { return }
                Alerts.show(
                    title: L("update.upToDate.title", "You are up to date"),
                    text: String(format: L("update.upToDate.text",
                                           "SleepSwitch %@ is the latest version."),
                                 Updater.currentVersion),
                    style: .informational
                )

            case .failure(let error):
                guard !automatic else { return }
                Alerts.show(title: L("update.failed.title", "Could not check for updates"),
                            text: self.describe(error), style: .warning)
            }
        }
    }

    private func present(_ release: Updater.Release, automatic: Bool) {
        guard automatic else {
            // The check was asked for by hand, so answer in kind — with a window.
            offer(release)
            return
        }
        guard release.version != Preferences.skippedVersion else { return }
        notify(release)
    }

    // MARK: - Background: a notification rather than a modal

    /// The daily check fires at an arbitrary moment and has no business interrupting
    /// whatever the user is doing.
    private func notify(_ release: Updater.Release) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                // Ask once, the first time there is actually something to say.
                center.requestAuthorization(options: [.alert]) { granted, _ in
                    DispatchQueue.main.async {
                        if granted {
                            self.deliver(release, through: center)
                        } else {
                            self.fallBackToWindow(release)
                        }
                    }
                }
            case .denied:
                DispatchQueue.main.async { self.fallBackToWindow(release) }
            default:
                DispatchQueue.main.async { self.deliver(release, through: center) }
            }
        }
    }

    private func deliver(_ release: Updater.Release, through center: UNUserNotificationCenter) {
        Preferences.announcedVersion = release.version
        center.add(UNNotificationRequest(identifier: "update-\(release.version)",
                                         content: content(for: release),
                                         trigger: nil))
    }

    /// Notifications are off, so a window is the only way to say anything at all — but it
    /// gets one chance per version, not one per day.
    private func fallBackToWindow(_ release: Updater.Release) {
        guard release.version != Preferences.announcedVersion else { return }
        Preferences.announcedVersion = release.version
        offer(release)
    }

    private func content(for release: Updater.Release) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = String(format: L("update.available.title",
                                         "SleepSwitch %@ is available"),
                               release.version)
        content.body = String(format: L("update.available.text",
                                        "You have version %@. Download the installer?"),
                              Updater.currentVersion)
        content.categoryIdentifier = Notify.category
        content.userInfo = [
            "version": release.version,
            "package": release.package?.absoluteString ?? "",
            "page": release.page.absoluteString,
        ]
        return content
    }

    private func registerNotificationCategory() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: Notify.category,
                actions: [
                    UNNotificationAction(identifier: Notify.download,
                                         title: L("update.download", "Download"),
                                         options: [.foreground]),
                    UNNotificationAction(identifier: Notify.skip,
                                         title: L("update.skip", "Skip this version"),
                                         options: []),
                ],
                intentIdentifiers: [],
                options: []
            ),
        ])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let page = (info["page"] as? String).flatMap(URL.init(string:))
        let package = (info["package"] as? String).flatMap(URL.init(string:))

        switch response.actionIdentifier {
        case Notify.skip:
            Preferences.skippedVersion = info["version"] as? String

        case Notify.download:
            if let package {
                startDownload(package)
            } else if let page {
                NSWorkspace.shared.open(page)
            }

        case UNNotificationDefaultActionIdentifier:
            // A click on the notification body opens the release page rather than
            // starting a download nobody asked for.
            if let page { NSWorkspace.shared.open(page) }

        default:
            break
        }
        completionHandler()
    }

    // MARK: - Foreground: the dialog

    private func offer(_ release: Updater.Release) {
        let choice = Alerts.choose(
            title: String(format: L("update.available.title", "SleepSwitch %@ is available"),
                          release.version),
            text: String(format: L("update.available.text",
                                   "You have version %@. Download the installer?"),
                         Updater.currentVersion),
            buttons: [
                L("update.download", "Download"),
                L("update.notes", "Release notes"),
                L("update.skip", "Skip this version"),
                L("update.later", "Later"),
            ]
        )

        switch choice {
        case 0:
            if let package = release.package {
                startDownload(package)
            } else {
                NSWorkspace.shared.open(release.page)
            }
        case 1:
            NSWorkspace.shared.open(release.page)
        case 2:
            Preferences.skippedVersion = release.version
        default:
            break
        }
    }

    private func startDownload(_ url: URL) {
        Updater.download(url) { [weak self] result in
            switch result {
            case .success(let file):
                NSWorkspace.shared.open(file)
            case .failure(let error):
                Alerts.show(
                    title: L("update.downloadFailed.title", "Could not download the update"),
                    text: self?.describe(error) ?? "",
                    style: .warning
                )
            }
        }
    }

    private func describe(_ error: Updater.Failure) -> String {
        switch error {
        case .network(let message):
            return message
        case .malformed:
            return L("update.error.malformed", "GitHub returned an unexpected response.")
        case .noPackage:
            return L("update.error.noPackage", "This release has no installer package.")
        }
    }
}
