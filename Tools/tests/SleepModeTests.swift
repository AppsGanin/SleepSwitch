import Foundation

/// Covers the awkward paths: a declined password, a ban somebody else set, and the
/// difference between "the user turned the mode off" and "we are deliberately partial".
func runSleepModeTests() {
    Test.section("SleepMode: switching on")

    do {
        let ban = FakeSleepBan()
        let mode = SleepMode(ban: ban)

        let outcome = mode.set(true)
        Test.expect(isApplied(outcome), "a working privileged half reports .applied")
        Test.expect(mode.isOn && mode.isFullyOn, "the mode is fully on")
        Test.expect(ban.setCalls.map(\.on) == [true], "the ban was asked to switch on once")
    }

    do {
        let ban = FakeSleepBan()
        ban.response = .failure(.cancelled)
        let mode = SleepMode(ban: ban)

        let outcome = mode.set(true)
        Test.expect(isPartial(outcome), "a declined password reports .partial")
        Test.expect(mode.isOn, "the mode still counts as on — idle sleep is blocked")
        Test.expect(!mode.isFullyOn, "but not fully: the lid will still sleep")
    }

    Test.section("SleepMode: switching off")

    do {
        let ban = FakeSleepBan()
        let mode = SleepMode(ban: ban)
        mode.set(true)

        ban.response = .failure(.cancelled)
        mode.set(false)
        Test.expect(mode.isOn, "declining the password on the way out keeps the mode shown as on")
        Test.expect(ban.isActive, "because the system ban really is still standing")
    }

    do {
        let ban = FakeSleepBan()
        let mode = SleepMode(ban: ban)
        mode.set(true)
        mode.set(false)
        Test.expect(!mode.isOn && !ban.isActive, "an ordinary switch off clears both halves")
    }

    Test.section("SleepMode: who owns the ban")

    do {
        let ban = FakeSleepBan()
        let mode = SleepMode(ban: ban)
        mode.set(true)

        mode.relinquish(mayAskPassword: true)
        Test.expect(ban.quietClears == 1, "a ban we set is cleared on the way out")
        Test.expect(!ban.isActive, "and it really is gone")
    }

    do {
        // The ban was already there at launch — somebody else's to clear, not ours.
        let ban = FakeSleepBan()
        ban.isActive = true
        let mode = SleepMode(ban: ban)
        mode.adoptSystemState()

        Test.expect(mode.isOn, "an existing ban is adopted honestly at startup")
        mode.relinquish(mayAskPassword: true)
        Test.expect(ban.quietClears == 0, "a ban we did not set is left alone")
        Test.expect(ban.isActive, "so it survives our exit")
    }

    do {
        // No sudo rule: the quiet clear does nothing, so quitting has to ask.
        let ban = FakeSleepBan()
        let mode = SleepMode(ban: ban)
        mode.set(true)
        ban.quietClearWorks = false

        mode.relinquish(mayAskPassword: true)
        Test.expect(ban.setCalls.contains { !$0.on && $0.allowPrompt },
                    "when the quiet path fails, quitting falls back to asking")
    }

    do {
        let ban = FakeSleepBan()
        let mode = SleepMode(ban: ban)
        mode.set(true)
        ban.quietClearWorks = false

        // Logging out: a modal password dialog would block the shutdown.
        mode.relinquish(mayAskPassword: false)
        Test.expect(!ban.setCalls.contains { !$0.on && $0.allowPrompt },
                    "during logout it never asks for a password")
    }

    Test.section("SleepMode: picking up outside changes")

    do {
        let ban = FakeSleepBan()
        let mode = SleepMode(ban: ban)

        ban.isActive = true // as if somebody ran pmset in a terminal
        Test.expect(mode.syncWithSystem(), "an outside ban moves the state")
        Test.expect(mode.isOn, "and the mode shows as on")
    }

    do {
        let ban = FakeSleepBan()
        ban.response = .failure(.cancelled)
        let mode = SleepMode(ban: ban)
        mode.set(true) // partial: our assertions stand, the ban does not

        Test.expect(!mode.syncWithSystem(), "partial mode is not mistaken for being switched off")
        Test.expect(mode.isOn, "the mode stays on")
    }

    Test.section("SleepMode: turning on at launch")

    do {
        let ban = FakeSleepBan()
        let mode = SleepMode(ban: ban)

        mode.set(true, askForPassword: false)
        Test.expect(ban.setCalls.map(\.allowPrompt) == [false],
                    "at launch the password prompt is suppressed, not merely unlikely")
    }
}

private func isApplied(_ outcome: SleepMode.Outcome) -> Bool {
    if case .applied = outcome { return true }
    return false
}

private func isPartial(_ outcome: SleepMode.Outcome) -> Bool {
    if case .partial = outcome { return true }
    return false
}
