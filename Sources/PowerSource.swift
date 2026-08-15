import Foundation
import IOKit.ps

/// The current power source, plus a notification when it changes.
///
/// Unlike the sleep ban, macOS does publish an event for this one
/// (`IOPSNotificationCreateRunLoopSource`), so nothing here needs polling.
final class PowerSource {
    struct State {
        let onBattery: Bool
        /// Absent on a machine with no battery, and on the rare occasion the system
        /// reports a source without a usable capacity. Treated as "do not act".
        let percentage: Int?

        static let unknown = State(onBattery: false, percentage: nil)
    }

    /// Whether this Mac has a built-in battery at all — that is, whether it is a laptop.
    /// Hardware does not change under a running app, so it is read once.
    static let hasInternalBattery = internalBattery() != nil

    static var current: State {
        guard let description = internalBattery(),
              let state = description[kIOPSPowerSourceStateKey] as? String else { return .unknown }

        return State(onBattery: state == kIOPSBatteryPowerValue,
                     percentage: percentage(from: description))
    }

    /// Deliberately matched by type rather than by "the first source there is": a UPS is a
    /// power source too, and on a desktop it would otherwise pass for a battery.
    private static func internalBattery() -> [String: Any]? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?
                .takeUnretainedValue() as? [String: Any] else { continue }
            if description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType {
                return description
            }
        }
        return nil
    }

    private static func percentage(from description: [String: Any]) -> Int? {
        guard let current = description[kIOPSCurrentCapacityKey] as? Int,
              let maximum = description[kIOPSMaxCapacityKey] as? Int,
              maximum > 0 else { return nil }
        return Int((Double(current) / Double(maximum) * 100).rounded())
    }

    // MARK: - Observing

    private var runLoopSource: CFRunLoopSource?
    private var handler: (() -> Void)?

    func startObserving(_ handler: @escaping () -> Void) {
        guard runLoopSource == nil else { return }
        self.handler = handler

        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            Unmanaged<PowerSource>.fromOpaque(context).takeUnretainedValue().handler?()
        }
        let context = Unmanaged.passUnretained(self).toOpaque()

        guard let source = IOPSNotificationCreateRunLoopSource(callback, context)?
            .takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        runLoopSource = source
    }
}
