"""Эталонная модель режимов наложения (строка C03 матрицы).

Всё считается в гамма-пространстве sRGB (подтверждено эталоном normal: ΔE p99 0.002).
Композиция с альфой — по W3C Compositing and Blending Level 1:
    Cs' = (1 − αb)·Cs + αb·B(Cb, Cs);   результат = αs·Cs' + (1 − αs)·Cb   (для непрозрачного фона)
Для режимов, где стандарт допускает разные формулы, есть варианты: MODES[имя] = {вариант: функция}.
Функции принимают массивы ...x3 (Cb — фон, Cs — верхний слой) в 0..1.
"""
import numpy as np

EPS = 1e-12


def _clip(x):
    return np.clip(x, 0.0, 1.0)


# --- разделимые режимы -------------------------------------------------------
def normal(b, s):
    return s


def multiply(b, s):
    return b * s


def screen(b, s):
    return b + s - b * s


def darken(b, s):
    return np.minimum(b, s)


def lighten(b, s):
    return np.maximum(b, s)


def color_burn_w3c(b, s):
    return np.where(b >= 1, 1.0, np.where(s <= 0, 0.0, 1 - np.minimum(1, (1 - b) / np.maximum(s, EPS))))


def color_burn_ps(b, s):
    """Как в Photoshop: при b=1 и s=0 результат 0 (а не 1, как в W3C)."""
    return np.where(s <= 0, np.where(b >= 1, 1.0, 0.0), _clip(1 - (1 - b) / np.maximum(s, EPS)))


def color_dodge_w3c(b, s):
    return np.where(b <= 0, 0.0, np.where(s >= 1, 1.0, np.minimum(1, b / np.maximum(1 - s, EPS))))


def color_dodge_ps(b, s):
    return np.where(s >= 1, np.where(b <= 0, 0.0, 1.0), _clip(b / np.maximum(1 - s, EPS)))


def linear_burn(b, s):
    return _clip(b + s - 1)


def linear_dodge(b, s):
    return _clip(b + s)


def overlay(b, s):
    return hard_light(s, b)


def hard_light(b, s):
    return np.where(s <= 0.5, multiply(b, 2 * s), screen(b, 2 * s - 1))


def soft_light_w3c(b, s):
    d = np.where(b <= 0.25, ((16 * b - 12) * b + 4) * b, np.sqrt(b))
    return np.where(s <= 0.5, b - (1 - 2 * s) * b * (1 - b), b + (2 * s - 1) * (d - b))


def soft_light_ps(b, s):
    """Классический Photoshop: корень без кусочной ветки d(b)."""
    return np.where(s <= 0.5, 2 * b * s + b * b * (1 - 2 * s), np.sqrt(b) * (2 * s - 1) + 2 * b * (1 - s))


def soft_light_pegtop(b, s):
    return (1 - 2 * s) * b * b + 2 * s * b


def vivid_light_ps(b, s):
    return np.where(s <= 0.5, color_burn_ps(b, 2 * s), color_dodge_ps(b, 2 * s - 1))


def vivid_light_w3c(b, s):
    return np.where(s <= 0.5, color_burn_w3c(b, 2 * s), color_dodge_w3c(b, 2 * s - 1))


def linear_light(b, s):
    return _clip(b + 2 * s - 1)


def pin_light(b, s):
    return np.where(s <= 0.5, np.minimum(b, 2 * s), np.maximum(b, 2 * s - 1))


def hard_mix_threshold(b, s):
    return np.where(b + s >= 1, 1.0, 0.0)


def hard_mix_strict(b, s):
    """Подтверждено эталоном: на точной границе b + s = 1 результат 0 (порог строгий).
    Допуск 1e-6 — чтобы граница не зависела от ошибок округления при чтении 16-битных значений."""
    return np.where(b + s > 1 + 1e-6, 1.0, 0.0)


def hard_mix_vivid(b, s):
    return np.where(vivid_light_ps(b, s) >= 0.5, 1.0, 0.0)


def difference(b, s):
    return np.abs(b - s)


def exclusion(b, s):
    return b + s - 2 * b * s


def subtract(b, s):
    return _clip(b - s)


def divide(b, s):
    return np.where(s <= 0, np.where(b <= 0, 0.0, 1.0), _clip(b / np.maximum(s, EPS)))


