"""Чтение и запись PNG без сторонних библиотек (только numpy + zlib).

Нужен потому, что Pillow читает 16-битные RGB/RGBA PNG с потерей точности до 8 бит,
а эталоны с Mac экспортируются в 16 бит на канал.
"""
import struct
import zlib

import numpy as np

SIGNATURE = b"\x89PNG\r\n\x1a\n"
CHANNELS = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}


class PngInfo:
    def __init__(self):
        self.width = 0
        self.height = 0
        self.bit_depth = 0
        self.color_type = 0
        self.srgb_intent = None
        self.icc_name = None
        self.icc_profile = None
        self.gamma = None


def _chunk(kind, data):
    body = kind + data
    return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)


def write_png(path, pixels, bit_depth=16, srgb=True):
    """pixels: массив HxW, HxWx1..4 в диапазоне 0..1 (float) или целые значения нужной разрядности."""
    arr = np.asarray(pixels)
    if arr.ndim == 2:
        arr = arr[:, :, None]
    h, w, c = arr.shape
    color_type = {1: 0, 2: 4, 3: 2, 4: 6}[c]
    maxv = (1 << bit_depth) - 1
    if arr.dtype.kind == "f":
        arr = np.clip(np.rint(arr * maxv), 0, maxv)
    dtype = ">u2" if bit_depth == 16 else "u1"
    raw = arr.astype(dtype).reshape(h, w * c)
    rows = np.empty((h, 1 + raw.shape[1] * raw.dtype.itemsize), dtype=np.uint8)
    rows[:, 0] = 0
    rows[:, 1:] = raw.view(np.uint8).reshape(h, -1)
    out = [SIGNATURE, _chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, bit_depth, color_type, 0, 0, 0))]
    if srgb:
        out.append(_chunk(b"sRGB", b"\x00"))
    out.append(_chunk(b"IDAT", zlib.compress(rows.tobytes(), 9)))
    out.append(_chunk(b"IEND", b""))
    with open(path, "wb") as f:
        f.write(b"".join(out))


def _unfilter(data, h, stride, bpp):
    """Снимает построчные фильтры PNG (None/Sub/Up/Average/Paeth)."""
    out = np.zeros((h, stride), dtype=np.uint8)
    prev = np.zeros(stride, dtype=np.int32)
    pos = 0
    for y in range(h):
        ftype = data[pos]
        line = np.frombuffer(data, dtype=np.uint8, count=stride, offset=pos + 1).astype(np.int32)
        pos += 1 + stride
        if ftype == 0:
            cur = line
        elif ftype == 1:
            cur = line.copy()
            lanes = cur[: (stride // bpp) * bpp].reshape(-1, bpp)
            cur[: lanes.size] = (np.cumsum(lanes, axis=0) & 0xFF).reshape(-1)
        elif ftype == 2:
            cur = (line + prev) & 0xFF
        elif ftype in (3, 4):
            cur = line.copy()
            for x in range(0, stride, bpp):
                a = cur[x - bpp:x] if x >= bpp else np.zeros(bpp, dtype=np.int32)
                b = prev[x:x + bpp]
                if ftype == 3:
                    pred = (a + b) >> 1
                else:
                    c = prev[x - bpp:x] if x >= bpp else np.zeros(bpp, dtype=np.int32)
                    p = a + b - c
                    pa, pb, pc = np.abs(p - a), np.abs(p - b), np.abs(p - c)
                    pred = np.where((pa <= pb) & (pa <= pc), a, np.where(pb <= pc, b, c))
                cur[x:x + bpp] = (cur[x:x + bpp] + pred) & 0xFF
        else:
            raise ValueError(f"неизвестный фильтр PNG {ftype} в строке {y}")
        out[y] = cur
        prev = cur
    return out


def read_png(path):
    """Возвращает (float32 HxWx4 RGBA 0..1, PngInfo). Серые изображения разворачиваются в RGB."""
    with open(path, "rb") as f:
        blob = f.read()
    if blob[:8] != SIGNATURE:
        raise ValueError(f"{path}: не PNG")
    info = PngInfo()
    idat = []
    palette = None
    trns = None
    pos = 8
    while pos < len(blob):
        length, kind = struct.unpack(">I4s", blob[pos:pos + 8])
        data = blob[pos + 8:pos + 8 + length]
        pos += 12 + length
        if kind == b"IHDR":
            (info.width, info.height, info.bit_depth, info.color_type,
             _comp, _filt, interlace) = struct.unpack(">IIBBBBB", data)
            if interlace:
                raise ValueError(f"{path}: чересстрочный PNG не поддерживается")
        elif kind == b"IDAT":
            idat.append(data)
        elif kind == b"PLTE":
            palette = np.frombuffer(data, dtype=np.uint8).reshape(-1, 3)
        elif kind == b"tRNS":
            trns = data
        elif kind == b"sRGB":
            info.srgb_intent = data[0]
        elif kind == b"gAMA":
            info.gamma = struct.unpack(">I", data)[0] / 100000.0
        elif kind == b"iCCP":
            name, _, rest = data.partition(b"\x00")
            info.icc_name = name.decode("latin-1")
            info.icc_profile = zlib.decompress(rest[1:])
        elif kind == b"IEND":
            break
    ch = CHANNELS[info.color_type]
    if info.bit_depth not in (8, 16):
        raise ValueError(f"{path}: глубина {info.bit_depth} бит не поддерживается")
    bpp = ch * info.bit_depth // 8
    stride = info.width * bpp
    rows = _unfilter(zlib.decompress(b"".join(idat)), info.height, stride, bpp)
    if info.bit_depth == 16:
        vals = rows.view(">u2").astype(np.float32) / 65535.0
    else:
        vals = rows.astype(np.float32) / 255.0
    vals = vals.reshape(info.height, info.width, ch)
    if info.color_type == 3:
        idx = rows.reshape(info.height, info.width)
        rgb = palette[idx].astype(np.float32) / 255.0
        alpha = np.ones((info.height, info.width, 1), dtype=np.float32)
        if trns is not None:
            ta = np.full(256, 255, dtype=np.uint8)
            ta[: len(trns)] = np.frombuffer(trns, dtype=np.uint8)
            alpha = (ta[idx].astype(np.float32) / 255.0)[:, :, None]
        return np.concatenate([rgb, alpha], axis=2), info
    if ch == 1:
        vals = np.concatenate([vals] * 3 + [np.ones_like(vals)], axis=2)
    elif ch == 2:
        vals = np.concatenate([vals[:, :, :1]] * 3 + [vals[:, :, 1:]], axis=2)
    elif ch == 3:
        vals = np.concatenate([vals, np.ones_like(vals[:, :, :1])], axis=2)
    return vals, info
