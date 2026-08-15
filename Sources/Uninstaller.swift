import Foundation

/// Removes everything the app put on this machine.
///
/// Worth having in the app itself: someone who installed the `.pkg` has no copy of the
/// repository's `uninstall.sh`, and a utility that writes to `/etc/sudoers.d` should be
/// able to clean up after itself.
enum Uninstaller {
    /// Order matters. The sleep ban goes first, while the sudo rule is still in place to
    /// make that quiet — otherwise removing the rule would strand the ban, and the Mac
    /// would stop sleeping with nothing left on screen to explain why.
    static func run() -> Result<Void, SystemSleepBan.Failure> {
        let bundle = Bundle.main.bundleURL.path
        guard !bundle.contains("'") else {
            return .failure(.failed(L("error.badPath",
                                      "The app sits in a folder this cannot handle safely.")))
        }

        let command = "/usr/bin/pmset -a disablesleep 0 && "
            + "/bin/rm -rf '\(bundle)' && "
            + "/bin/rm -f \(SystemSleepBan.sudoersPath) && "
            + "{ /usr/sbin/pkgutil --forget com.ganin.sleepswitch.app; "
            + "/usr/sbin/pkgutil --forget com.ganin.sleepswitch.sudoers; true; } > /dev/null 2>&1"

        return SystemSleepBan.runAsAdministrator(command)
    }

    /// Preferences belong to the user, not to root, so they are cleared separately.
    static func removePreferences() {
        guard let identifier = Bundle.main.bundleIdentifier else { return }
        UserDefaults.standard.removePersistentDomain(forName: identifier)
    }
}
