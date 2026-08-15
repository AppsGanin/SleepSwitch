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

    static var current: State {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return .unknown }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?
                .takeUnretainedValue() as? [String: Any],
                let state = description[kIOPSPowerSourceStateKey] as? String
            else { continue }

            return State(onBattery: state == kIOPSBatteryPowerValue,
                         percentage: percentage(from: description))
        }
        // No power sources at all: a desktop Mac. Never a reason to drop the mode.
        return .unknown
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
