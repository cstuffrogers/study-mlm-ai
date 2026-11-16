"""把人物像统一处理成「红底 + 白人物 + 白色描边圈」的红白图。

红色取自 frontend/pic/1.jpg 的主色（纯红底），描边圈模仿 1.jpg 的白圈。
用法: python scripts/redwhite.py
输出: frontend/pic/red/red1.png … red8.png
"""

from __future__ import annotations

import os

import cv2
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "frontend", "pic")
OUT = os.path.join(SRC, "red")

RED = (9, 2, 159)  # BGR，取自 1.jpg 主色 rgb(159,2,9)
WHITE = (255, 255, 255)

# 每张图的处理参数
#   mode: light(浅底泛洪) / grabcut(深底油彩) / outline(白底线描稿：沿墨线外轮廓填实)
#   tol/inset: 抠图参数；ratio: outline 的墨线阈值（图的亮度 p99 的比例）
#   gamma: >1 把中间调压向红（头发之类不会发白）；white: 白色端点（<255 则整体更红）
CFG = {
    1: dict(mode="light", tol=45),
    2: dict(mode="outline", ratio=0.93),  # 线描稿：只按轮廓抠形；内部用统一红白映射，不加任何特殊提亮/压暗
    3: dict(mode="grabcut", inset=0.15, hi_pct=62, gamma=0.85),  # 同斯大林：油画无真白，白点压低
    4: dict(mode="light", tol=26),
    5: dict(mode="grabcut", inset=0.18, hi_pct=72, gamma=0.9),  # 原图最亮只到 211，白色点压低才白得起来
    6: dict(mode="light", tol=30, gamma=1.38, white=246),  # 头发偏白 → 压低中间调
    7: dict(mode="light", tol=30),
    8: dict(mode="light", tol=26),
}


def load(n: int) -> np.ndarray:
    for ext in (".jpg", ".png", ".jpeg"):
        p = os.path.join(SRC, f"{n}{ext}")
        if os.path.exists(p):
            return cv2.imread(p, cv2.IMREAD_COLOR)
    raise FileNotFoundError(n)


def largest(mask: np.ndarray) -> np.ndarray:
    n, lab, stats, _ = cv2.connectedComponentsWithStats(mask.astype(np.uint8), 8)
    if n <= 1:
        return mask
    i = 1 + int(np.argmax(stats[1:, cv2.CC_STAT_AREA]))
    return (lab == i).astype(np.uint8)


def mask_light(img: np.ndarray, tol: float) -> np.ndarray:
    """浅色/纯色底：从四边泛洪，得到背景，再取补集。"""
    h, w = img.shape[:2]
    ring = np.concatenate(
        [
            img[0:2].reshape(-1, 3),
            img[-2:].reshape(-1, 3),
            img[:, 0:2].reshape(-1, 3),
            img[:, -2:].reshape(-1, 3),
        ]
    )
    bg = np.median(ring, axis=0)
    diff = np.linalg.norm(img.astype(np.float32) - bg, axis=2)
    cand = (diff < tol).astype(np.uint8)
    # 从四边泛洪，避免把人物内部浅色（衬衫/高光）当背景
    ff = cand.copy()
    m = np.zeros((h + 2, w + 2), np.uint8)
    for seed in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]:
        if ff[seed[1], seed[0]]:
            cv2.floodFill(ff, m, seed, 2)
    bgmask = (ff == 2).astype(np.uint8)
    fg = 1 - bgmask
    fg = cv2.morphologyEx(fg, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))
    fg = cv2.morphologyEx(fg, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
    return largest(fg)


def mask_grabcut(img: np.ndarray, inset: float = 0.16) -> np.ndarray:
    """深色/油彩底：GrabCut，边框硬性当背景、中心当人物。"""
    h, w = img.shape[:2]
    gc = np.full((h, w), cv2.GC_PR_BGD, np.uint8)
    band = max(2, int(min(w, h) * 0.02))
    gc[0:band, :] = cv2.GC_BGD
    gc[-band:, :] = cv2.GC_BGD
    gc[:, 0:band] = cv2.GC_BGD
    gc[:, -band:] = cv2.GC_BGD
    i = int(min(w, h) * inset)
    gc[i:h - i, i:w - i] = cv2.GC_PR_FGD
    gc[i + h // 4:h - i - h // 4, i + w // 4:w - i - w // 4] = cv2.GC_FGD
    bgd, fgd = np.zeros((1, 65), np.float64), np.zeros((1, 65), np.float64)
    cv2.grabCut(img, gc, None, bgd, fgd, 6, cv2.GC_INIT_WITH_MASK)
    fg = np.where((gc == cv2.GC_FGD) | (gc == cv2.GC_PR_FGD), 1, 0).astype(np.uint8)
    fg = cv2.morphologyEx(fg, cv2.MORPH_CLOSE, np.ones((7, 7), np.uint8))
    fg = cv2.morphologyEx(fg, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
    return largest(fg)


def mask_outline(img: np.ndarray, ratio: float = 0.93) -> np.ndarray:
    """白底线描稿（如 2.jpg）：墨线是人物，纸是底。

    浅底泛洪会把「跟纸一样白的脸」当成背景一起刷掉（脸变红）。
    这里反过来：以墨线为边界，取最大外轮廓并**填实**，脸/头发在内的纸白整块算人物。
    """
    lum = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY).astype(np.float32)
    hi = float(np.percentile(lum, 99)) or 255.0
    ink = (lum < hi * ratio).astype(np.uint8)
    ink = cv2.morphologyEx(ink, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))
    cs, _ = cv2.findContours(ink, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if not cs:
        return np.ones(lum.shape, np.uint8)
    c = max(cs, key=cv2.contourArea)
    fg = np.zeros(lum.shape, np.uint8)
    cv2.drawContours(fg, [c], -1, 1, -1)
    fg = cv2.morphologyEx(fg, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))
    return largest(fg)


def duotone(
    img: np.ndarray,
    fg: np.ndarray,
    gamma: float = 1.0,
    white: float = 255.0,
    hi_pct: float = 98.0,
    ink: float = 0.0,
) -> np.ndarray:
    """红↔白线性双色调（等价 1.jpg 的调子）：亮处发白、暗处发红，保留照片层次。

    1.jpg 实测色 ≈ red + (white-red)*L / 255，这里按此线性映射，
    只用百分位把人物亮度拉伸到 0–1，避免整张脸糊成一片白。
    """
    lum = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY).astype(np.float32)
    vals = lum[fg == 1]
    if vals.size < 16:
        vals = lum.ravel()
    lo, hi = np.percentile(vals, [2, hi_pct])
    if hi - lo < 8:
        lo, hi = float(vals.min()), float(vals.max()) or 1.0
    t = np.clip((lum - lo) / (hi - lo), 0, 1)
    if ink > 0:
        # 线描稿专用：先把人物整块填白，再让墨线按 ink 比例压成淡红描线
        # （直接线性映射会让密集的排线把脸压成一片红，看着像「留空」）
        t = 1.0 - ink * (1.0 - t)
    if gamma != 1.0:
        t = t ** gamma
    t = t * (white / 255.0)
    red = np.array(RED, np.float32)
    w = np.array(WHITE, np.float32)
    out = red[None, None, :] + t[:, :, None] * (w - red)[None, None, :]
    out[fg == 0] = red
    return out.astype(np.uint8)


