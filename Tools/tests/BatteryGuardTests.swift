import Foundation

func runBatteryGuardTests() {
    Test.section("BatteryGuard: nothing to do")

    Test.expect(verdict(onBattery: false, percentage: 5, floor: 20) == .keepRunning,
                "on the adapter the charge is irrelevant")
    Test.expect(verdict(onBattery: true, percentage: 90, floor: 20) == .keepRunning,
                "on battery but well above the floor")
    Test.expect(verdict(onBattery: true, percentage: 21, floor: 20) == .keepRunning,
                "one point above the floor is still above it")
    Test.expect(verdict(onBattery: false, percentage: nil, floor: 20) == .keepRunning,
                "a desktop Mac reports no battery and is left alone")

    Test.section("BatteryGuard: the floor")

    Test.expect(verdict(onBattery: true, percentage: 20, floor: 20) == .lowBattery(20),
                "reaching the floor exactly trips it")
    Test.expect(verdict(onBattery: true, percentage: 3, floor: 20) == .lowBattery(3),
                "well below the floor trips it")
    Test.expect(verdict(onBattery: true, percentage: 5, floor: 0) == .keepRunning,
                "floor 0 means the guard is switched off")
    Test.expect(verdict(onBattery: true, percentage: nil, floor: 20) == .keepRunning,
                "no reading means no action — the mode is not dropped for an unstated reason")

    Test.section("BatteryGuard: only on power")

    Test.expect(verdict(onBattery: true, percentage: 100, floor: 0, onlyOnPower: true) == .unplugged,
                "unplugging trips it even at a full charge")
    Test.expect(verdict(onBattery: false, percentage: 100, floor: 0, onlyOnPower: true) == .keepRunning,
                "plugged in, it stays out of the way")
    Test.expect(verdict(onBattery: true, percentage: 5, floor: 20, onlyOnPower: true) == .unplugged,
                "unplugging is reported ahead of the floor — it is the more precise reason")
}

private func verdict(onBattery: Bool,
                     percentage: Int?,
                     floor: Int,
                     onlyOnPower: Bool = false) -> BatteryGuard.Verdict {
    BatteryGuard.verdict(for: PowerSource.State(onBattery: onBattery, percentage: percentage),
                         onlyOnPower: onlyOnPower,
                         floor: floor)
}
