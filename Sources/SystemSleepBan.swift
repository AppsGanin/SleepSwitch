import Foundation
import IOKit

/// The privileged half behind a protocol, so the state machine that drives it can be
/// exercised in tests without touching real power settings.
protocol SleepBanControlling {
    var isActive: Bool { get }
    func set(_ on: Bool, allowPrompt: Bool) -> Result<Void, SystemSleepBan.Failure>
    func clearQuietly()
}

/// Production implementation: forwards straight to `SystemSleepBan`.
struct SystemSleepBanControl: SleepBanControlling {
    var isActive: Bool { SystemSleepBan.isActive }

    func set(_ on: Bool, allowPrompt: Bool) -> Result<Void, SystemSleepBan.Failure> {
        SystemSleepBan.set(on, allowPrompt: allowPrompt)
    }

    func clearQuietly() {
        SystemSleepBan.clearQuietly()
    }
}

/// The privileged half: `pmset -a disablesleep`, the setting that governs what happens
/// when the lid closes.
///
/// Unlike the IOKit assertions this one is system-wide and outlives the process, which is
/// why the app is careful to clear it on the way out.
enum SystemSleepBan {
    static let pmsetPath = "/usr/bin/pmset"
    static let sudoersPath = "/etc/sudoers.d/sleepswitch"

    enum Failure: Error {
        /// The user dismissed the password dialog, or it was suppressed on purpose.
        case cancelled
        case failed(String)
    }

    /// Read straight from IOPMrootDomain — no `sudo`, no shelling out.
    static var isActive: Bool {
        let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                  IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }

        let property = IORegistryEntryCreateCFProperty(service, "SleepDisabled" as CFString,
                                                       kCFAllocatorDefault, 0)
        guard let raw = property?.takeRetainedValue() else { return false }
        return (raw as? NSNumber)?.boolValue ?? false
    }

    /// True when the sudo rule is in place and `pmset` can be driven without a password.
    static var hasPasswordlessRule: Bool {
        FileManager.default.fileExists(atPath: sudoersPath)
    }

    /// Tries the passwordless path first, then falls back to the system administrator
    /// dialog. Pass `allowPrompt: false` to skip that fallback — turning the mode on at
    /// launch must not turn into a password prompt at every login.
    static func set(_ on: Bool, allowPrompt: Bool = true) -> Result<Void, Failure> {
        let value = on ? "1" : "0"
        if runSilently("/usr/bin/sudo", ["-n", pmsetPath, "-a", "disablesleep", value]) {
            return .success(())
        }
        guard allowPrompt else { return .failure(.cancelled) }
        return runAsAdministrator("\(pmsetPath) -a disablesleep \(value)")
    }

    /// Best-effort clear on the way out: never shows a dialog.
    static func clearQuietly() {
        _ = runSilently("/usr/bin/sudo", ["-n", pmsetPath, "-a", "disablesleep", "0"])
    }

    // MARK: - The sudo rule

    /// Installs a rule allowing exactly two `pmset` invocations and nothing else.
    ///
    /// The file is written, validated by `visudo` and installed entirely as root inside a
    /// mode-0700 temporary directory. No user-writable file takes part, which matters:
    /// anything the user could write could also be swapped between the check and the
    /// install, turning this into a way to put arbitrary content into sudoers.
    static func installPasswordlessRule() -> Result<Void, Failure> {
        let user = NSUserName()
        guard isSafeUserName(user) else {
            let format = L("error.badUserName", "Unsupported account name: “%@”.")
            return .failure(.failed(String(format: format, user)))
        }

        // Comments stay English: this is a system file, read by whoever audits the machine.
        let lines = [
            "# Installed by SleepSwitch. Allows toggling the sleep ban without a password.",
            "# Remove with: sudo rm \(sudoersPath)",
            "\(user) ALL=(root) NOPASSWD: \(pmsetPath) -a disablesleep 0",
            "\(user) ALL=(root) NOPASSWD: \(pmsetPath) -a disablesleep 1",
        ]
        guard lines.allSatisfy({ !$0.contains("'") }) else {
            return .failure(.failed(L("error.ruleBuild", "Could not build the rule safely.")))
        }

        let quoted = lines.map { "'\($0)'" }.joined(separator: " ")
        let command = "d=$(/usr/bin/mktemp -d) && "
            + "/usr/bin/printf '%s\\n' \(quoted) > \"$d/sleepswitch\" && "
            + "/usr/sbin/visudo -cf \"$d/sleepswitch\" && "
            + "/usr/bin/install -m 0440 -o root -g wheel \"$d/sleepswitch\" \(sudoersPath); "
            + "r=$?; /bin/rm -rf \"$d\"; exit $r"
        return runAsAdministrator(command)
    }

    static func removePasswordlessRule() -> Result<Void, Failure> {
        runAsAdministrator("/bin/rm -f \(sudoersPath)")
    }

    /// The account name lands in sudoers and in a shell command, so only the characters
    /// macOS itself permits in a short name are allowed through.
    private static func isSafeUserName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 63, name.first != "-" else { return false }
        return name.allSatisfy { character in
            character.isASCII
                && (character.isLetter || character.isNumber || "._-".contains(character))
        }
    }

    // MARK: - Running things

    private static func runSilently(_ launchPath: String, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        do { try process.run() } catch { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    /// The stock macOS administrator dialog. The password is typed into a system window;
    /// the app never sees it.
    private static func runAsAdministrator(_ shellCommand: String) -> Result<Void, Failure> {
        // Order matters: backslashes first, or the escaping eats itself.
        let escaped = shellCommand
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        let source = "do shell script \"\(escaped)\" with administrator privileges"

        guard let script = NSAppleScript(source: source) else {
            return .failure(.failed(L("error.scriptBuild", "Could not build the privilege request.")))
        }

        var errorInfo: NSDictionary?
        script.executeAndReturnError(&errorInfo)
        guard let errorInfo else { return .success(()) }

        // -128 is the user pressing Cancel in the password dialog.
        if errorInfo[NSAppleScript.errorNumber] as? Int == -128 {
            return .failure(.cancelled)
        }
        let message = errorInfo[NSAppleScript.errorMessage] as? String
            ?? L("error.unknown", "Unknown error.")
        return .failure(.failed(message))
    }
}
