import RealityKit
import SwiftUI
import UIKit

/// Builds the sanctuary and drives its per-frame motion from the session's clock.
@MainActor
final class SanctuaryScene {
    /// Where the orb floats: a little below standing eye height, comfortable when seated.
    static let orbPosition = SIMD3<Float>(0, 1.3, -1.7)
    static let instructionPosition = orbPosition + SIMD3(0, 0.4, 0.05)
    /// Below the orb, about 20° under a standing user's level gaze.
    static let controlsPosition = SIMD3<Float>(0, 1.02, -1.25)

    let root = Entity()
    /// Follows the orb's breath so the sound and the light swell together.
    weak var soundscape: AmbientSoundscape?
    private(set) var orb: BreathingOrb?
    private var motes: Entity?

    private var displayedExpansion: Float = 0.35
    private var displayedAmplitude: Float = 1
    private var sceneOpacity: Float = 0
    private var reduceMotion = false
    private var updateSubscription: EventSubscription?

    /// Expansion the orb settles to when it isn't following a breath.
    private static let restingExpansion: Float = 0.35

    func build() async {
        root.name = "Sanctuary"
        root.components.set(OpacityComponent(opacity: 0))

        let skyImage = ProceduralTextures.sky()
        let glowMask = await Self.texture(ProceduralTextures.radialGlowMask(), semantic: .raw)
        let floorTexture = await Self.texture(ProceduralTextures.floor())
        let floorMask = await Self.texture(ProceduralTextures.floorMask(), semantic: .raw)

        if let skyImage, let skyTexture = await Self.texture(skyImage) {
            root.addChild(Self.makeSkyDome(texture: skyTexture))
        }
        root.addChild(Self.makeFloor(texture: floorTexture, mask: floorMask))
        root.addChild(Self.makeLightPool(mask: glowMask))
        root.addChild(Self.makeMist(mask: glowMask))

        let motes = Self.makeMotes()
        self.motes = motes
        root.addChild(motes)

        let orb = BreathingOrb(glowMask: glowMask)
        orb.entity.position = Self.orbPosition
        self.orb = orb
        root.addChild(orb.entity)

        if let skyImage {
            await applyImageBasedLighting(from: skyImage, to: orb.entity)
        }
        applyReduceMotion()
    }

    func startUpdating(in content: RealityViewContent, session: MeditationSession) {
        updateSubscription?.cancel()
        updateSubscription = content.subscribe(to: SceneEvents.Update.self) { [weak self, weak session] (event: SceneEvents.Update) in
            guard let session else { return }
            let deltaTime = Float(event.deltaTime)
            MainActor.assumeIsolated {
                self?.update(deltaTime: deltaTime, session: session)
            }
        }
    }

    func stopUpdating() {
        updateSubscription?.cancel()
        updateSubscription = nil
    }

    func setReduceMotion(_ enabled: Bool) {
        guard enabled != reduceMotion else { return }
        reduceMotion = enabled
        applyReduceMotion()
    }

    // MARK: - Per-frame update

    private func update(deltaTime: Float, session: MeditationSession) {
        guard let orb else { return }
        let dt = min(max(deltaTime, 0), 0.1)

        if sceneOpacity < 1 {
            sceneOpacity = min(1, sceneOpacity + dt / 1.6)
            root.components.set(OpacityComponent(opacity: Self.smoothstep(sceneOpacity)))
        }

        // The breath itself is already eased; smoothing only softens transitions such as
        // guidance turning off or the session ending.
        let target = session.breathingExpansion().map(Float.init) ?? Self.restingExpansion
        let targetAmplitude: Float = reduceMotion ? 0.3 : 1
        let response = 1 - exp(-dt * 8)
        let newExpansion = displayedExpansion + (target - displayedExpansion) * response
        let newAmplitude = displayedAmplitude + (targetAmplitude - displayedAmplitude) * response

        if abs(newExpansion - displayedExpansion) > 0.0001 || abs(newAmplitude - displayedAmplitude) > 0.0001 {
            displayedExpansion = newExpansion
            displayedAmplitude = newAmplitude
            orb.apply(expansion: displayedExpansion, amplitude: displayedAmplitude)
            soundscape?.setBreath(displayedExpansion)
        }
    }

    // MARK: - Construction

    private static func makeSkyDome(texture: TextureResource) -> Entity {
        var material = UnlitMaterial(texture: texture)
        material.faceCulling = .front
        let dome = ModelEntity(mesh: .generateSphere(radius: 60), materials: [material])
        dome.name = "Sky"
        return dome
    }

    private static func makeFloor(texture: TextureResource?, mask: TextureResource?) -> Entity {
        let radius: Float = 14
        var material = UnlitMaterial(color: Palette.uiColor(Palette.RGB.floor))
        if let texture {
            material.color = .init(tint: .white, texture: .init(texture))
        }
        if let mask {
            material.blending = .transparent(opacity: .init(scale: 1, texture: .init(mask)))
        }
        let floor = ModelEntity(
            mesh: .generatePlane(width: radius * 2, depth: radius * 2, cornerRadius: radius),
            materials: [material]
        )
        floor.name = "Floor"
        return floor
    }

