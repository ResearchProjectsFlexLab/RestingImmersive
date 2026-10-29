import SwiftUI
import UIKit

/// Shared colors so the window, the spatial controls, and the RealityKit scene stay cohesive.
enum Palette {
    static let midnight = Color(red: 0.03, green: 0.05, blue: 0.14)
    static let cyan = Color(red: 0.42, green: 0.86, blue: 0.95)
    static let lavender = Color(red: 0.72, green: 0.64, blue: 0.98)

    enum RGB {
        static let skyZenith = SIMD3<Double>(0.010, 0.016, 0.060)
        static let skyHorizon = SIMD3<Double>(0.090, 0.090, 0.230)
        static let horizonGlow = SIMD3<Double>(0.300, 0.250, 0.520)
        static let skyNadir = SIMD3<Double>(0.006, 0.010, 0.035)
        static let floor = SIMD3<Double>(0.030, 0.045, 0.110)
        static let cyan = SIMD3<Double>(0.420, 0.860, 0.950)
        static let lavender = SIMD3<Double>(0.720, 0.640, 0.980)
        static let core = SIMD3<Double>(0.880, 0.980, 1.000)
    }

    static func uiColor(_ rgb: SIMD3<Double>, alpha: Double = 1) -> UIColor {
        UIColor(red: rgb.x, green: rgb.y, blue: rgb.z, alpha: alpha)
    }
}