def add_ring(img: np.ndarray, fg: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """沿人物**四周外部**轮廓画一圈细白线（约图幅 0.3%，2px 左右）；人物内部颜色一律不动。"""
    h, w = img.shape[:2]
    r = max(2, int(round(min(w, h) * 0.006)))
    k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * r + 1, 2 * r + 1))
    grown = cv2.dilate(fg, k)
    ring = (grown == 1) & (fg == 0)
    out = img.copy()
    out[ring] = WHITE
    return out, ((grown == 1) | (ring)).astype(np.uint8)


def solidify(mask: np.ndarray) -> np.ndarray:
    """把轮廓内部的透明小洞填实，避免背景色从缝隙里透出来。"""
    h, w = mask.shape[:2]
    inv = (1 - mask).astype(np.uint8)
    ff = inv.copy()
    m = np.zeros((h + 2, w + 2), np.uint8)
    cv2.floodFill(ff, m, (0, 0), 2)
    outside = (ff == 2).astype(np.uint8)
    return (1 - outside).astype(np.uint8)


def crop(img: np.ndarray, fg: np.ndarray, pad_ratio: float = 0.04) -> np.ndarray:
    ys, xs = np.where(fg == 1)
    if len(xs) == 0:
        return img
    h, w = img.shape[:2]
    pad = int(round(min(w, h) * pad_ratio))
    x0, x1 = max(0, xs.min() - pad), min(w, xs.max() + pad + 1)
    y0, y1 = max(0, ys.min() - pad), min(h, ys.max() + pad + 1)
    return img[y0:y1, x0:x1]


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    for n in range(1, 9):
        cfg = CFG[n]
        img = load(n)
        h, w = img.shape[:2]
        if w < 520 or h < 520:  # 小图先放大，描边不会被糊掉
            s = max(520 / w, 520 / h)
            img = cv2.resize(img, (int(w * s), int(h * s)), interpolation=cv2.INTER_CUBIC)
        if cfg["mode"] == "grabcut":
            fg = mask_grabcut(img, cfg.get("inset", 0.16))
        elif cfg["mode"] == "outline":
            fg = mask_outline(img, cfg.get("ratio", 0.93))
        else:
            fg = mask_light(img, cfg["tol"])
        # 线描稿（马克思）：把墨线围出的内部小洞填实，且用原图亮度做红白映射。
        # 否则洞里是纯红 + 透明，叠到红色头部就「留空、透出背景色」。
        if cfg["mode"] == "outline":
            fg = solidify(fg)
        art, solid = duotone(
            img,
            fg,
            cfg.get("gamma", 1.0),
            cfg.get("white", 255.0),
            cfg.get("hi_pct", 98.0),
            cfg.get("ink", 0.0),
        ), None
        art, solid = add_ring(art, fg)
        # 内部一律填实：任何透明小洞叠到红色头部都会「留空、透出背景色」。
        solid = solidify(solid)
        art = crop(art, solid)
        solid = crop(solid, solid)
        # RGBA：底色透明（放到任意红色头部都不露边），人物+白描边不透明
        alpha = (solid * 255).astype(np.uint8)
        rgba = np.dstack([art, alpha])
        p = os.path.join(OUT, f"red{n}.png")
        cv2.imwrite(p, rgba)
        # 预览用的红底版放 .local，不进 assets
        p2 = os.path.join(ROOT, ".local", "redwhite_preview", f"red{n}_solid.png")
        os.makedirs(os.path.dirname(p2), exist_ok=True)
        bg = np.full_like(art, RED)
        bg[solid == 1] = art[solid == 1]
        cv2.imwrite(p2, bg)
        ys, xs = np.where(fg == 1)
        print(
            f"red{n}.png {art.shape[1]}x{art.shape[0]} 人物占比 {fg.mean():.2%} "
            f"bbox=({xs.min()},{ys.min()})-({xs.max()},{ys.max()})"
        )


if __name__ == "__main__":
    main()
