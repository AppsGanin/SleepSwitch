import Foundation

// The two lid cues, synthesised rather than sampled: no licence question and no binary
// asset in the repository, the same reasoning as the icon.
//
//   swift make-sounds.swift <output directory>
//
// Porcelain, muted: two partials and nothing underneath. An earlier attempt staged a whole
// scene — cup, drop, gurgle — and read as foley rather than as a cue. Lower on closing,
// higher on opening, so the direction alone says which happened.

let sampleRate = 44_100.0
let duration = 0.26

/// Applied after normalisation. Before it, normalisation would simply undo it.
let outputLevel = 0.5

func porcelain(opening: Bool) -> [Double] {
    let frameCount = Int(sampleRate * duration)
    let partials: [(frequency: Double, decay: Double, level: Double)] = opening
        ? [(3_060, 42, 1.0), (4_580, 55, 0.4)]
        : [(2_180, 34, 1.0), (3_290, 46, 0.45)]

    var samples = [Double](repeating: 0, count: frameCount)
    for index in 0 ..< frameCount {
        let t = Double(index) / sampleRate
        var value = 0.0
        for partial in partials {
            value += sin(2 * .pi * partial.frequency * t) * exp(-t * partial.decay) * partial.level
        }
        // A couple of milliseconds of attack, or the onset clicks.
        samples[index] = value * min(t / 0.002, 1)
    }
    return samples
}

/// Normalise to full scale, apply the level, then top and tail so it neither clips nor clicks.
func finish(_ samples: [Double]) -> [Double] {
    var samples = samples
    let peak = samples.map(abs).max() ?? 1
    if peak > 0 {
        for index in samples.indices {
            samples[index] = samples[index] / (peak * 1.05) * outputLevel
        }
    }
    let edge = Int(0.003 * sampleRate)
    for index in 0 ..< min(edge, samples.count / 2) {
        let gain = Double(index) / Double(edge)
        samples[index] *= gain
        samples[samples.count - 1 - index] *= gain
    }
    return samples
}

/// 16-bit mono WAV. No framework needed to lay out 44 bytes of header.
func wav(_ samples: [Double]) -> Data {
    var data = Data()
    func append<T: FixedWidthInteger>(_ value: T) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }

    let payloadBytes = UInt32(samples.count * 2)
    data.append(contentsOf: Array("RIFF".utf8))
    append(UInt32(36) + payloadBytes)
    data.append(contentsOf: Array("WAVEfmt ".utf8))
    append(UInt32(16))                   // chunk size
    append(UInt16(1))                    // PCM
    append(UInt16(1))                    // mono
    append(UInt32(sampleRate))
    append(UInt32(sampleRate) * 2)       // byte rate
    append(UInt16(2))                    // block align
    append(UInt16(16))                   // bits per sample
    data.append(contentsOf: Array("data".utf8))
    append(payloadBytes)
    for sample in samples {
        append(Int16(max(-1, min(1, sample)) * 32_767))
    }
    return data
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("one argument required: the output directory\n".utf8))
    exit(2)
}
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

try wav(finish(porcelain(opening: false)))
    .write(to: directory.appendingPathComponent("LidClose.wav"))
try wav(finish(porcelain(opening: true)))
    .write(to: directory.appendingPathComponent("LidOpen.wav"))
print("sounds written to \(directory.path)")
