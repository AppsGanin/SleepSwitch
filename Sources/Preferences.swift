import Foundation

/// Everything the app remembers between launches, behind typed accessors so no raw
/// `UserDefaults` keys are scattered through the code.
enum Preferences {
    private enum Key {
        static let enableAtLaunch = "enableAtLaunch"
        static let autoCheckUpdates = "autoCheckUpdates"
        static let lastUpdateCheck = "lastUpdateCheck"
        static let skippedVersion = "skippedVersion"
    }

    private static let store = UserDefaults.standard

    static func registerDefaults() {
        store.register(defaults: [
            Key.enableAtLaunch: false,
            Key.autoCheckUpdates: true,
        ])
    }

    /// Turn the mode on as soon as the app starts.
    static var enableAtLaunch: Bool {
        get { store.bool(forKey: Key.enableAtLaunch) }
        set { store.set(newValue, forKey: Key.enableAtLaunch) }
    }

    static var autoCheckUpdates: Bool {
        get { store.bool(forKey: Key.autoCheckUpdates) }
        set { store.set(newValue, forKey: Key.autoCheckUpdates) }
    }

    /// Only set after GitHub actually answered — a failed check must not count.
    static var lastUpdateCheck: Date? {
        get { store.object(forKey: Key.lastUpdateCheck) as? Date }
        set { store.set(newValue, forKey: Key.lastUpdateCheck) }
    }

    /// Version the user asked not to be reminded about again.
    static var skippedVersion: String? {
        get { store.string(forKey: Key.skippedVersion) }
        set { store.set(newValue, forKey: Key.skippedVersion) }
    }
}
