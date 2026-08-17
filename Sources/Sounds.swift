import AppKit

/// The lid cues, loaded once from the bundle.
///
/// Silence is an acceptable outcome: if the files are missing the app carries on without
/// them rather than treating it as an error worth bothering anyone about.
final class Sounds {
    enum Cue {
        case lidClosed
        case lidOpened
    }

    private let closed = Sounds.load("LidClose")
    private let opened = Sounds.load("LidOpen")

    private static func load(_ name: String) -> NSSound? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else { return nil }
        return NSSound(contentsOf: url, byReference: false)
    }

    func play(_ cue: Cue) {
        let sound = cue == .lidClosed ? closed : opened
        guard let sound else { return }
        // Closing and opening in quick succession would otherwise be ignored: NSSound
        // does nothing when asked to play something already playing.
        if sound.isPlaying { sound.stop() }
        sound.play()
    }
}
