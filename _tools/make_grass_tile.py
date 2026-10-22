# -*- coding: utf-8 -*-
"""
生成「草地」地块素材（浮岛借木 / 千星奇域）

为什么不用 AI 生成这类地块：
  地块必须**严丝合缝铺满格子**，AI 出图会给成「等距菱形」视角（顶面是旋转 45° 的菱形），
  铺到正交方形网格上就变成一片菱形格纹 —— 数量级的问题，没法靠调参数救。
  而地块本身在参考图里就是「纯色方块 + 一点点质感」，程序化生成反而更准：
    · 顶面是**正方形**，四边水平/垂直（相机在正上方 + 前侧厚度，参考图就是这个观感）
    · 顶面 = 整格，岛缘描边 / 侧面厚度 / 水下投影由脚本画（两种路径同源，见 level.lua）
    · 顶面内留**很淡的接缝**，让相邻格还能数得清（纯色模式下靠深浅交替，素材模式下靠它）

输出：浮岛借木/素材/草地.png（1024×1024，顶面 900×900 居中，其余透明）
配套：config.DEFAULT_ART_FIT.land = { w = 1024/900, h = 1024/900, dy = 0 }
"""
import os

import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "浮岛借木", "素材", "草地.png")

SIZE = 1024
FACE = 900                 # 顶面边长
X0 = (SIZE - FACE) // 2
Y0 = X0
BASE = (109, 176, 60)      # = config.DEFAULT_PALETTE.land（6DB03C）
DARK = (94, 158, 51)       # = DEFAULT_PALETTE.landDark（5E9E33）

rng = np.random.default_rng(20260927)


def value_noise(n, cells, seed):
    """低频噪声：cells × cells 随机点双线性放大 + 平滑"""
    r = np.random.default_rng(seed)
    small = r.random((cells + 1, cells + 1))
    ys = np.linspace(0, cells, n, endpoint=False)
    xs = np.linspace(0, cells, n, endpoint=False)
    y0 = ys.astype(int); x0 = xs.astype(int)
    fy = (ys - y0)[:, None]; fx = (xs - x0)[None, :]
    fy = fy * fy * (3 - 2 * fy); fx = fx * fx * (3 - 2 * fx)      # smoothstep
    a = small[y0][:, x0]; b = small[y0][:, x0 + 1]
    c = small[y0 + 1][:, x0]; dd = small[y0 + 1][:, x0 + 1]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + dd * fx) * fy


def main():
    yy, xx = np.mgrid[0:FACE, 0:FACE].astype(np.float64)

    # ① 底色：**纯平**。
    #   ⚠️ 这里绝对不能加「上亮下暗」的竖向渐变 —— 那是一张瓦片自己的明暗，
    #      平铺时每张瓦片的顶部都更亮、底部都更暗，整片草地就出现等距的
    #      横向条纹（实测绿通道在 159↔182 之间按格周期锯齿）。
    #      瓦片内部的低频/高频变化要能被 **平铺平均掉**，否则就是「可重复的噪声」
    #      而不是「随机质感」。所以底色定死，质感全部交给下面两层噪声。
    img = np.zeros((FACE, FACE, 3))
    for k in range(3):
        img[:, :, k] = BASE[k]

    # ② 有机质感：两层低频噪声 + 一层细颗粒
    n1 = value_noise(FACE, 7, 11)
    n2 = value_noise(FACE, 23, 12)
    fine = rng.normal(0, 1.0, (FACE, FACE))
    tint = ((n1 - 0.5) * 11 + (n2 - 0.5) * 7 + fine * 2.2)[:, :, None]
    img += tint

    # ③ 草丛小点：随机散布的小亮/暗斑
    specks = np.zeros((FACE, FACE))
    for _ in range(360):
        sx, sy = rng.integers(0, FACE, 2)
        r = int(rng.integers(2, 5))
        y1, y2 = max(0, sy - r), min(FACE, sy + r + 1)
        x1, x2 = max(0, sx - r), min(FACE, sx + r + 1)
        specks[y1:y2, x1:x2] += float(rng.normal(0, 1)) * 12
    specks = np.asarray(Image.fromarray(((specks + 128).clip(0, 255)).astype(np.uint8))
                        .filter(ImageFilter.GaussianBlur(1.6)), dtype=np.float64) - 128
    img += specks[:, :, None]

    # ④ 淡接缝：贴着顶面四周往里的**四边对称**微弱压暗，相邻格之间正好合成一条细沟。
    #    它是玩家在素材模式下数格子的依据（纯色模式那边靠深浅交替棋盘）。
    #    用连续的软衰减而不是硬边 —— 缩放下来不会出现 1px 的锯齿。
    seam = 26
    d_edge = np.minimum(np.minimum(yy, FACE - 1 - yy), np.minimum(xx, FACE - 1 - xx))
    t = np.clip((seam - d_edge) / seam, 0.0, 1.0)
    t = t * t * (3 - 2 * t)                     # smoothstep
    for k in range(3):
        img[:, :, k] -= t * (BASE[k] - DARK[k]) * 0.95

    # ⑤ 圆角（很小，接上时看不出缺口，但单独摆着不硬）
    rad = 12
    alpha = np.full((FACE, FACE), 255.0)
    yy2, xx2 = np.mgrid[0:FACE, 0:FACE]
    for cx, cy in ((rad, rad), (FACE - rad, rad), (rad, FACE - rad), (FACE - rad, FACE - rad)):
        d = np.sqrt((xx2 - cx) ** 2 + (yy2 - cy) ** 2)
        corner = ((xx2 < rad) if cx == rad else (xx2 > FACE - rad)) & \
                 ((yy2 < rad) if cy == rad else (yy2 > FACE - rad))
        alpha[corner & (d > rad)] = 0
        edge = corner & (d > rad - 3) & (d <= rad)
        alpha[edge] = np.minimum(alpha[edge], (rad - d[edge]) / 3 * 255)

    face = Image.fromarray(np.dstack([img.clip(0, 255).astype(np.uint8),
                                      alpha.astype(np.uint8)]), "RGBA")

    out = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    out.paste(face, (X0, Y0), face)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    out.save(OUT)
    print("已生成 %s（顶面 %dx%d 居中，透明边 %d px）" % (OUT, FACE, FACE, X0))
    print("配套 config: DEFAULT_ART_FIT.land = { w = %.3f, h = %.3f, dy = 0 }" % (SIZE / FACE, SIZE / FACE))
    # 自检：横向铺 3 张，**只看每张瓦片的中段**（排除两端刻意做的接缝），
    # 这里应该是平的；极差偏大就说明又混进了瓦片自身的明暗渐变。
    strip = np.concatenate([np.asarray(out)[Y0:Y0 + FACE, X0:X0 + FACE]] * 3, axis=1).astype(np.float64)
    prof = strip[:, :, 1].mean(axis=1)
    inner = np.concatenate([prof[seam:FACE - seam] for _ in range(3)])
    print("平铺自检：格内亮度 均值 %.2f 极差 %.2f（极差 > 8 说明还有条纹）"
          % (inner.mean(), inner.max() - inner.min()))
    print("平铺自检：接缝处亮度 %.2f（应明显低于格内均值 %d 左右）"
          % (prof[0], int(inner.mean())))



if __name__ == "__main__":
    main()
