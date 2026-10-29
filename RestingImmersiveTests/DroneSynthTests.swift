import Foundation
import Testing
@testable import RestingImmersive

struct DroneSynthTests {
    private func render(_ synth: DroneSynth, frames: Int) -> (left: [Float], right: [Float]) {
        var left = [Float](repeating: .nan, count: frames)
        var right = [Float](repeating: .nan, count: frames)
        left.withUnsafeMutableBufferPointer { l in
            right.withUnsafeMutableBufferPointer { r in
                synth.render(frameCount: frames, left: l.baseAddress, right: r.baseAddress)
            }
        }
        return (left, right)
    }

    @Test func silentUntilGivenAVolume() {
        let synth = DroneSynth(sampleRate: 48_000)
        #expect(synth.isSilent)
        let output = render(synth, frames: 512)
        #expect(output.left.allSatisfy { $0 == 0 })
        #expect(output.right.allSatisfy { $0 == 0 })
    }

    @Test func fadesInGraduallyAndStaysBounded() {
        let synth = DroneSynth(sampleRate: 48_000)
        synth.setTargetGain(1)

        let firstBlock = render(synth, frames: 480)
        #expect(firstBlock.left.allSatisfy { abs($0) < 0.01 }, "No sudden onset")

        let later = render(synth, frames: 48_000 * 4)
        #expect(later.left.allSatisfy { $0.isFinite && abs($0) <= 1 })
        #expect(later.right.allSatisfy { $0.isFinite && abs($0) <= 1 })
        #expect((later.left.map(abs).max() ?? 0) > 0.1, "Audible once faded in")
    }

    @Test func fadesBackToSilence() {
        let synth = DroneSynth(sampleRate: 48_000)
        synth.setTargetGain(1)
        _ = render(synth, frames: 48_000 * 3)
        synth.setTargetGain(0)
        _ = render(synth, frames: 48_000 * 25)
        #expect(synth.isSilent)
        let next = render(synth, frames: 256)
        #expect(next.left.allSatisfy { $0 == 0 })
    }

    @Test func outOfRangeControlValuesAreClamped() {
        let synth = DroneSynth(sampleRate: 48_000)
        synth.setTargetGain(50)
        synth.setBreath(-3)
        let output = render(synth, frames: 48_000 * 4)
        #expect(output.left.allSatisfy { $0.isFinite && abs($0) <= 1 })
    }
}
