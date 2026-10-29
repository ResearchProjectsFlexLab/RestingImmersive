import RealityKit
import UIKit

/// A layered, procedurally built orb: a bright core inside a glassy luminous shell,
/// wrapped in two camera-facing glow sprites.
@MainActor
final class BreathingOrb {
    let entity = Entity()

    private let body = Entity()
    private let glow = Entity()
    private let innerGlow: ModelEntity
    private let outerHalo: ModelEntity

    /// Uniform scale of the orb body at an empty and a full breath.
    private static let restScale: Float = 0.82
    private static let fullScale: Float = 1.28

    init(glowMask: TextureResource?) {
        entity.name = "BreathingOrb"

        let core = ModelEntity(
            mesh: .generateSphere(radius: 0.07),
            materials: [Self.unlit(Palette.RGB.core, opacity: 1)]
        )

        var shellMaterial = PhysicallyBasedMaterial()
        shellMaterial.baseColor = .init(tint: Palette.uiColor(Palette.RGB.cyan))
        shellMaterial.emissiveColor = .init(color: Palette.uiColor(Palette.RGB.cyan))
        shellMaterial.emissiveIntensity = 0.9
        shellMaterial.roughness = 0.12
        shellMaterial.metallic = 0.0
        shellMaterial.clearcoat = 1.0
        shellMaterial.clearcoatRoughness = 0.05
        shellMaterial.blending = .transparent(opacity: 0.42)
        let shell = ModelEntity(mesh: .generateSphere(radius: 0.14), materials: [shellMaterial])

        let veil = ModelEntity(
            mesh: .generateSphere(radius: 0.175),
            materials: [Self.unlit(Palette.RGB.lavender, opacity: 0.08)]
        )

        body.addChild(core)
        body.addChild(shell)
        body.addChild(veil)
        entity.addChild(body)

        innerGlow = Self.sprite(size: 0.85, tint: Palette.RGB.cyan, opacity: 0.55, mask: glowMask)
        outerHalo = Self.sprite(size: 2.0, tint: Palette.RGB.lavender, opacity: 0.22, mask: glowMask)
        // Slightly behind the orb's center (in billboard space) so the sprites never
        // z-fight with each other or slice through the front of the shell.
        innerGlow.position.z = -0.02
        outerHalo.position.z = -0.04
        glow.addChild(outerHalo)
        glow.addChild(innerGlow)
        glow.components.set(BillboardComponent())
        entity.addChild(glow)

        apply(expansion: 0.35, amplitude: 1)
    }

    /// - Parameters:
    ///   - expansion: Breath fullness in `0...1`.
    ///   - amplitude: Fraction of the full scale range to use (reduced for Reduce Motion).
    func apply(expansion: Float, amplitude: Float) {
        let e = min(max(expansion, 0), 1)
        let midpoint = (Self.restScale + Self.fullScale) / 2
        let scale = midpoint + (Self.restScale + (Self.fullScale - Self.restScale) * e - midpoint) * amplitude
        body.scale = SIMD3(repeating: scale)
        glow.scale = SIMD3(repeating: 0.9 + 0.25 * e * amplitude)

        // Brightness follows the breath even when motion is reduced.
        innerGlow.components.set(OpacityComponent(opacity: 0.55 + 0.4 * e))
        outerHalo.components.set(OpacityComponent(opacity: 0.6 + 0.4 * e))
    }

    private static func unlit(_ rgb: SIMD3<Double>, opacity: Float) -> UnlitMaterial {
        var material = UnlitMaterial(color: Palette.uiColor(rgb))
        if opacity < 1 {
            material.blending = .transparent(opacity: .init(floatLiteral: opacity))
        }
        return material
    }

    private static func sprite(size: Float, tint: SIMD3<Double>, opacity: Float, mask: TextureResource?) -> ModelEntity {
        var material = UnlitMaterial(color: Palette.uiColor(tint))
        material.blending = .transparent(opacity: .init(
            scale: mask == nil ? opacity * 0.2 : opacity,
            texture: mask.map { .init($0) }
        ))
        // A glow is mostly empty space; writing depth would hide the floor behind its quad.
        material.writesDepth = false
        let entity = ModelEntity(mesh: .generatePlane(width: size, height: size), materials: [material])
        return entity
    }
}