    /// A soft pool of light on the floor beneath the orb.
    private static func makeLightPool(mask: TextureResource?) -> Entity {
        let pool = Entity()
        guard let mask else { return pool }
        var material = UnlitMaterial(color: Palette.uiColor(Palette.RGB.cyan))
        material.blending = .transparent(opacity: .init(scale: 0.16, texture: .init(mask)))
        material.writesDepth = false
        let disc = ModelEntity(mesh: .generatePlane(width: 2.6, depth: 2.6), materials: [material])
        disc.name = "LightPool"
        disc.position = SIMD3(orbPosition.x, 0.004, orbPosition.z)
        return disc
    }

    /// Large, faint, camera-facing veils near the horizon that suggest distant atmosphere.
    private static func makeMist(mask: TextureResource?) -> Entity {
        let mist = Entity()
        mist.name = "Mist"
        guard let mask else { return mist }

        var random = SeededRandom(seed: 42)
        let count = 14
        for index in 0..<count {
            let angle = (Float(index) / Float(count)) * 2 * .pi + Float(random.next()) * 0.3
            let distance = 16 + Float(random.next()) * 14
            let size = 10 + Float(random.next()) * 10
            let tint = index.isMultiple(of: 2) ? Palette.RGB.lavender : Palette.RGB.cyan

            var material = UnlitMaterial(color: Palette.uiColor(tint))
            material.blending = .transparent(opacity: .init(scale: 0.05 + Float(random.next()) * 0.05, texture: .init(mask)))
            material.writesDepth = false
            let veil = ModelEntity(mesh: .generatePlane(width: size * 1.8, height: size), materials: [material])
            veil.position = SIMD3(sin(angle) * distance, 1.2 + Float(random.next()) * 2.5, -cos(angle) * distance)
            veil.components.set(BillboardComponent())
            mist.addChild(veil)
        }
        return mist
    }

    /// Slow, sparse motes of light drifting around the user.
    private static func makeMotes() -> Entity {
        var emitter = ParticleEmitterComponent()
        emitter.emitterShape = .box
        emitter.emitterShapeSize = SIMD3(7, 2.6, 7)
        emitter.birthLocation = .volume
        emitter.birthDirection = .world
        emitter.emissionDirection = SIMD3(0, 1, 0)
        emitter.speed = 0.012
        emitter.speedVariation = 0.008

        var particles = emitter.mainEmitter
        particles.birthRate = 14
        particles.birthRateVariation = 4
        particles.lifeSpan = 12
        particles.lifeSpanVariation = 3
        particles.size = 0.007
        particles.sizeVariation = 0.003
        particles.opacityCurve = .gradualFadeInOut
        particles.blendMode = .additive
        particles.isLightingEnabled = false
        particles.color = .evolving(
            start: .single(Palette.uiColor(Palette.RGB.cyan, alpha: 0.85)),
            end: .single(Palette.uiColor(Palette.RGB.lavender, alpha: 0.6))
        )
        particles.noiseStrength = 0.004
        particles.noiseScale = 0.6
        particles.noiseAnimationSpeed = 0.05
        emitter.mainEmitter = particles

        let motes = Entity()
        motes.name = "Motes"
        motes.position = SIMD3(0, 1.5, -1)
        motes.components.set(emitter)
        return motes
    }

    private func applyReduceMotion() {
        guard let motes, var emitter = motes.components[ParticleEmitterComponent.self] else { return }
        emitter.speed = reduceMotion ? 0.003 : 0.012
        emitter.mainEmitter.birthRate = reduceMotion ? 6 : 14
        emitter.mainEmitter.noiseStrength = reduceMotion ? 0 : 0.004
        motes.components.set(emitter)
    }

    private func applyImageBasedLighting(from image: CGImage, to receiver: Entity) async {
        guard let environment = try? await EnvironmentResource(equirectangular: image) else { return }
        let light = Entity()
        light.name = "SkyLight"
        light.components.set(ImageBasedLightComponent(source: .single(environment), intensityExponent: 1.2))
        root.addChild(light)
        Self.setLightReceiver(light, on: receiver)
    }

    private static func setLightReceiver(_ light: Entity, on entity: Entity) {
        entity.components.set(ImageBasedLightReceiverComponent(imageBasedLight: light))
        for child in entity.children {
            setLightReceiver(light, on: child)
        }
    }

    private static func texture(_ image: CGImage?, semantic: TextureResource.Semantic = .color) async -> TextureResource? {
        guard let image else { return nil }
        return try? await TextureResource(image: image, options: .init(semantic: semantic))
    }

    private static func smoothstep(_ t: Float) -> Float {
        let t = min(max(t, 0), 1)
        return t * t * (3 - 2 * t)
    }
}
