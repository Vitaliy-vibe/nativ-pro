/// 28 режимов наложения образца. Формулы повторяют tools/blendmodel.py,
/// где каждая подтверждена эталонами.
/// Расчёт в гамма-пространстве sRGB: Cb — фон, Cs — слой, значения 0…1.
public enum BlendMode: String, CaseIterable, Sendable, Codable {
    case normal, darken, multiply, colorBurn, linearBurn, darkerColor
    case lighten, screen, colorDodge, linearDodge, lighterColor
    case overlay, softLight, hardLight, vividLight, linearLight, pinLight, hardMix
    case difference, exclusion, subtract, divide
    case hue, saturation, color, luminosity
    case passThrough, behind

    /// Имя в AppleScript-словаре образца (enum «blend mode»).
    public var appleScriptName: String {
        switch self {
        case .colorBurn: return "color burn"
        case .linearBurn: return "linear burn"
        case .darkerColor: return "darker color"
        case .colorDodge: return "color dodge"
        case .linearDodge: return "linear dodge"
        case .lighterColor: return "lighter color"
        case .softLight: return "soft light"
        case .hardLight: return "hard light"
        case .vividLight: return "vivid light"
        case .linearLight: return "linear light"
        case .pinLight: return "pin light"
        case .hardMix: return "hard mix"
        case .hue: return "hue blend mode"
        case .saturation: return "saturation blend mode"
        case .color: return "color blend mode"
        case .passThrough: return "pass through"
        case .behind: return "behind blend mode"
        default: return rawValue
        }
    }

    public init?(appleScriptName: String) {
        guard let mode = BlendMode.allCases.first(where: { $0.appleScriptName == appleScriptName }) else { return nil }
        self = mode
    }

    /// Результат B(Cb, Cs) для одного пикселя. Для `behind` и `passThrough` наложение особое — см. Compositor.
    @inline(__always)
    public func apply(_ b: SIMD3<Float>, _ s: SIMD3<Float>) -> SIMD3<Float> {
        switch self {
        case .normal, .passThrough, .behind: return s
        case .multiply: return b * s
        case .screen: return b + s - b * s
        case .darken: return pointwiseMin(b, s)
        case .lighten: return pointwiseMax(b, s)
        case .colorBurn: return map(b, s, Blend.colorBurn)
        case .colorDodge: return map(b, s, Blend.colorDodge)
        case .linearBurn: return clamp01(b + s - 1)
        case .linearDodge: return clamp01(b + s)
        case .overlay: return map(s, b, Blend.hardLight)
        case .hardLight: return map(b, s, Blend.hardLight)
        case .softLight: return map(b, s, Blend.softLight)
        case .vividLight: return map(b, s, Blend.vividLight)
        case .linearLight: return clamp01(b + 2 * s - 1)
        case .pinLight: return map(b, s, Blend.pinLight)
        case .hardMix: return map(b, s) { b, s in b + s > 1 + 1e-6 ? 1 : 0 }
        case .difference: return abs(b - s)
        case .exclusion: return b + s - 2 * b * s
        case .subtract: return clamp01(b - s)
        case .divide: return map(b, s, Blend.divide)
        case .darkerColor: return Blend.lum(s) < Blend.lum(b) ? s : b
        case .lighterColor: return Blend.lum(s) > Blend.lum(b) ? s : b
        case .hue: return Blend.setLum(Blend.setSat(s, Blend.sat(b)), Blend.lum(b))
        case .saturation: return Blend.setLum(Blend.setSat(b, Blend.sat(s)), Blend.lum(b))
        case .color: return Blend.setLum(s, Blend.lum(b))
        case .luminosity: return Blend.setLum(b, Blend.lum(s))
        }
    }

    @inline(__always)
    private func map(_ b: SIMD3<Float>, _ s: SIMD3<Float>, _ f: (Float, Float) -> Float) -> SIMD3<Float> {
        SIMD3(f(b.x, s.x), f(b.y, s.y), f(b.z, s.z))
    }

    @inline(__always)
    private func clamp01(_ v: SIMD3<Float>) -> SIMD3<Float> {
        v.clamped(lowerBound: SIMD3(repeating: 0), upperBound: SIMD3(repeating: 1))
    }

    @inline(__always)
    private func abs(_ v: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(Swift.abs(v.x), Swift.abs(v.y), Swift.abs(v.z))
    }
}

/// Покомпонентные функции режимов (W3C Compositing and Blending Level 1, веса яркости Rec.601).
enum Blend {
    static let eps: Float = 1e-12
    static let weights = SIMD3<Float>(0.3, 0.59, 0.11)

    static func colorBurn(_ b: Float, _ s: Float) -> Float {
        if b >= 1 { return 1 }
        if s <= 0 { return 0 }
        return 1 - min(1, (1 - b) / s)
    }

    static func colorDodge(_ b: Float, _ s: Float) -> Float {
        if b <= 0 { return 0 }
        if s >= 1 { return 1 }
        return min(1, b / (1 - s))
    }

    static func hardLight(_ b: Float, _ s: Float) -> Float {
        s <= 0.5 ? b * 2 * s : b + (2 * s - 1) - b * (2 * s - 1)
    }

    static func softLight(_ b: Float, _ s: Float) -> Float {
        if s <= 0.5 { return b - (1 - 2 * s) * b * (1 - b) }
        let d = b <= 0.25 ? ((16 * b - 12) * b + 4) * b : b.squareRoot()
        return b + (2 * s - 1) * (d - b)
    }

    static func vividLight(_ b: Float, _ s: Float) -> Float {
        s <= 0.5 ? colorBurn(b, 2 * s) : colorDodge(b, 2 * s - 1)
    }

    static func pinLight(_ b: Float, _ s: Float) -> Float {
        s <= 0.5 ? min(b, 2 * s) : max(b, 2 * s - 1)
    }

    static func divide(_ b: Float, _ s: Float) -> Float {
        if s <= 0 { return b <= 0 ? 0 : 1 }
        return min(max(b / s, 0), 1)
    }

    static func lum(_ c: SIMD3<Float>) -> Float { (c * weights).sum() }

    static func clipColor(_ c: SIMD3<Float>) -> SIMD3<Float> {
        let l = lum(c)
        let n = c.min(), x = c.max()
        var out = c
        if n < 0 { out = SIMD3(repeating: l) + (out - SIMD3(repeating: l)) * l / max(l - n, eps) }
        if x > 1 { out = SIMD3(repeating: l) + (out - SIMD3(repeating: l)) * (1 - l) / max(x - l, eps) }
        return out
    }

    static func setLum(_ c: SIMD3<Float>, _ l: Float) -> SIMD3<Float> {
        clipColor(c + SIMD3(repeating: l - lum(c)))
    }

    static func sat(_ c: SIMD3<Float>) -> Float { c.max() - c.min() }

    static func setSat(_ c: SIMD3<Float>, _ s: Float) -> SIMD3<Float> {
        let mx = c.max(), mn = c.min()
        let range = mx - mn
        guard range > 0 else { return SIMD3(repeating: 0) }
        return (c - SIMD3(repeating: mn)) * s / range
    }
}
