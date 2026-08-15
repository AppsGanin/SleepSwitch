import Foundation

/// The mode itself: IOKit assertions plus the system-wide sleep ban.
///
/// Deliberately free of AppKit. It reports what happened and leaves the caller to decide
/// how to show it, which keeps the two-layer logic readable and testable on its own.
final class SleepMode {
    /// What actually happened when the mode was switched.
    enum Outcome {
        /// Both layers followed: the assertions and the system ban.
        case applied
        /// Assertions only. The privileged half wanted a password that was declined or
        /// suppressed, so idle sleep is blocked but the lid still puts the Mac to sleep.
        case partial
        case failed(String)
    }

    private let assertions = PowerAssertions()

    /// The system ban was switched on by us, so we owe its removal. A ban that was
    /// already there when we launched is somebody else's to clear.
    private var banIsOurs = false

    private(set) var isOn = false

    /// The system ban is on as well, not just our assertions.
    var isFullyOn: Bool { isOn && SystemSleepBan.isActive }

    /// Adopts whatever the system reports at startup — including a ban left behind by a
    /// crash, which is better shown honestly than silently ignored.
    func adoptSystemState() {
        isOn = SystemSleepBan.isActive
        assertions.apply(active: isOn)
    }

    @discardableResult
    func set(_ wanted: Bool, askForPassword: Bool = true) -> Outcome {
        isOn = wanted
        assertions.apply(active: wanted)

        var outcome = Outcome.applied
        switch SystemSleepBan.set(wanted, allowPrompt: askForPassword) {
        case .success:
            banIsOurs = wanted
        case .failure(.cancelled):
            outcome = .partial
        case .failure(.failed(let message)):
            outcome = .failed(message)
        }

        // Switching off did not go through and the system ban is still standing, so the
        // mode is not really off. Show that immediately rather than at the next sync.
        if !wanted && SystemSleepBan.isActive {
            isOn = true
            assertions.apply(active: true)
        }
        return outcome
    }

    /// Picks up changes made behind the app's back — a terminal, another utility.
    /// Returns true when the state actually moved.
    @discardableResult
    func syncWithSystem() -> Bool {
        let banned = SystemSleepBan.isActive

        if !isOn && banned {
            isOn = true
            assertions.apply(active: true)
            return true
        }
        // Our own assertions still standing means we are deliberately in partial mode,
        // not that somebody turned the mode off.
        if isOn && !banned && !assertions.holdsSystem {
            isOn = false
            return true
        }
        return false
    }

    /// Releases everything the app holds.
    ///
    /// `mayAskPassword` is false during logout, where a modal password dialog would block
    /// the shutdown; it is true on an ordinary quit, where leaving the ban behind would
    /// strand the Mac permanently awake with no switch on screen.
    func relinquish(mayAskPassword: Bool) {
        assertions.releaseAll()
        guard banIsOurs else { return }
        banIsOurs = false

        SystemSleepBan.clearQuietly()
        if mayAskPassword && SystemSleepBan.isActive {
            _ = SystemSleepBan.set(false)
        }
    }
}
