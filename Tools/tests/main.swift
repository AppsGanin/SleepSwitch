import Foundation

runSleepModeTests()
runUpdaterTests()

if CommandLine.arguments.contains("--network") {
    runUpdaterNetworkTests()
}

Test.finish()
