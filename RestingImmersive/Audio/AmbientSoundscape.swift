import AVFAudio

/// Plays the generated drone while a session is underway. Fades in and out
/// rather than cutting, and stops the audio engine once it has gone quiet.
@MainActor
final class AmbientSoundscape {
    /// Master level at full volume. The drone is meant to sit well beneath awareness.
    private static let level: Float = 0.22
    private static let fadeOutDuration: Duration = .seconds(3)

    private let engine = AVAudioEngine()
    private var synth: DroneSynth?
    private var stopTask: Task<Void, Never>?

    func setPlaying(_ playing: Bool) {
        if playing { play() } else { fadeOut() }
    }

    func setBreath(_ expansion: Float) {
        synth?.setBreath(expansion)
    }

    private func play() {
        stopTask?.cancel()
        stopTask = nil
        let synth = prepareIfNeeded()
        if !engine.isRunning {
            do {
                // Starting the engine activates the session; activating it explicitly
                // on the main thread risks a hang.
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
                try engine.start()
            } catch {
                // Sound is a nicety; the session continues silently if audio is unavailable.
                return
            }
        }
        synth.setTargetGain(Self.level)
    }

    private func fadeOut() {
        guard let synth, stopTask == nil else { return }
        synth.setTargetGain(0)
        guard engine.isRunning else { return }
        // Holds `self` strongly so the fade can finish even after the space has closed.
        stopTask = Task {
            try? await Task.sleep(for: Self.fadeOutDuration)
            guard !Task.isCancelled else { return }
            engine.stop()
            stopTask = nil
        }
    }

    private func prepareIfNeeded() -> DroneSynth {
        if let synth { return synth }
        let outputRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let sampleRate = outputRate > 0 ? outputRate : 48_000
        let synth = DroneSynth(sampleRate: sampleRate)
        if let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) {
            let node = Self.makeSourceNode(format: format, synth: synth)
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
        }
        self.synth = synth
        return synth
    }

    /// Built outside the main actor so the render block carries no actor isolation;
    /// it is called on the real-time audio thread.
    private nonisolated static func makeSourceNode(format: AVAudioFormat, synth: DroneSynth) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { _, _, frameCount, bufferList in
            synth.render(frameCount: Int(frameCount), into: bufferList)
            return noErr
        }
    }
}
