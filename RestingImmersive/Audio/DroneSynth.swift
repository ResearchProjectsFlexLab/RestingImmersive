import CoreAudio
import Foundation
import Synchronization

/// A gentle, generated drone: a stack of pure harmonics of 54 Hz (A = 432 Hz tuning),
/// each with its own slow swell, slightly detuned between ears for a wide, soft beat.
///
/// `render` runs on the real-time audio thread. The main thread only writes the
/// two atomic targets; everything else is owned by the audio thread.
final class DroneSynth: @unchecked Sendable {
    private struct Voice {
        var frequency: Double
        var amplitude: Double
        var swellRate: Double
        /// Upper partials brighten with the breath; the foundation stays steady.
        var followsBreath: Bool
    }

    private static let voices: [Voice] = [
        Voice(frequency: 54, amplitude: 0.10, swellRate: 0.031, followsBreath: false),
        Voice(frequency: 108, amplitude: 0.32, swellRate: 0.047, followsBreath: false),
        Voice(frequency: 162, amplitude: 0.18, swellRate: 0.063, followsBreath: false),
        Voice(frequency: 216, amplitude: 0.12, swellRate: 0.041, followsBreath: false),
        Voice(frequency: 324, amplitude: 0.07, swellRate: 0.083, followsBreath: true),
        Voice(frequency: 432, amplitude: 0.035, swellRate: 0.11, followsBreath: true),
    ]

    private let targetGainBits = Atomic<UInt32>(Float(0).bitPattern)
    private let targetBreathBits = Atomic<UInt32>(Float(0.35).bitPattern)

    private let leftIncrements: [Double]
    private let rightIncrements: [Double]
    private let swellIncrements: [Double]
    private let gainCoefficient: Float
    private let breathCoefficient: Float

    private var leftPhases: [Double]
    private var rightPhases: [Double]
    private var swellPhases: [Double]
    private var gain: Float = 0
    private var breath: Float = 0.35

    init(sampleRate: Double) {
        let sampleRate = max(sampleRate, 8_000)
        let twoPi = 2 * Double.pi
        let voices = Self.voices
        leftIncrements = voices.map { twoPi * $0.frequency / sampleRate }
        rightIncrements = voices.indices.map { twoPi * (voices[$0].frequency + 0.06 * Double($0 + 1)) / sampleRate }
        swellIncrements = voices.map { twoPi * $0.swellRate / sampleRate }
        // Start each swell at a different point so the voices never peak together.
        swellPhases = voices.indices.map { Double($0) * 1.7 }
        leftPhases = Array(repeating: 0, count: voices.count)
        rightPhases = Array(repeating: 0, count: voices.count)
        // About 1.5 s fades, and a 0.4 s glide for the breath so it never steps.
        gainCoefficient = Float(1 - exp(-1 / (sampleRate * 1.5)))
        breathCoefficient = Float(1 - exp(-1 / (sampleRate * 0.4)))
    }

    /// Overall level in `0...1`; the synth glides toward it.
    func setTargetGain(_ value: Float) {
        targetGainBits.store(min(max(value, 0), 1).bitPattern, ordering: .relaxed)
    }

    /// Breath fullness in `0...1`.
    func setBreath(_ value: Float) {
        targetBreathBits.store(min(max(value, 0), 1).bitPattern, ordering: .relaxed)
    }

    var isSilent: Bool {
        gain < 1e-5 && Float(bitPattern: targetGainBits.load(ordering: .relaxed)) == 0
    }

    /// Fills non-interleaved Float32 channels. Must not allocate, lock, or block.
    func render(frameCount: Int, left: UnsafeMutablePointer<Float>?, right: UnsafeMutablePointer<Float>?) {
        if isSilent {
            left?.update(repeating: 0, count: frameCount)
            right?.update(repeating: 0, count: frameCount)
            return
        }
        let targetGain = Float(bitPattern: targetGainBits.load(ordering: .relaxed))
        let targetBreath = Float(bitPattern: targetBreathBits.load(ordering: .relaxed))
        let voices = Self.voices
        let twoPi = 2 * Double.pi

        for frame in 0..<frameCount {
            gain += (targetGain - gain) * gainCoefficient
            breath += (targetBreath - breath) * breathCoefficient

            var leftSample = 0.0
            var rightSample = 0.0
            for index in voices.indices {
                let voice = voices[index]
                var amplitude = voice.amplitude * (0.7 + 0.3 * sin(swellPhases[index]))
                if voice.followsBreath { amplitude *= 0.3 + 0.7 * Double(breath) }
                leftSample += sin(leftPhases[index]) * amplitude
                rightSample += sin(rightPhases[index]) * amplitude

                leftPhases[index] = (leftPhases[index] + leftIncrements[index]).truncatingRemainder(dividingBy: twoPi)
                rightPhases[index] = (rightPhases[index] + rightIncrements[index]).truncatingRemainder(dividingBy: twoPi)
                swellPhases[index] = (swellPhases[index] + swellIncrements[index]).truncatingRemainder(dividingBy: twoPi)
            }
            let level = Double(gain) * (0.85 + 0.15 * Double(breath))
            left?[frame] = Float(leftSample * level)
            right?[frame] = Float(rightSample * level)
        }
    }

    func render(frameCount: Int, into bufferList: UnsafeMutablePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        let left = buffers.count > 0 ? buffers[0].mData?.assumingMemoryBound(to: Float.self) : nil
        let right = buffers.count > 1 ? buffers[1].mData?.assumingMemoryBound(to: Float.self) : nil
        render(frameCount: frameCount, left: left, right: right)
    }
}
