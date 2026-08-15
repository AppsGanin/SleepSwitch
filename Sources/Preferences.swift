import Foundation

/// Everything the app remembers between launches, behind typed accessors so no raw
/// `UserDefaults` keys are scattered through the code.
enum Preferences {
    private enum Key {
        static let enableAtLaunch = "enableAtLaunch"
        static let autoCheckUpdates = "autoCheckUpdates"
        static let lastUpdateCheck = "lastUpdateCheck"
        static let skippedVersion = "skippedVersion"
        static let announcedVersion = "announcedVersion"
        static let batteryFloor = "batteryFloor"
        static let onlyOnPower = "onlyOnPower"
    }

    private static let store = UserDefaults.standard

    static func registerDefaults() {
        store.register(defaults: [
            Key.enableAtLaunch: false,
            Key.autoCheckUpdates: true,
            // On by default: the failure this guards against — a Mac cooking in a closed
            // bag until the battery is flat — is worse than an unexpected switch off.
            Key.batteryFloor: 20,
            Key.onlyOnPower: false,
        ])
    }

    /// Battery percentage at which the mode switches itself off. Zero disables the floor.
    static var batteryFloor: Int {
        get { store.integer(forKey: Key.batteryFloor) }
        set { store.set(newValue, forKey: Key.batteryFloor) }
    }

    /// Drop the mode as soon as the power adapter is unplugged.
    static var onlyOnPower: Bool {
        get { store.bool(forKey: Key.onlyOnPower) }
        set { store.set(newValue, forKey: Key.onlyOnPower) }
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

    /// Last version already brought to the user's attention. Notifications can be denied,
    /// and the fallback is a window — which must not reappear every single day.
    static var announcedVersion: String? {
        get { store.string(forKey: Key.announcedVersion) }
        set { store.set(newValue, forKey: Key.announcedVersion) }
    }
}
