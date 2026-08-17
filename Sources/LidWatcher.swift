import Foundation
import IOKit

/// Watches the lid.
///
/// The clamshell, unlike the sleep ban, does come through the general IOKit interest
/// notification on IOPMrootDomain — confirmed on hardware. Unrelated power messages arrive
/// on the same channel, so the state is re-read and compared rather than trusting a
/// message type: no undocumented constants, and no polling either.
final class LidWatcher {
    /// Whether this Mac has a lid at all. An iMac or a Mac mini simply has no
    /// `AppleClamshellState` to report. Hardware, so it is read once.
    static let hasLid = isClosed != nil

    /// Nil on hardware with no lid at all.
    static var isClosed: Bool? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                  IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        let property = IORegistryEntryCreateCFProperty(service, "AppleClamshellState" as CFString,
                                                       kCFAllocatorDefault, 0)
        guard let raw = property?.takeRetainedValue() else { return nil }
        return (raw as? NSNumber)?.boolValue
    }

    private var notificationPort: IONotificationPortRef?
    private var notifier: io_object_t = 0
    private var lastKnown: Bool?
    private var handler: ((Bool) -> Void)?

    /// Calls back with true when the lid closes and false when it opens.
    func startObserving(_ handler: @escaping (Bool) -> Void) {
        guard Self.hasLid, notificationPort == nil else { return }
        self.handler = handler
        lastKnown = Self.isClosed

        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        IONotificationPortSetDispatchQueue(port, .main)
        notificationPort = port

        let root = IOServiceGetMatchingService(kIOMainPortDefault,
                                               IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return }
        defer { IOObjectRelease(root) }

        let callback: IOServiceInterestCallback = { context, _, _, _ in
            guard let context else { return }
            Unmanaged<LidWatcher>.fromOpaque(context).takeUnretainedValue().stateMayHaveChanged()
        }
        IOServiceAddInterestNotification(port, root, kIOGeneralInterest, callback,
                                         Unmanaged.passUnretained(self).toOpaque(), &notifier)
    }

    private func stateMayHaveChanged() {
        guard let closed = Self.isClosed, closed != lastKnown else { return }
        lastKnown = closed
        handler?(closed)
    }
}