# --- неразделимые режимы (W3C: SetLum / SetSat) -------------------------------
LUM_601 = np.array([0.3, 0.59, 0.11])
LUM_709 = np.array([0.2126, 0.7152, 0.0722])


def _lum(c, w):
    return (c * w).sum(-1, keepdims=True)


def _clip_color(c, w):
    l = _lum(c, w)
    n = c.min(-1, keepdims=True)
    x = c.max(-1, keepdims=True)
    c = np.where(n < 0, l + (c - l) * l / np.maximum(l - n, EPS), c)
    c = np.where(x > 1, l + (c - l) * (1 - l) / np.maximum(x - l, EPS), c)
    return c


def _set_lum(c, l, w):
    return _clip_color(c + (l - _lum(c, w)), w)


def _sat(c):
    return c.max(-1, keepdims=True) - c.min(-1, keepdims=True)


def _set_sat(c, s):
    mx = c.max(-1, keepdims=True)
    mn = c.min(-1, keepdims=True)
    rng = mx - mn
    out = np.where(rng > 0, (c - mn) * s / np.maximum(rng, EPS), 0.0)
    return out


def _nonsep(w):
    return {
        "hue": lambda b, s: _set_lum(_set_sat(s, _sat(b)), _lum(b, w), w),
        "saturation": lambda b, s: _set_lum(_set_sat(b, _sat(s)), _lum(b, w), w),
        "color": lambda b, s: _set_lum(s, _lum(b, w), w),
        "luminosity": lambda b, s: _set_lum(b, _lum(s, w), w),
    }


NS601 = _nonsep(LUM_601)
NS709 = _nonsep(LUM_709)


def _pick_by(metric):
    def f(b, s, pick_lower):
        mb, ms = metric(b), metric(s)
        choose_s = (ms < mb) if pick_lower else (ms > mb)
        return np.where(choose_s, s, b)
    return f


_sum = lambda c: c.sum(-1, keepdims=True)  # noqa: E731
_l601 = lambda c: _lum(c, LUM_601)  # noqa: E731

# Имена — как в AppleScript-словаре (enum «blend mode»).
MODES = {
    "normal": {"std": normal},
    "darken": {"std": darken},
    "multiply": {"std": multiply},
    "color burn": {"w3c": color_burn_w3c, "ps": color_burn_ps},
    "linear burn": {"std": linear_burn},
    "darker color": {"sum": lambda b, s: _pick_by(_sum)(b, s, True), "lum601": lambda b, s: _pick_by(_l601)(b, s, True)},
    "lighten": {"std": lighten},
    "screen": {"std": screen},
    "color dodge": {"w3c": color_dodge_w3c, "ps": color_dodge_ps},
    "linear dodge": {"std": linear_dodge},
    "lighter color": {"sum": lambda b, s: _pick_by(_sum)(b, s, False), "lum601": lambda b, s: _pick_by(_l601)(b, s, False)},
    "overlay": {"std": overlay},
    "soft light": {"w3c": soft_light_w3c, "ps": soft_light_ps, "pegtop": soft_light_pegtop},
    "hard light": {"std": hard_light},
    "vivid light": {"ps": vivid_light_ps, "w3c": vivid_light_w3c},
    "linear light": {"std": linear_light},
    "pin light": {"std": pin_light},
    "hard mix": {"strict": hard_mix_strict, "threshold": hard_mix_threshold, "vivid": hard_mix_vivid},
    "difference": {"std": difference},
    "exclusion": {"std": exclusion},
    "subtract": {"std": subtract},
    "divide": {"std": divide},
    "hue blend mode": {"601": NS601["hue"], "709": NS709["hue"]},
    "saturation blend mode": {"601": NS601["saturation"], "709": NS709["saturation"]},
    "color blend mode": {"601": NS601["color"], "709": NS709["color"]},
    "luminosity": {"601": NS601["luminosity"], "709": NS709["luminosity"]},
    "pass through": {"as-normal": normal},
    "behind blend mode": {"backdrop-wins": lambda b, s: b},
}


def composite(backdrop_rgb, source_rgba, mode_fn, opacity=1.0, alpha_b=1.0):
    """Слой source поверх непрозрачного фона. Возвращает RGB."""
    a_s = source_rgba[..., 3:] * opacity
    cs = source_rgba[..., :3]
    cb = backdrop_rgb
    mixed = (1 - alpha_b) * cs + alpha_b * mode_fn(cb, cs)
    return _clip(a_s * mixed + (1 - a_s) * cb)
