import Foundation

runSleepModeTests()
runBatteryGuardTests()
runUpdaterTests()

if CommandLine.arguments.contains("--network") {
    runUpdaterNetworkTests()
}

Test.finish()
