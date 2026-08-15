import Foundation
import IOKit
import IOKit.pwr_mgt

/// Holds the IOKit assertions that block idle sleep and keep the display lit.
///
/// This is the safe half of the app: assertions belong to the process, so they disappear
/// the moment it dies. Nothing can get stuck the way a system setting can.
final class PowerAssertions {
    private var systemAssertion: IOPMAssertionID = 0
    private var displayAssertion: IOPMAssertionID = 0

    private(set) var holdsSystem = false
    private(set) var holdsDisplay = false

    /// Sleep and display go together. A separate "keep the screen on" switch only
    /// confused people: its effect showed up tens of minutes later, once the idle
    /// timer expired, so toggling it looked like it did nothing.
    func apply(active: Bool) {
        setSystem(active)
        setDisplay(active)
    }

    func releaseAll() {
        apply(active: false)
    }

    private func setSystem(_ wanted: Bool) {
        guard wanted != holdsSystem else { return }
        if wanted {
            // Assertion names stay ASCII: `pmset -g assertions` prints them verbatim.
            guard let id = create(kIOPMAssertionTypePreventUserIdleSystemSleep,
                                  reason: "SleepSwitch: no idle sleep") else { return }
            systemAssertion = id
            holdsSystem = true
        } else {
            IOPMAssertionRelease(systemAssertion)
            systemAssertion = 0
            holdsSystem = false
        }
    }

    private func setDisplay(_ wanted: Bool) {
        guard wanted != holdsDisplay else { return }
        if wanted {
            guard let id = create(kIOPMAssertionTypePreventUserIdleDisplaySleep,
                                  reason: "SleepSwitch: no display sleep") else { return }
            displayAssertion = id
            holdsDisplay = true
        } else {
            IOPMAssertionRelease(displayAssertion)
            displayAssertion = 0
            holdsDisplay = false
        }
    }

    private func create(_ type: String, reason: String) -> IOPMAssertionID? {
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            type as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &id
        )
        return result == kIOReturnSuccess ? id : nil
    }
}
