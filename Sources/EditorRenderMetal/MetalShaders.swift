#if canImport(Metal)
/// Шейдеры рендера на GPU. Формулы — те же, что в EditorCore/BlendMode.swift и CPURenderer.swift
/// (подтверждены эталонами образца). Компилируются при запуске из исходника: так пакет собирается `swift build`
/// без Xcode-проекта. Математика — без «быстрых» приближений (mathMode = .safe).
let metalShaderSource = #"""
#include <metal_stdlib>
using namespace metal;

// Порядок режимов совпадает с BlendMode.allCases; префикс m — чтобы имена не совпадали с функциями metal::.
enum Mode : int {
    mNormal = 0, mDarken, mMultiply, mColorBurn, mLinearBurn, mDarkerColor, mLighten, mScreen, mColorDodge, mLinearDodge, mLighterColor, mOverlay, mSoftLight, mHardLight, mVividLight, mLinearLight, mPinLight, mHardMix, mDifference, mExclusion, mSubtract, mDivide, mHue, mSaturation, mColor, mLuminosity, mPassThrough, mBehind
};

constant float3 W = float3(0.3f, 0.59f, 0.11f);
constant float EPS = 1e-12f;

float colorBurnF(float b, float s) { if (b >= 1) return 1; if (s <= 0) return 0; return 1 - min(1.0f, (1 - b) / s); }
float colorDodgeF(float b, float s) { if (b <= 0) return 0; if (s >= 1) return 1; return min(1.0f, b / (1 - s)); }
float hardLightF(float b, float s) { return s <= 0.5f ? b * 2 * s : b + (2 * s - 1) - b * (2 * s - 1); }
float softLightF(float b, float s) {
    if (s <= 0.5f) return b - (1 - 2 * s) * b * (1 - b);
    float d = b <= 0.25f ? ((16 * b - 12) * b + 4) * b : sqrt(b);
    return b + (2 * s - 1) * (d - b);
}
float vividLightF(float b, float s) { return s <= 0.5f ? colorBurnF(b, 2 * s) : colorDodgeF(b, 2 * s - 1); }
float pinLightF(float b, float s) { return s <= 0.5f ? min(b, 2 * s) : max(b, 2 * s - 1); }
float divideF(float b, float s) { if (s <= 0) return b <= 0 ? 0 : 1; return clamp(b / s, 0.0f, 1.0f); }

float lum(float3 c) { return dot(c, W); }
float3 clipColor(float3 c) {
    float l = lum(c), n = min(c.x, min(c.y, c.z)), x = max(c.x, max(c.y, c.z));
    float3 o = c;
    if (n < 0) o = l + (o - l) * l / max(l - n, EPS);
    if (x > 1) o = l + (o - l) * (1 - l) / max(x - l, EPS);
    return o;
}
float3 setLum(float3 c, float l) { return clipColor(c + (l - lum(c))); }
float sat(float3 c) { return max(c.x, max(c.y, c.z)) - min(c.x, min(c.y, c.z)); }
float3 setSat(float3 c, float s) {
    float mx = max(c.x, max(c.y, c.z)), mn = min(c.x, min(c.y, c.z)), r = mx - mn;
    return r > 0 ? (c - mn) * s / r : float3(0);
}

#define MAP(f) float3(f(b.x, s.x), f(b.y, s.y), f(b.z, s.z))

float3 blendColor(int mode, float3 b, float3 s) {
    switch (mode) {
        case mMultiply: return b * s;
        case mScreen: return b + s - b * s;
        case mDarken: return min(b, s);
        case mLighten: return max(b, s);
        case mColorBurn: return MAP(colorBurnF);
        case mColorDodge: return MAP(colorDodgeF);
        case mLinearBurn: return clamp(b + s - 1, 0.0f, 1.0f);
        case mLinearDodge: return clamp(b + s, 0.0f, 1.0f);
        case mOverlay: return float3(hardLightF(s.x, b.x), hardLightF(s.y, b.y), hardLightF(s.z, b.z));
        case mHardLight: return MAP(hardLightF);
        case mSoftLight: return MAP(softLightF);
        case mVividLight: return MAP(vividLightF);
        case mLinearLight: return clamp(b + 2 * s - 1, 0.0f, 1.0f);
        case mPinLight: return MAP(pinLightF);
        case mHardMix: return select(float3(0), float3(1), b + s > 1 + 1e-6f);
        case mDifference: return abs(b - s);
        case mExclusion: return b + s - 2 * b * s;
        case mSubtract: return clamp(b - s, 0.0f, 1.0f);
        case mDivide: return MAP(divideF);
        case mDarkerColor: return lum(s) < lum(b) ? s : b;
        case mLighterColor: return lum(s) > lum(b) ? s : b;
        case mHue: return setLum(setSat(s, sat(b)), lum(b));
        case mSaturation: return setLum(setSat(b, sat(s)), lum(b));
        case mColor: return setLum(s, lum(b));
        case mLuminosity: return setLum(b, lum(s));
        default: return s;   // normal, passThrough, behind
    }
}

bool inside(int2 p, uint w, uint h) { return p.x >= 0 && p.y >= 0 && p.x < int(w) && p.y < int(h); }

