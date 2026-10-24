#!/usr/bin/env python3
"""Детерминированно строит тестовые изображения для эталонов (sRGB, PNG).

Запуск: python3 tools/make_inputs.py   → tools/inputs/*.png
Изображения целиком наши: собраны из формул, без чужих фото.
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pngio import write_png  # noqa: E402

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "inputs")


def hsv_to_rgb(h, s, v):
    h = (np.asarray(h, dtype=np.float64) % 1.0) * 6
    i = np.floor(h).astype(int) % 6
    f = h - np.floor(h)
    p, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
    choices = [(v, t, p), (q, v, p), (p, v, t), (p, q, v), (t, p, v), (v, p, q)]
    rgb = np.zeros(np.shape(h) + (3,))
    for k, (r, g, b) in enumerate(choices):
        m = i == k
        rgb[m, 0] = np.broadcast_to(r, np.shape(h))[m]
        rgb[m, 1] = np.broadcast_to(g, np.shape(h))[m]
        rgb[m, 2] = np.broadcast_to(b, np.shape(h))[m]
    return rgb


def grid(n):
    y, x = np.mgrid[0:n, 0:n].astype(np.float64)
    return x, y


def base_a():
    """Нижний слой для режимов наложения, 256×256, непрозрачный.
    Зоны: (0..127, 0..127) серая шкала по x; (128..255, 0..127) насыщенный тон по x;
    нижняя половина — гладкий «фотоподобный» узор."""
    x, y = grid(256)
    img = np.zeros((256, 256, 3))
    top, left = y < 128, x < 128
    g = x / 127
    img[top & left] = np.stack([g, g, g], -1)[top & left]
    img[top & ~left] = hsv_to_rgb((x - 128) / 128, 1.0, 1.0)[top & ~left]
    bottom = ~top
    photo = np.stack([0.5 + 0.5 * np.sin(x / 9), 0.5 + 0.5 * np.sin(y / 13 + 1),
                      0.5 + 0.5 * np.sin((x + y) / 17 + 2)], -1)
    img[bottom] = photo[bottom]
    return img


def top_b():
    """Верхний слой, 256×256, RGBA.
    (0..127, 0..127) серая шкала по y — вместе с base_a даёт таблицу «серый × серый»;
    (128..255, 0..127) тон по y (s=0.6, v=0.8) — таблица «цвет × цвет»;
    нижняя половина — другой узор; в строках 192..255 альфа растёт по x от 0 до 1."""
    x, y = grid(256)
    rgb = np.zeros((256, 256, 3))
    top, left = y < 128, x < 128
    g = y / 127
    rgb[top & left] = np.stack([g, g, g], -1)[top & left]
    rgb[top & ~left] = hsv_to_rgb(y / 128, 0.6, 0.8)[top & ~left]
    bottom = ~top
    photo = np.stack([0.5 + 0.5 * np.cos(y / 7), 0.5 + 0.5 * np.cos(x / 11 + 2),
                      0.5 + 0.5 * np.cos((x - y) / 15 + 1)], -1)
    rgb[bottom] = photo[bottom]
    alpha = np.ones((256, 256, 1))
    ramp = y >= 192
    alpha[ramp, 0] = x[ramp] / 255
    return np.concatenate([rgb, alpha], -1)


def photo_c():
    """512×512 для коррекций и эффектов.
    Левая половина: таблица 8 тонов × 8 светлот (по 32×64 px) при насыщенности 0.85;
    правая верхняя: 16 ступеней серого; правая средняя: плавный градиент;
    правая нижняя: мелкая текстура и резкие края."""
    x, y = grid(512)
    img = np.zeros((512, 512, 3))
    left = x < 256
    hue = np.floor(x / 32) / 8
    light = 0.15 + 0.8 * np.floor(y / 64) / 7
    img[left] = hsv_to_rgb(hue, 0.85, light)[left]
    r1 = (~left) & (y < 128)
    step = np.floor((x - 256) / 16) / 15
    img[r1] = np.stack([step] * 3, -1)[r1]
    r2 = (~left) & (y >= 128) & (y < 320)
    grad = np.stack([(x - 256) / 255, (y - 128) / 191, 1 - (x - 256) / 255], -1)
    img[r2] = grad[r2]
    r3 = (~left) & (y >= 320)
    tex = 0.5 + 0.25 * np.sin(x * 1.3) * np.sin(y * 1.7) + 0.2 * ((np.floor(x / 24) + np.floor(y / 24)) % 2 - 0.5)
    img[r3] = np.stack([tex, tex * 0.9, tex * 0.8], -1)[r3]
    return np.clip(img, 0, 1)


def mask_grad():
    """Маска 256×256: вертикальный градиент чёрный→белый, оттенки серого."""
    _, y = grid(256)
    return y / 255


def trim_transparent():
    """256×256 RGBA: прозрачная рамка 24 px вокруг цветного прямоугольника."""
    img = np.zeros((256, 256, 4))
    img[24:232, 40:216, :3] = [0.2, 0.4, 0.8]
    img[24:232, 40:216, 3] = 1
    return img


def trim_color():
    """256×256 RGB: рамка цвета (0.9, 0.3, 0.1) вокруг серого прямоугольника."""
    img = np.zeros((256, 256, 3))
    img[:, :] = [0.9, 0.3, 0.1]
    img[30:220, 50:200] = [0.5, 0.5, 0.5]
    return img


def solid(n, rgb):
    img = np.zeros((n, n, 3))
    img[:, :] = rgb
    return img


IMAGES = {
    "base_a.png": (base_a, 16),
    "top_b.png": (top_b, 16),
    "photo_c.png": (photo_c, 16),
    "mask_grad.png": (mask_grad, 16),
    "trim_transparent.png": (trim_transparent, 16),
    "trim_color.png": (trim_color, 16),
    "white256.png": (lambda: solid(256, [1, 1, 1]), 8),
    "white64.png": (lambda: solid(64, [1, 1, 1]), 8),
    "red16.png": (lambda: solid(16, [1, 0, 0]), 8),
}


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, (fn, depth) in IMAGES.items():
        write_png(os.path.join(OUT, name), fn(), bit_depth=depth)
        print("записан", name)


if __name__ == "__main__":
    main()
