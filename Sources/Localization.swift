import Foundation

/// Thin wrapper over `NSLocalizedString`. The second argument is the English text, and it
/// doubles as the fallback if an `.lproj` is ever missing from the bundle — so a broken
/// build degrades to readable English rather than raw keys.
///
/// `Tools/check-localization.sh` diffs these keys against every `Localizable.strings`,
/// so a forgotten translation fails the build.
func L(_ key: String, _ english: String) -> String {
    NSLocalizedString(key, tableName: nil, bundle: .main, value: english, comment: "")
}