kernel void fill_r(texture2d<float, access::write> t [[texture(0)]],
                   constant float &value [[buffer(0)]],
                   uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= t.get_width() || gid.y >= t.get_height()) return;
    t.write(float4(value), gid);
}

struct MaskParams { int2 offset; int hasBitmap; float background; float density; int inverted; };

// coverage *= значение маски (с плотностью и инверсией); вне растра маски — background.
kernel void mul_mask(texture2d<float, access::read_write> cov [[texture(0)]],
                     texture2d<float, access::read> mask [[texture(1)]],
                     constant MaskParams &p [[buffer(0)]],
                     uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= cov.get_width() || gid.y >= cov.get_height()) return;
    float m = p.background;
    int2 l = int2(gid) - p.offset;
    if (p.hasBitmap != 0 && inside(l, mask.get_width(), mask.get_height())) m = mask.read(uint2(l)).r;
    m = 1 - p.density * (1 - m);
    if (p.inverted != 0) m = 1 - m;
    cov.write(float4(cov.read(gid).r * m), gid);
}

// coverage *= альфа источника в точке документа (для основания обтравки).
kernel void mul_alpha(texture2d<float, access::read_write> cov [[texture(0)]],
                      texture2d<float, access::read> src [[texture(1)]],
                      constant int2 &origin [[buffer(0)]],
                      uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= cov.get_width() || gid.y >= cov.get_height()) return;
    int2 l = int2(gid) - origin;
    float a = inside(l, src.get_width(), src.get_height()) ? src.read(uint2(l)).a : 0;
    cov.write(float4(cov.read(gid).r * a), gid);
}

// coverage *= другое покрытие (основание обтравки).
kernel void mul_cov(texture2d<float, access::read_write> cov [[texture(0)]],
                    texture2d<float, access::read> other [[texture(1)]],
                    uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= cov.get_width() || gid.y >= cov.get_height()) return;
    cov.write(float4(cov.read(gid).r * other.read(gid).r), gid);
}

struct ExtentParams { int2 origin; int2 size; float background; };

// Значения маски в области: внутри растра маски — 0 (пустые плитки), снаружи — фон маски.
// Непустые плитки затем вписываются put_r.
kernel void mask_init(texture2d<float, access::write> t [[texture(0)]],
                      constant ExtentParams &p [[buffer(0)]],
                      uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= t.get_width() || gid.y >= t.get_height()) return;
    int2 q = int2(gid) - p.origin;
    bool isIn = q.x >= 0 && q.y >= 0 && q.x < p.size.x && q.y < p.size.y;
    t.write(float4(isIn ? 0.0f : p.background), gid);
}

struct PutParams { int2 origin; int channel; };

// Вписать канал плитки (0 — значение маски, 3 — альфа) в текстуру области со смещением origin.
kernel void put_r(texture2d<float, access::write> dst [[texture(0)]],
                  texture2d<float, access::read> src [[texture(1)]],
                  constant PutParams &p [[buffer(0)]],
                  uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= src.get_width() || gid.y >= src.get_height()) return;
    int2 d = int2(gid) + p.origin;
    if (!inside(d, dst.get_width(), dst.get_height())) return;
    float4 v = src.read(gid);
    dst.write(float4(p.channel == 3 ? v.a : v.r), uint2(d));
}

struct ValueParams { float density; int inverted; };

// coverage *= значение маски с плотностью и инверсией.
kernel void mul_value(texture2d<float, access::read_write> cov [[texture(0)]],
                      texture2d<float, access::read> val [[texture(1)]],
                      constant ValueParams &p [[buffer(0)]],
                      uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= cov.get_width() || gid.y >= cov.get_height()) return;
    float m = val.read(gid).r;
    m = 1 - p.density * (1 - m);
    if (p.inverted != 0) m = 1 - m;
    cov.write(float4(cov.read(gid).r * m), gid);
}

struct CompParams { int2 origin; int mode; float opacity; };

// Наложение слоя на холст (W3C Compositing Level 1, гамма-пространство sRGB, без премультипликации на холсте).
kernel void composite(texture2d<float, access::read_write> canvas [[texture(0)]],
                      texture2d<float, access::read> src [[texture(1)]],
                      texture2d<float, access::read> cov [[texture(2)]],
                      constant CompParams &p [[buffer(0)]],
                      uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= src.get_width() || gid.y >= src.get_height()) return;
    int2 d = int2(gid) + p.origin;
    if (!inside(d, canvas.get_width(), canvas.get_height())) return;
    float4 s = src.read(gid);
    float as = s.a * p.opacity;
    if (as <= 0) return;
    as *= cov.read(uint2(d)).r;
    if (as <= 0) return;
    float4 bk = canvas.read(uint2(d));
    float3 cb = bk.rgb, cs = s.rgb;
    float ab = bk.a;
    float3 co;
    if (p.mode == mBehind) {
        co = ab * cb + (1 - ab) * as * cs;
    } else {
        float3 mixed = (1 - ab) * cs + ab * blendColor(p.mode, cb, cs);
        co = as * mixed + (1 - as) * ab * cb;
    }
    float ao = as + ab * (1 - as);
    float3 c = ao > 0 ? co / ao : float3(0);
    canvas.write(float4(clamp(c, 0.0f, 1.0f), min(ao, 1.0f)), uint2(d));
}
"""#
#endif
