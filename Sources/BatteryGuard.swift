import Foundation

/// Decides whether the mode has to be dropped for the battery's sake.
///
/// The app makes one particular mistake easy: switch the mode on, close the lid, put the
/// Mac in a bag, and it runs hot in there until the battery is flat. This is the guard
/// against that, kept as a pure function so every branch is covered by tests.
enum BatteryGuard {
    enum Verdict: Equatable {
        case keepRunning
        /// The adapter was unplugged and the user asked to stay awake only on power.
        case unplugged
        /// The battery fell to or below the chosen floor.
        case lowBattery(Int)
    }

    /// Thresholds offered in the menu. Zero means the floor is switched off.
    static let offeredFloors = [0, 10, 20, 30]

    static func verdict(for state: PowerSource.State,
                        onlyOnPower: Bool,
                        floor: Int) -> Verdict {
        guard state.onBattery else { return .keepRunning }

        if onlyOnPower { return .unplugged }

        // No floor set, or no reading to trust: leave the user's choice alone. Acting on
        // a missing percentage would mean switching the mode off for no stated reason.
        guard floor > 0, let percentage = state.percentage else { return .keepRunning }

        return percentage <= floor ? .lowBattery(percentage) : .keepRunning
    }
}
