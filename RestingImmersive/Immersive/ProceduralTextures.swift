import CoreGraphics
import Foundation

/// Small, deterministic Core Graphics images used to texture the sanctuary.
/// Generating them at launch keeps the app free of downloaded or bundled assets.
enum ProceduralTextures {
    /// Equirectangular sky: deep midnight at the poles, a soft lavender band at the
    /// horizon, and a sparse field of faint stars. The gradient is symmetric so the
    /// result is correct regardless of the sphere's UV orientation.
    static func sky(width: Int = 2048, height: Int = 1024) -> CGImage? {
        guard let context = makeContext(width: width, height: height) else { return nil }
        let palette = Palette.RGB.self

        let colors = [
            cgColor(palette.skyNadir),
            cgColor(palette.skyHorizon),
            cgColor(palette.horizonGlow),
            cgColor(palette.skyHorizon),
            cgColor(palette.skyZenith),
        ] as CFArray
        let locations: [CGFloat] = [0.0, 0.44, 0.5, 0.56, 1.0]
        if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) {
            context.drawLinearGradient(
                gradient,
                start: .zero,
                end: CGPoint(x: 0, y: height),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }

        var random = SeededRandom(seed: 0x5EED_CAFE)
        for _ in 0..<900 {
            let y = random.next() * Double(height)
            let latitude = abs(y / Double(height) - 0.5) * 2 // 0 at horizon, 1 at poles
            guard latitude > 0.12 else { continue }
            let x = random.next() * Double(width)
            // Equirectangular images stretch near the poles; widen stars there to compensate.
            let stretch = 1 / max(0.15, cos(latitude * .pi / 2))
            let radius = 0.6 + random.next() * 1.1
            let alpha = 0.15 + random.next() * 0.45
            let tint = random.next() < 0.5 ? palette.cyan : palette.lavender
            let color = mix(SIMD3(1, 1, 1), tint, 0.4)
            context.setFillColor(cgColor(color, alpha: alpha))
            context.fillEllipse(in: CGRect(
                x: x - radius * stretch, y: y - radius,
                width: radius * 2 * stretch, height: radius * 2
            ))
        }
        return context.makeImage()
    }

    /// A soft circular falloff, white at the center and black at the rim.
    /// RealityKit reads opacity textures as a single scalar channel rather than
    /// from color alpha, so this is an opaque grayscale mask, not a transparent image.
    /// `falloff` above 1 concentrates the light toward the center.
    static func radialGlowMask(size: Int = 256, falloff: Double = 1.6) -> CGImage? {
        let steps = 16
        let stops = (0...steps).map { index in
            let t = Double(index) / Double(steps)
            return (location: t, value: pow(1 - t, falloff) * (0.5 + 0.5 * cos(.pi * t)))
        }
        return radialMask(size: size, stops: stops)
    }

    /// Opacity for the floor disc: solid near the user, fading to nothing at the rim
    /// so the floor melts into the sky without a visible edge.
    static func floorMask(size: Int = 512) -> CGImage? {
        radialMask(size: size, stops: [(0, 1), (0.35, 0.96), (0.75, 0.6), (1, 0)])
    }

    /// Floor color: dark navy that deepens toward the rim, with a faint cyan ring
    /// for a sense of place.
    static func floor(size: Int = 1024) -> CGImage? {
        guard let context = makeContext(width: size, height: size) else { return nil }
        let palette = Palette.RGB.self
        let center = CGPoint(x: size / 2, y: size / 2)
        let radius = CGFloat(size) / 2

        let base = [
            cgColor(palette.floor),
            cgColor(palette.floor),
            cgColor(palette.skyNadir),
            cgColor(palette.skyNadir),
        ] as CFArray
        if let gradient = CGGradient(colorsSpace: colorSpace, colors: base, locations: [0, 0.35, 0.75, 1]) {
            context.drawRadialGradient(
                gradient, startCenter: center, startRadius: 0,
                endCenter: center, endRadius: radius, options: []
            )
        }

        let ring = [
            cgColor(palette.cyan, alpha: 0),
            cgColor(palette.cyan, alpha: 0.10),
            cgColor(palette.lavender, alpha: 0.05),
            cgColor(palette.cyan, alpha: 0),
        ] as CFArray
        if let gradient = CGGradient(colorsSpace: colorSpace, colors: ring, locations: [0.12, 0.155, 0.17, 0.21]) {
            context.drawRadialGradient(
                gradient, startCenter: center, startRadius: 0,
                endCenter: center, endRadius: radius, options: []
            )
        }
        return context.makeImage()
    }

    // MARK: - Helpers

    private static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    private static func makeContext(width: Int, height: Int) -> CGContext? {
        CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    private static let grayColorSpace = CGColorSpaceCreateDeviceGray()

    private static func radialMask(size: Int, stops: [(location: Double, value: Double)]) -> CGImage? {
        guard let context = CGContext(
            data: nil, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: 0, space: grayColorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))

        let colors = stops.map { CGColor(gray: $0.value, alpha: 1) } as CFArray
        let locations = stops.map { CGFloat($0.location) }
        guard let gradient = CGGradient(colorsSpace: grayColorSpace, colors: colors, locations: locations) else {
            return nil
        }
        let center = CGPoint(x: size / 2, y: size / 2)
        context.drawRadialGradient(
            gradient,
            startCenter: center, startRadius: 0,
            endCenter: center, endRadius: CGFloat(size) / 2,
            options: []
        )
        return context.makeImage()
    }

    private static func cgColor(_ rgb: SIMD3<Double>, alpha: Double = 1) -> CGColor {
        CGColor(colorSpace: colorSpace, components: [rgb.x, rgb.y, rgb.z, alpha])
            ?? CGColor(red: rgb.x, green: rgb.y, blue: rgb.z, alpha: alpha)
    }

    private static func mix(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ t: Double) -> SIMD3<Double> {
        a + (b - a) * t
    }
}

/// Tiny deterministic generator so the star field is identical on every launch.
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed }

    /// Uniform value in `0..<1`.
    mutating func next() -> Double {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return Double(state >> 11) / Double(1 << 53)
    }
}
